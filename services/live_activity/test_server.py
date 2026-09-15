import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from scoring import APPLE_EPOCH, payload, read_matchup, updated_state, validate_subscription
from server import APNs, MAX_LIFETIME, Service

NOW = 1789322400
CONFIG = {'allowedLogins': ['owner@example.test'], 'leagues': {'2026.12345': 'www45.myfantasyleague.com'}}


def subscription():
    return {'season': 2026, 'leagueID': '12345', 'week': 1, 'homeID': '0001', 'awayID': '0002',
            'homeAbbreviation': 'HOME', 'awayAbbreviation': 'AWAY', 'precision': 1, 'revision': 1,
            'token': 'ab' * 32, 'environment': 'sandbox', 'playerNames': {'10': 'First Player', '20': 'Second Player'},
            'state': {'homeScore': '3.0', 'awayScore': '4.0', 'activePlayers': 2,
                      'updatedAt': NOW - APPLE_EPOCH, 'homeRecord': '0–0',
                      'homeArtwork': {'red': .7, 'green': .1, 'blue': .2, 'thumbnail': 'eA=='}}}


def document(home='3.0', away='4.0', clock=2000):
    return {'liveScoring': {'week': '1', 'matchup': {'franchise': [
        {'id': tid, 'score': total, 'players': {'player': {'id': pid, 'status': 'starter', 'score': total,
                                                      'gameSecondsRemaining': str(clock)}}}
        for tid, pid, total in [('0001', '10', home), ('0002', '20', away)]]}}}


class FakeMFL:
    def __init__(self):
        self.calls = 0
        self.value = document()
        self.fail = False
    def read(self, *args):
        self.calls += 1
        if self.fail:
            raise ValueError('sensitive upstream error never exposed')
        return copy.deepcopy(self.value)


class FakeAPNs:
    ready = True
    def __init__(self):
        self.calls = []
        self.result = 200
    def send(self, body, data, now):
        self.calls.append((copy.deepcopy(body), json.loads(data), now))
        return self.result


