import hashlib
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from server import Denied, Gateway, Limited, Server


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.now = 10000
        self.token = 'a' * 43
        self.second = 'b' * 43
        self.calls = []
        self.config = {'teams': {f'2026.12345.{n:04}':
            {'id': 'blitz-beta-' + str(n), 'season': 2026, 'leagueID': '12345', 'franchiseID': f'{n:04}', 'expires': 20000}
            for n, token in enumerate((self.token, self.second), 1)}}
        self.path = self.root / 'testers.json'
        self.save()
        self.gateway = Gateway(self.path, self.root / 'state.sqlite3', clock=lambda: self.now, transport=self.transport)
        for n, token in enumerate((self.token, self.second), 1):
            self.gateway.db.execute('INSERT INTO grants VALUES (?,?,?)', (hashlib.sha256(token.encode()).hexdigest(), f'2026.12345.{n:04}', 20000))
        self.gateway.db.commit()
        self.headers = {'X-Blitz-Access': self.token, 'Authorization': 'Bearer ' + 'c' * 64}
        self.body = json.dumps({'season': 2026, 'leagueID': '12345', 'franchiseID': '0001'}).encode()
    def tearDown(self):
        self.gateway.db.close()
        self.temp.cleanup()
    def save(self):
        self.path.write_text(json.dumps(self.config))
    def transport(self, *args):
        self.calls.append(args)
        return 200, {'registered': True, 'pushReady': True, 'productionPushReady': True, 'expiresAt': 15000, 'private': 'must not expose status'}
    def test_missing_invalid_revoked_and_expired_credentials_never_reach_upstream(self):
        for token in ('', 'x' * 43, '../secret'):
            with self.assertRaises(Denied):
                self.gateway.request('GET', '/v1/status', {'X-Blitz-Access': token})
        self.config['teams'].pop('2026.12345.0001')
        self.save()
        with self.assertRaises(Denied):
            self.gateway.request('GET', '/v1/status', self.headers)
        self.now = 20001
        with self.assertRaises(Denied):
            self.gateway.request('GET', '/v1/status', {'X-Blitz-Access': self.second})
        self.assertEqual(self.calls, [])
    def test_access_receipt_is_scoped_and_does_not_forward_credentials(self):
        code, value = self.gateway.request('GET', '/v1/access', self.headers)
        self.assertEqual((code, value['franchiseID'], value['leagueID']), (200, '0001', '12345'))
        self.assertNotIn('id', value)
        self.assertEqual(self.calls, [])
    def test_shared_nfl_cache_only_has_allowlisted_headers(self):
        headers = self.headers | {'Cookie': 'private', 'Tailscale-User-Login': 'attacker', 'X-Blitz-NFL-Teams': 'DAL,NYG'}
        self.gateway.request('GET', '/v1/seasons/2026/weeks/2', headers)
        port, _, _, sent, _ = self.calls[-1]
        self.assertEqual(port, 8793)
        self.assertEqual(sent, {'X-Blitz-NFL': '1', 'X-Blitz-NFL-Teams': 'DAL,NYG'})
    def test_arbitrary_urls_wrong_season_and_browser_calls_are_denied(self):
        for path in ('https://evil.invalid', '/v1/seasons/2025/weeks/2', '/admin', '/v1/status?url=evil', '/v1/../status'):
            with self.assertRaises(Denied):
                self.gateway.request('GET', path, self.headers)
        with self.assertRaises(Denied):
            self.gateway.request('GET', '/v1/status', self.headers | {'Origin': 'https://example.test'})
        self.assertEqual(self.calls, [])
    def test_status_does_not_leak_other_tester_activity_counts(self):
        _, value = self.gateway.request('GET', '/v1/status', self.headers)
        self.assertNotIn('private', value)
        self.assertEqual(value['subscriptions'], 0)
    def test_lineup_and_activity_registration_must_include_invited_team(self):
        for body in ({'season': 2026, 'leagueID': '12345', 'franchiseID': '0002'},
                     {'season': 2026, 'leagueID': '54321', 'franchiseID': '0001'}):
            with self.assertRaises(Denied):
                self.gateway.request('PUT', '/v1/lineup-alerts/a', self.headers, json.dumps(body).encode())
        with self.assertRaises(Denied):
            self.gateway.request('PUT', '/v1/activities/a', self.headers, json.dumps({'season': 2026, 'leagueID': '12345', 'homeID': '0002', 'awayID': '0003'}).encode())
        self.assertEqual(self.calls, [])
    def test_timeline_only_includes_own_matchup(self):
        self.gateway.request('GET', '/v1/timeline/2026/12345/2/0001/0002', self.headers)
        with self.assertRaises(Denied):
            self.gateway.request('GET', '/v1/timeline/2026/12345/2/0003/0002', self.headers)
        self.assertEqual(len(self.calls), 1)
    def test_registration_limit_delete_ownership_and_device_secret_survive_restart(self):
        for sid in ('a', 'b', 'd', 'e'):
            self.gateway.request('PUT', '/v1/lineup-alerts/' + sid, self.headers, self.body)
        with self.assertRaises(Limited):
            self.gateway.request('PUT', '/v1/lineup-alerts/c', self.headers, self.body)
        self.gateway.db.close()
        self.gateway = Gateway(self.path, self.root / 'state.sqlite3', clock=lambda: self.now, transport=self.transport)
        for headers in (self.headers | {'X-Blitz-Access': self.second}, self.headers | {'Authorization': 'Bearer ' + 'd' * 64}):
            with self.assertRaises(Denied):
                self.gateway.request('DELETE', '/v1/lineup-alerts/a', headers)
        self.gateway.request('DELETE', '/v1/lineup-alerts/a', self.headers)
        self.gateway.request('PUT', '/v1/lineup-alerts/c', self.headers, self.body)
        before = len(self.calls)
        self.gateway.request('DELETE', '/v1/lineup-alerts/unknown', self.headers)
        self.assertEqual(len(self.calls), before)
    def test_per_tester_rate_limit_and_new_minute(self):
        for _ in range(60):
            self.gateway.request('GET', '/v1/access', self.headers)
        with self.assertRaises(Limited):
            self.gateway.request('GET', '/v1/access', self.headers)
        self.gateway.request('GET', '/v1/access', {'X-Blitz-Access': self.second})
        self.now += 60
        self.gateway.request('GET', '/v1/access', self.headers)
    def test_real_http_rejects_missing_auth_and_accepts_scoped_receipt(self):
        server = Server(('127.0.0.1', 0), self.gateway)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for headers, expected in (({}, 403), (self.headers, 200)):
                connection = http.client.HTTPConnection('127.0.0.1', server.server_port)
                connection.request('GET', '/v1/access', headers=headers)
                response = connection.getresponse()
                self.assertEqual(response.status, expected)
                self.assertEqual(response.getheader('Cache-Control'), 'no-store')
                self.assertNotIn(self.token, response.read().decode())
                connection.close()
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def enrollment(self, token='e' * 43, franchise='0001', cookie='synthetic-session'):
        return json.dumps(dict(season=2026, leagueID='12345', franchiseID=franchise,
                               deviceCredential=token, mflSession=cookie)).encode()

    def test_automatic_access_requires_verified_membership_and_does_not_store_session(self):
        checked = []
        self.gateway.verify_membership = lambda *args: checked.append(args) or False
        with self.assertRaises(Denied):
            self.gateway.request('POST', '/v1/access', {}, self.enrollment())
        self.now += 3
        self.gateway.verify_membership = lambda *args: checked.append(args) or True
        code, result = self.gateway.request('POST', '/v1/access', {}, self.enrollment())
        self.assertEqual((code, result['franchiseID']), (200, '0001'))
        self.assertEqual(checked[-1], (2026, '12345', '0001', 'synthetic-session'))
        self.assertNotIn('synthetic-session', str(list(self.gateway.db.iterdump())))
        self.assertNotIn('e' * 43, str(list(self.gateway.db.iterdump())))
        self.gateway.request('GET', '/v1/status', {'X-Blitz-Access': 'e' * 43})
        self.gateway.request('POST', '/v1/access', {}, self.enrollment())
        self.assertEqual(len(checked), 2)  # Retry reuses verified grant.
        self.gateway.request('DELETE', '/v1/access', {'X-Blitz-Access': 'e' * 43})
        with self.assertRaises(Denied):
            self.gateway.request('GET', '/v1/status', {'X-Blitz-Access': 'e' * 43})

    def test_coowners_receive_independent_credentials_for_the_same_team(self):
        self.gateway.verify_membership = lambda *args: True
        for token in ('e' * 43, 'f' * 43):
            self.gateway.request('POST', '/v1/access', {}, self.enrollment(token=token))
            self.now += 3
            _, receipt = self.gateway.request('GET', '/v1/access', {'X-Blitz-Access': token})
            self.assertEqual(receipt['franchiseID'], '0001')
        self.gateway.request('DELETE', '/v1/access', {'X-Blitz-Access': 'e' * 43})
        self.gateway.request('GET', '/v1/access', {'X-Blitz-Access': 'f' * 43})

    def test_uninvited_team_and_invalid_cookie_never_check_mfl(self):
        checks = []
        self.gateway.verify_membership = lambda *args: checks.append(args) or True
        for payload in (self.enrollment(franchise='9999'), self.enrollment(cookie='abc;other=secret'),
                        self.enrollment(cookie='abc\r\nInjected: hi')):
            with self.assertRaises(Denied):
                self.gateway.request('POST', '/v1/access', {}, payload)
        self.assertEqual(checks, [])

    def test_mfl_rate_limit_persists_across_gateway_restart(self):
        checks = []
        def limited(*args):
            checks.append(args)
            raise Limited()
        self.gateway.verify_membership = limited
        with self.assertRaises(Limited):
            self.gateway.request('POST', '/v1/access', {}, self.enrollment())
        self.gateway.db.close()
        self.gateway = Gateway(self.path, self.root / 'state.sqlite3', clock=lambda: self.now,
                               transport=self.transport, verify_membership=limited)
        self.now += 60
        with self.assertRaises(Limited):
            self.gateway.request('POST', '/v1/access', {}, self.enrollment(token='f' * 43))
        self.assertEqual(len(checks), 1)


if __name__ == '__main__':
    unittest.main()
