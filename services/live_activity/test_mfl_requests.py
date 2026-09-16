import io
import json
import tempfile
import unittest
import urllib.error
from email.message import Message
from email.utils import formatdate
from pathlib import Path
from mfl_requests import MFL, MFLThrottled


class Clock:
    def __init__(self): self.now = 1800000000.0
    def __call__(self): return self.now
    def sleep(self, seconds): self.now += seconds


class Reply(io.BytesIO):
    headers = {}


class Upstream:
    def __init__(self, clock): self.clock, self.calls, self.retry = clock, [], None
    def open(self, request, timeout):
        self.calls.append((self.clock(), request.host))
        if self.retry is not None:
            headers = Message(); headers['Retry-After'] = self.retry
            raise urllib.error.HTTPError(request.full_url, 429, 'limit', headers, None)
        return Reply(json.dumps({'liveScoring': {'week': '1'}}).encode())


class RequestBudgetTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock(); self.upstream = Upstream(self.clock)
        self.leagues = {'2026.41333': 'www45.myfantasyleague.com', '2026.12345': 'www45.myfantasyleague.com'}
        self.client = MFL(self.leagues, clock=self.clock, sleep=self.clock.sleep, opener=self.upstream)

    def test_shared_scores_keep_original_receipt_and_isolate_mutations(self):
        data, checked = self.client.read_with_receipt(2026, '41333', 1)
        data['liveScoring']['week'] = '9'
        self.clock.now += 40
        again, receipt = self.client.read_with_receipt(2026, '41333', 1)
        self.assertEqual(again['liveScoring']['week'], '1')
        self.assertEqual(receipt, checked)
        self.assertEqual(len(self.upstream.calls), 1)
        self.clock.now += 21
        self.client.read(2026, '41333', 1)
        self.assertEqual(len(self.upstream.calls), 2)

    def test_same_server_leagues_are_paced(self):
        self.client.read(2026, '41333', 1)
        self.client.read(2026, '12345', 1)
        self.assertGreaterEqual(self.upstream.calls[1][0]-self.upstream.calls[0][0], 1.25)

    def test_cooldown_shared_across_leagues_and_persists_restart(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root)/'limits.sqlite3'
            self.upstream.retry = formatdate(self.clock()+600, usegmt=True)
            for league in ('41333', '12345'):
                client = MFL(self.leagues, path, clock=self.clock, sleep=self.clock.sleep, opener=self.upstream)
                with self.assertRaises(MFLThrottled): client.read(2026, league, 1)
                client.db.close()
            self.assertEqual(len(self.upstream.calls), 1)
            self.clock.now += 601
            self.upstream.retry = None
            client = MFL(self.leagues, path, clock=self.clock, sleep=self.clock.sleep, opener=self.upstream)
            client.read(2026, '41333', 1)
            self.assertEqual(len(self.upstream.calls), 2)

    def test_non_league_feeds_share_api_host_budget(self):
        self.client.export(2026, '41333', 1, 'nflSchedule')
        self.client.export(2026, '12345', 1, 'nflSchedule')
        self.client.export(2026, '41333', 1, 'injuries')
        self.assertEqual(len(self.upstream.calls), 2)
        self.assertTrue(all(host == 'api.myfantasyleague.com' for _, host in self.upstream.calls))
        self.assertGreaterEqual(self.upstream.calls[1][0]-self.upstream.calls[0][0], 1.25)

    def test_bad_retry_headers_use_finite_fallback(self):
        for value in (None, 'nan', 'inf', '-20', 'garbage', '1e100'):
            self.assertEqual(MFL.retry_delay(value, self.clock()), 90)
        self.assertEqual(MFL.retry_delay('120', self.clock()), 120)


if __name__ == '__main__': unittest.main()