class ScoringTests(unittest.TestCase):
    def projected_subscription(self):
        value = subscription()
        value.update(homeStarterIDs=['10'], awayStarterIDs=['20'], starterProjections={'10': 18, '20': 36})
        return validate_subscription(value, NOW, CONFIG['leagues'])

    def projected_document(self, clock=1800):
        d = document(clock=clock)
        for f in d['liveScoring']['matchup']['franchise']:
            f.update(playersYetToPlay=int(clock == 3600), playersCurrentlyPlaying=int(0 < clock < 3600))
        return d

    def test_live_estimates_recalculate_from_official_total_and_remaining_clock(self):
        value = self.projected_subscription()
        for clock, home, away in [(3600, '21.0', '40.0'), (1800, '12.0', '22.0'), (0, '3.0', '4.0')]:
            state = updated_state(value, read_matchup(self.projected_document(clock), value), NOW)
            self.assertEqual((state['homeProjection'], state['awayProjection']), (home, away))
            self.assertEqual(state['homeScore'], '3.0')
            self.assertNotIn('homeRecord', state)

    def test_estimates_clear_when_inputs_are_incomplete(self):
        for fault in ('projection', 'clock', 'aggregate', 'lineup', 'unknown'):
            value = self.projected_subscription(); d = self.projected_document()
            value['state']['homeProjection'] = '999.0'
            f = d['liveScoring']['matchup']['franchise'][0]
            if fault == 'projection': value['starterProjections'].pop('10')
            if fault == 'clock': f['players']['player'].pop('gameSecondsRemaining')
            if fault == 'aggregate': f['playersCurrentlyPlaying'] = 2
            if fault == 'lineup': value['homeStarterIDs'].append('11')
            if fault == 'unknown': f['players']['player']['status'] = 'unknown'
            state = updated_state(value, read_matchup(d, value), NOW)
            self.assertNotIn('homeProjection', state, fault)
            self.assertEqual(state['awayProjection'], '22.0')

    def test_finished_starter_needs_no_projection_and_corrections_remain_signed(self):
        value = self.projected_subscription(); value['starterProjections'] = {}
        d = self.projected_document(0)
        d['liveScoring']['matchup']['franchise'][0]['score'] = '-1.5'
        state = updated_state(value, read_matchup(d, value), NOW)
        self.assertEqual(state['homeProjection'], '-1.5')

    def test_final_needs_two_complete_reads_with_same_expected_starters(self):
        value = self.projected_subscription(); teams = read_matchup(self.projected_document(0), value)
        value.update(baseline=teams, baselineAt=NOW)
        self.assertEqual(updated_state(value, teams, NOW + 30)['phase'], 'waiting')
        final = updated_state(value, teams, NOW + 90)
        self.assertEqual(final['phase'], 'final')
        self.assertNotIn('homeProjection', final)
        self.assertEqual(updated_state(value, teams, NOW + 211)['phase'], 'waiting')
        value['homeStarterIDs'].append('11')
        incomplete = read_matchup(self.projected_document(0), value)
        self.assertEqual(updated_state(value, incomplete, NOW + 90)['phase'], 'waiting')

    def test_projection_registration_rejects_invalid_numbers_and_duplicate_starters(self):
        for changes in [dict(starterProjections={'10': 'NaN'}), dict(starterProjections={'bad': 12}),
                        dict(homeStarterIDs=['10', '10']), dict(awayStarterIDs=[]), dict(starterProjections={'10': True})]:
            value = subscription(); value.update(changes)
            with self.assertRaises(ValueError): validate_subscription(value, NOW, CONFIG['leagues'])

    def test_dates_and_payload_contract(self):
        value = validate_subscription(subscription(), NOW, CONFIG['leagues'])
        state = updated_state(value, read_matchup(document(), value), NOW)
        data = json.loads(payload(state, NOW))
        self.assertEqual(data['aps']['timestamp'], NOW)
        self.assertEqual(data['aps']['stale-date'], NOW + 210)
        self.assertEqual(data['aps']['content-state']['updatedAt'], NOW - APPLE_EPOCH)
        self.assertNotIn('homeRecord', state)
        self.assertEqual(state['homeArtwork']['thumbnail'], 'eA==')

    def with_baseline(self):
        value = validate_subscription(subscription(), NOW, CONFIG['leagues'])
        value['baseline'] = read_matchup(document(), value)
        value['baselineAt'] = NOW
        return value

    def test_named_player_positive_and_negative(self):
        value = self.with_baseline()
        for total, expected in [('9', 'First Player +6.0 pts · HOME'), ('2', 'First Player −1.0 pts · HOME')]:
            state = updated_state(value, read_matchup(document(home=total), value), NOW + 90)
            self.assertEqual(state['latestChange']['text'], expected)

    def test_both_teams_change_without_guessed_order(self):
        value = self.with_baseline()
        state = updated_state(value, read_matchup(document('9', '7'), value), NOW + 90)
        self.assertEqual(state['latestChange']['text'], 'AWAY +3.0 pts · HOME +6.0 pts')

    def test_missing_scores_wrong_week_duplicates_rejected(self):
        for mutation in [lambda d: d['liveScoring'].update(week='2'),
                         lambda d: d['liveScoring']['matchup']['franchise'][0].pop('score'),
                         lambda d: d['liveScoring']['matchup']['franchise'][0].update(score='NaN'),
                         lambda d: d['liveScoring']['matchup']['franchise'].append(d['liveScoring']['matchup']['franchise'][0])]:
            d = document(); mutation(d)
            with self.assertRaises(ValueError):
                read_matchup(d, subscription())

    def test_unreconciled_missing_or_changed_lineup_uses_team_delta(self):
        value = self.with_baseline()
        for mutation in [lambda p: p.update(score='3'), lambda p: p.pop('score'), lambda p: p.update(id='99')]:
            d = document('9'); mutation(d['liveScoring']['matchup']['franchise'][0]['players']['player'])
            state = updated_state(value, read_matchup(d, value), NOW + 90)
            self.assertEqual(state['latestChange']['text'], 'HOME +6.0 pts')

    def test_gap_resets_change_and_unchanged_preserves_timestamp(self):
        value = self.with_baseline()
        teams = read_matchup(document('9'), value)
        value['state'] = updated_state(value, teams, NOW + 90)
        value['baseline'] = teams; value['baselineAt'] = NOW + 90
        state = updated_state(value, teams, NOW + 180)
        self.assertEqual(state['latestChange']['checkedAt'], NOW + 90 - APPLE_EPOCH)
        self.assertNotIn('latestChange', updated_state(value, teams, NOW + 400))

    def test_final_requires_complete_explicit_zero_starter_clocks(self):
        value = subscription()
        for clock, phase in [(0, 'waiting'), (3600, 'waiting'), (2000, 'live')]:
            state = updated_state(value, read_matchup(document(clock=clock), value), NOW)
            self.assertEqual(state['phase'], phase)
        d = document(clock=0)
        d['liveScoring']['matchup']['franchise'][0]['players']['player'].pop('gameSecondsRemaining')
        self.assertEqual(updated_state(value, read_matchup(d, value), NOW)['phase'], 'waiting')

    def test_untrusted_registration_fields_are_not_stored(self):
        value = subscription(); value.update(cookie='private', password='private', url='http://127.0.0.1')
        value['state']['unexpected'] = 'private'
        body = validate_subscription(value, NOW, CONFIG['leagues'])
        self.assertNotIn('private', json.dumps(body))
        for key, invalid in [('leagueID', '99999'), ('token', 'not-a-token'), ('environment', 'other'), ('precision', 5)]:
            value = subscription(); value[key] = invalid
            with self.assertRaises(ValueError):
                validate_subscription(value, NOW, CONFIG['leagues'])
        with self.assertRaises(ValueError):
            validate_subscription(subscription(), NOW + 211, CONFIG['leagues'])

    def test_native_four_decimal_and_grouped_scores(self):
        value = subscription(); value['precision'] = 4
        value['state']['homeScore'] = '1,234.5678'
        result = validate_subscription(value, NOW, CONFIG['leagues'])
        self.assertEqual(result['state']['homeScore'], '1234.5678')

    def test_combined_static_dynamic_budget_keeps_normal_logos(self):
        state = subscription()['state']
        for side in ('homeArtwork', 'awayArtwork'):
            state[side] = {'red': .7, 'green': .1, 'blue': .2, 'thumbnail': 'A' * 1200}
        normal = json.loads(payload(state, NOW, attribute_bytes=350))['aps']['content-state']
        self.assertIn('thumbnail', normal['homeArtwork'])
        large = json.loads(payload(state, NOW, attribute_bytes=1800))['aps']['content-state']
        self.assertNotIn('thumbnail', large['homeArtwork'])
        self.assertLess(len(json.dumps(large).encode()) + 1800, 4096)

    def test_payload_size_fallback_keeps_colors(self):
        state = subscription()['state']
        for side in ('homeArtwork', 'awayArtwork'):
            state[side] = {'red': .7, 'green': .1, 'blue': .2, 'thumbnail': 'A' * 3000}
        data = payload(state, NOW)
        self.assertLessEqual(len(data), 4096)
        art = json.loads(data)['aps']['content-state']['homeArtwork']
        self.assertNotIn('thumbnail', art)
        self.assertEqual(art['red'], .7)


class ServiceTests(unittest.TestCase):
    def test_foreground_re_registration_preserves_delivered_art_and_newer_estimate(self):
        self.register(); self.service.tick()
        saved = json.loads(self.service.db.execute('SELECT body FROM subscriptions').fetchone()[0])
        saved['state']['homeProjection'] = '123.4'
        self.service.db.execute('UPDATE subscriptions SET body=?', (json.dumps(saved),)); self.service.db.commit()
        incoming = subscription(); incoming['revision'] = 2
        incoming['state'].pop('homeArtwork')
        incoming['state']['homeProjection'] = '10.0'
        self.service.register('one', 'owner-hash', incoming)
        body = json.loads(self.service.db.execute('SELECT body FROM subscriptions').fetchone()[0])
        self.assertEqual(body['state']['homeArtwork'], saved['state']['homeArtwork'])
        self.assertEqual(body['state']['homeProjection'], '123.4')
        self.now += 90; self.service.tick()
        self.assertEqual(self.push.calls[-1][1]['aps']['content-state']['homeArtwork'], saved['state']['homeArtwork'])

    def test_same_palette_keeps_thumbnail_but_new_palette_replaces_it(self):
        self.register()
        for revision, red, has_thumbnail in [(2, .7, True), (3, .2, False)]:
            value = subscription(); value['revision'] = revision
            value['state']['homeArtwork'].pop('thumbnail'); value['state']['homeArtwork']['red'] = red
            self.service.register('one', 'owner-hash', value)
            body = json.loads(self.service.db.execute('SELECT body FROM subscriptions').fetchone()[0])
            self.assertEqual(bool(body['state']['homeArtwork'].get('thumbnail')), has_thumbnail)
            self.assertEqual(body['state']['homeArtwork']['red'], red)

    def test_lifecycle_reasons_are_bounded_and_contain_no_credentials(self):
        self.register(); self.service.delete('one', 'owner-hash')
        for _ in range(100): self.service.lifecycle('Synthetic event')
        events = self.service.db.execute('SELECT at,event FROM lifecycle').fetchall()
        self.assertEqual(len(events), 64)
        self.assertNotIn('ab' * 32, json.dumps(events))

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = str(Path(self.temp.name) / 'test.sqlite3')
        self.now = NOW; self.mfl = FakeMFL(); self.push = FakeAPNs()
        self.service = Service(CONFIG, self.path, self.mfl, self.push, lambda: self.now)
    def tearDown(self):
        self.service.db.close(); self.temp.cleanup()
    def register(self, sid='one', **changes):
        value = subscription(); value.update(changes)
        value['state']['updatedAt'] = self.now - APPLE_EPOCH
        return self.service.register(sid, 'owner-hash', value)

    def test_coalesces_league_polls_and_persists_cooldown(self):
        self.register(); self.register('two')
        self.service.tick(); self.service.tick()
        self.assertEqual(self.mfl.calls, 1); self.assertEqual(len(self.push.calls), 2)
        self.service.db.close()
        self.service = Service(CONFIG, self.path, self.mfl, self.push, lambda: self.now)
        self.service.tick(); self.assertEqual(self.mfl.calls, 1)
        self.now += 90; self.service.tick(); self.assertEqual(self.mfl.calls, 2)

    def test_missing_push_key_performs_no_poll(self):
        self.push.ready = False; self.register(); self.service.tick()
        self.assertEqual(self.mfl.calls, 0)

    def test_token_rotation_old_request_does_not_restore_old_token(self):
        self.register(); self.register(token='cd' * 32, revision=3); self.register(token='ef' * 32, revision=2)
        self.service.tick(); self.assertEqual(self.push.calls[0][0]['token'], 'cd' * 32)
        self.assertEqual(self.service.status()['subscriptions'], 1)

    def test_delete_and_late_registration_cannot_resurrect(self):
        self.register(); self.service.delete('one', 'owner-hash')
        with self.assertRaises(ValueError): self.register()
        self.service.tick(); self.assertEqual(self.mfl.calls, 0)
        self.service.delete('never-arrived', 'owner-hash')
        with self.assertRaises(ValueError): self.register('never-arrived')

    def test_different_owner_cannot_replace_or_delete(self):
        self.register()
        with self.assertRaises(PermissionError): self.service.register('one', 'other', subscription())
        with self.assertRaises(PermissionError): self.service.delete('one', 'other')
        self.assertEqual(self.service.status()['subscriptions'], 1)

    def test_expiry_not_extended_by_foreground_refresh(self):
        first = self.register(); self.now += 1000
        self.assertEqual(self.register(revision=2)['expiresAt'], first['expiresAt'])
        self.now = NOW + MAX_LIFETIME + 1
        self.service.tick(); self.assertEqual(self.service.status()['subscriptions'], 0)
        self.assertEqual(self.mfl.calls, 0)

    def test_upstream_failure_retains_last_timestamp_and_backs_off(self):
        self.register(); self.service.tick(); self.now += 90; self.mfl.fail = True
        self.service.tick(); self.assertEqual(len(self.push.calls), 1)
        self.now += 90; self.service.tick(); self.assertEqual(self.mfl.calls, 2)
        body = json.loads(self.service.db.execute('SELECT body FROM subscriptions').fetchone()[0])
        self.assertEqual(body['state']['updatedAt'], NOW - APPLE_EPOCH)

    def test_invalidated_token_and_final_end_remove_subscription(self):
        self.register(); self.push.result = 410; self.service.tick()
        self.assertEqual(self.service.status()['subscriptions'], 0)
        self.register('two'); self.push.result = 200; self.mfl.value = document(clock=0)
        self.now += 90; self.service.tick()
        self.assertEqual(self.push.calls[-1][1]['aps']['event'], 'update')
        self.assertEqual(self.service.status()['subscriptions'], 1)
        self.now += 90; self.service.tick()
        self.assertEqual(self.push.calls[-1][1]['aps']['event'], 'end')
        self.assertEqual(self.service.status()['subscriptions'], 0)

    def test_newer_server_score_survives_registration(self):
        self.register(); self.mfl.value = document('9'); self.service.tick()
        self.register(revision=2)
        body = json.loads(self.service.db.execute('SELECT body FROM subscriptions').fetchone()[0])
        self.assertEqual(body['state']['homeScore'], '9.0')

    def test_authentication_errors_pause_pushes(self):
        self.register(); self.push.result = 403; self.service.tick()
        self.now += 90; self.service.tick(); self.assertEqual(len(self.push.calls), 1)
        self.assertEqual(self.service.last_error, 'Apple push configuration needs attention')

    def test_transient_push_failure_retries_new_read_and_delta(self):
        self.register(); self.service.tick(); self.now += 90; self.mfl.value = document('9')
        self.push.result = 503; self.service.tick()
        self.now += 90; self.push.result = 200; self.service.tick()
        state = self.push.calls[-1][1]['aps']['content-state']
        self.assertEqual(state['latestChange']['text'], 'First Player +6.0 pts · HOME')
        self.assertEqual(state['latestChange']['checkedAt'], NOW + 90 - APPLE_EPOCH)


class APNsTests(unittest.TestCase):
    def test_real_curl_preserves_unicode_and_json_bytes(self):
        # Exercise curl's config parser and HTTP body, not a JSON-only mock.
        # Replace only the synthetic destination; no real token/key/network is used.
        import subprocess
        import threading
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        received = []

        class Receiver(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass
            def do_POST(self):
                received.append(self.rfile.read(int(self.headers['Content-Length'])))
                self.send_response(200)
                self.send_header('Content-Length', '0')
                self.end_headers()

        listener = ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
        thread = threading.Thread(target=listener.serve_forever, daemon=True)
        thread.start()
        original_run = subprocess.run
        value = subscription()
        value['state']['awayRecord'] = '3–1–1'
        value['state']['awayScore'] = '−0.5'
        value['state']['latestChange'] = {
            'text': 'José “D’Andre” −1.0 pts · 🏈 \\ path\nnext\tline\b\f',
            'checkedAt': NOW - APPLE_EPOCH}
        expected = payload(value['state'], NOW)
        upstream = ('https://api.sandbox.push.apple.com/3/device/' + value['token']).encode()
        local = f'http://127.0.0.1:{listener.server_port}/push'.encode()

        def send_to_loopback(args, **kwargs):
            self.assertEqual(kwargs['input'].count(upstream), 1)
            kwargs['input'] = kwargs['input'].replace(upstream, local)
            return original_run(args, **kwargs)

        try:
            apns = APNs({})
            with patch.object(apns, 'jwt', return_value='synthetic-jwt'), \
                    patch('server.subprocess.run', side_effect=send_to_loopback):
                self.assertEqual(apns.send(value, expected, NOW), 200)
            self.assertEqual(received, [expected])
            self.assertEqual(json.loads(received[0])['aps']['content-state']['homeRecord'], '0–0')
        finally:
            listener.shutdown(); listener.server_close(); thread.join()

    def test_http2_headers_and_sensitive_data_only_in_stdin(self):
        apns = APNs({})
        with patch.object(apns, 'jwt', return_value='secret-jwt'), patch('server.subprocess.run') as run:
            run.return_value.returncode = 0; run.return_value.stdout = b'\n200'
            result = apns.send(subscription(), payload(subscription()['state'], NOW), NOW)
        self.assertEqual(result, 200)
        args, kwargs = run.call_args
        self.assertIn('--http2', args[0]); self.assertNotIn('secret-jwt', str(args))
        self.assertNotIn('ab' * 32, str(args))
        config = kwargs['input'].decode()
        self.assertIn('apns-priority: 5', config)
        self.assertIn('com.biggsjm.MFLBlitz.push-type.liveactivity', config)
        self.assertIn('api.sandbox.push.apple.com', config)



class HTTPTests(unittest.TestCase):
    def test_identity_browser_and_owner_controls(self):
        import http.client
        import threading
        from http.server import ThreadingHTTPServer
        from server import Handler
        with tempfile.TemporaryDirectory() as directory:
            service = Service(CONFIG, str(Path(directory) / 'test.sqlite3'), FakeMFL(), FakeAPNs(), lambda: NOW)
            server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            server.service = service
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            try:
                def call(method, path, headers, body=None):
                    connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
                    connection.request(method, path, body=body, headers=headers)
                    response = connection.getresponse(); status = response.status; response.read(); connection.close()
                    return status
                headers = {'Tailscale-User-Login': 'owner@example.test', 'X-Blitz-Sync': '1'}
                self.assertEqual(call('GET', '/v1/status', {}), 403)
                self.assertEqual(call('GET', '/v1/status', headers | {'Origin': 'https://untrusted.test'}), 403)
                self.assertEqual(call('GET', '/v1/status', headers | {'Tailscale-User-Login': 'other@test'}), 403)
                self.assertEqual(call('GET', '/v1/status', headers), 200)
                headers |= {'Authorization': 'Bearer ' + 'a' * 64, 'Content-Type': 'application/json'}
                self.assertEqual(call('PUT', '/v1/activities/one', headers, json.dumps(subscription())), 200)
                self.assertEqual(call('DELETE', '/v1/activities/one', headers | {'Authorization': 'Bearer ' + 'b' * 64}), 403)
                self.assertEqual(call('DELETE', '/v1/activities/one', headers), 200)
                self.assertEqual(call('PUT', '/v1/activities/one', headers, json.dumps(subscription())), 400)
            finally:
                server.shutdown(); server.server_close(); thread.join(); service.db.close()

if __name__ == '__main__': unittest.main()
