"""Synthetic, offline checks. No API key or network access is needed."""

import contextlib
import io
import json
import unittest
from unittest.mock import patch
import urllib.error

import api_nfl_probe as probe


def envelope(records, errors=None):
    return json.dumps({"errors": [] if errors is None else errors, "response": records}).encode()


def league(coverage=True, spelling="statisitcs"):
    return [{"league": {"id": 1}, "seasons": [{"year": 2026, "coverage": {
        "games": {spelling: {"players": coverage}}, "injuries": False}}]}]


def game(game_id=101, status="Q2", season=2026, league_id=1):
    return {"game": {"id": game_id, "status": {"short": status, "timer": "08:14"}},
            "league": {"id": league_id, "season": season},
            "teams": {"away": {"name": "Test Away"}, "home": {"name": "Test Home"}}}


class Response:
    def __init__(self, raw, remaining="97"):
        self.raw = raw
        self.headers = {"x-ratelimit-requests-remaining": remaining}

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def read(self, size):
        return self.raw[:size]


class Opener:
    def __init__(self, responses):
        self.responses = list(responses)
        self.requests = []

    def open(self, request, timeout):
        self.requests.append(request)
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


def client_for(*records):
    opener = Opener([Response(envelope(items)) for items in records])
    waits = []
    client = probe.Client("synthetic-secret", opener, waits.append)
    return client, opener, waits


class ProbeTests(unittest.TestCase):
    def test_live_game_checks_coverage_and_stats_with_three_spaced_gets(self):
        stats = [{"team": {"id": 2}, "players": [{"id": 555, "yards": 0}]}]
        client, opener, waits = client_for(league(), [game()], stats)
        result = probe.run_probe(client, 2026, "2026-09-09")
        self.assertNotIn("error", result)
        self.assertEqual(result["player_statistics"], stats)
        self.assertEqual(result["requests_attempted"], 3)
        self.assertEqual(result["daily_requests_remaining"], 97)
        self.assertEqual(waits, [6.5, 6.5])
        self.assertEqual(opener.requests[2].full_url, probe.BASE_URL + "games/statistics/players?id=101")
        for request in opener.requests:
            self.assertEqual(request.get_method(), "GET")
            self.assertNotIn("synthetic-secret", request.full_url)
            self.assertEqual(request.get_header("X-apisports-key"), "synthetic-secret")

    def test_zero_stats_and_missing_stats_are_distinct(self):
        client, _, _ = client_for(league(), [game(status="FT")], [])
        result = probe.run_probe(client, 2026, "2026-09-09")
        self.assertEqual(result["player_statistics"], [])
        self.assertIn("do not treat as zero", result["stats_result"])

    def test_unsupported_or_unknown_coverage_skips_stats(self):
        for flag in (False, None, "true", 1):
            with self.subTest(flag=flag):
                client, _, _ = client_for(league(flag), [game()])
                result = probe.run_probe(client, 2026, "2026-09-09")
                self.assertEqual(client.calls, 2)
                self.assertIn("not explicitly enabled", result["stats_result"])

    def test_alternative_coverage_spelling_is_supported(self):
        client, _, _ = client_for(league(spelling="statistics"), [game()], [])
        self.assertNotIn("error", probe.run_probe(client, 2026, "2026-09-09"))
        self.assertEqual(client.calls, 3)

    def test_empty_or_ambiguous_league_stops_after_one_request(self):
        for records in ([], league() + league()):
            with self.subTest(records=records):
                client, _, _ = client_for(records)
                result = probe.run_probe(client, 2026, "2026-09-09")
                self.assertIn("error", result)
                self.assertEqual(client.calls, 1)

    def test_no_games_and_pregame_do_not_request_stats(self):
        for games in ([], [game(status="NS")], [game(status="PST")], [game(status="CANC")]):
            with self.subTest(games=games):
                client, _, _ = client_for(league(), games)
                result = probe.run_probe(client, 2026, "2026-09-09")
                self.assertNotIn("player_statistics", result)
                self.assertEqual(client.calls, 2)

    def test_live_is_preferred_over_finished_and_pregame(self):
        client, _, _ = client_for(league(), [game(101, "FT"), game(102, "NS"), game(103, "HT")], [])
        result = probe.run_probe(client, 2026, "2026-09-09")
        self.assertEqual(result["selected_game"]["id"], 103)

    def test_all_live_and_finished_states_allow_stats(self):
        for phase in probe.ACTIVE | probe.FINISHED:
            with self.subTest(phase=phase):
                client, _, _ = client_for(league(), [game(status=phase)], [])
                self.assertNotIn("error", probe.run_probe(client, 2026, "2026-09-09"))
                self.assertEqual(client.calls, 3)

    def test_selected_game_is_respected(self):
        client, _, _ = client_for(league(), [game(101), game(102)], [])
        result = probe.run_probe(client, 2026, "2026-09-09", 102)
        self.assertEqual(result["selected_game"]["id"], 102)

    def test_selected_pregame_does_not_request_stats(self):
        client, _, _ = client_for(league(), [game(101, "NS")])
        result = probe.run_probe(client, 2026, "2026-09-09", 101)
        self.assertIn("not started", result["stats_result"])
        self.assertEqual(client.calls, 2)

    def test_missing_or_duplicate_selected_game_is_rejected(self):
        for games in ([], [game(), game()]):
            with self.subTest(games=games):
                client, _, _ = client_for(league(), games)
                result = probe.run_probe(client, 2026, "2026-09-09", 101)
                self.assertIn("error", result)
                self.assertEqual(client.calls, 2)

    def test_other_competition_or_season_is_not_used(self):
        client, _, _ = client_for(league(), [game(league_id=2), game(season=2025)])
        result = probe.run_probe(client, 2026, "2026-09-09")
        self.assertEqual(result["games"], [])
        self.assertEqual(client.calls, 2)

    def test_invalid_game_id_is_rejected(self):
        for game_id in (None, -1, True, "101"):
            with self.subTest(game_id=game_id):
                client, _, _ = client_for(league(), [game(game_id)])
                result = probe.run_probe(client, 2026, "2026-09-09")
                self.assertIn("error", result)
                self.assertEqual(client.calls, 2)

    def test_budget_refuses_fourth_request(self):
        client, opener, waits = client_for([], [], [])
        for _ in range(3):
            client.get("games", id=101)
        with self.assertRaises(probe.ProbeError):
            client.get("games", id=101)
        self.assertEqual(len(opener.requests), 3)
        self.assertEqual(len(waits), 2)

    def test_reported_exhausted_quota_stops_next_request(self):
        opener = Opener([Response(envelope(league()), remaining="0")])
        client = probe.Client("synthetic-secret", opener, lambda _: None)
        result = probe.run_probe(client, 2026, "2026-09-09")
        self.assertIn("no daily requests", result["error"])
        self.assertEqual(client.calls, 1)

    def test_allowlist_prevents_credentials_on_other_endpoints(self):
        client, opener, _ = client_for()
        for endpoint in ("status", "https://example.com", "../status"):
            with self.subTest(endpoint=endpoint), self.assertRaises(probe.ProbeError):
                client.get(endpoint)
        self.assertEqual(opener.requests, [])

    def test_redirect_handler_never_forwards_key(self):
        self.assertIsNone(probe.NoRedirects().redirect_request(None, None, 302, "", {}, "https://example.com"))

    def test_http_errors_and_timeouts_do_not_retry_or_echo_secrets(self):
        failures = [urllib.error.HTTPError(probe.BASE_URL, code, "synthetic-secret", {}, None)
                    for code in (302, 401, 403, 429, 500)]
        failures += [urllib.error.URLError("synthetic-secret"), TimeoutError("synthetic-secret")]
        for failure in failures:
            with self.subTest(failure=type(failure)):
                opener = Opener([failure])
                client = probe.Client("synthetic-secret", opener, lambda _: None)
                result = probe.run_probe(client, 2026, "2026-09-09")
                self.assertIn("error", result)
                self.assertNotIn("synthetic-secret", json.dumps(result))
                self.assertEqual(client.calls, 1)

    def test_body_errors_and_bad_shapes_stop_without_echo(self):
        for raw in (b"invalid", b"[]", b"{}", envelope([], {"token": "synthetic-secret"}),
                    envelope([], ["synthetic-secret"]), envelope([None]),
                    b'{"errors": [], "response": {}}'):
            with self.subTest(raw=raw):
                with self.assertRaises(probe.ProbeError) as caught:
                    probe.decode_response(raw)
                self.assertNotIn("synthetic-secret", str(caught.exception))

    def test_free_plan_restriction_stops_after_one_request(self):
        # Synthetic version of the plan-error envelope observed in the Live Tester.
        opener = Opener([Response(envelope([], {"plan": "restricted synthetic-secret"}))])
        client = probe.Client("synthetic-secret", opener)
        result = probe.run_probe(client, 2026, "2026-09-09")
        self.assertIn("Plan access restriction", result["error"])
        self.assertNotIn("synthetic-secret", json.dumps(result))
        self.assertEqual(client.calls, 1)

    def test_malformed_nested_coverage_and_status_fail_safely(self):
        client, _, _ = client_for([{"league": {"id": 1}, "seasons": 2026}])
        self.assertIn("error", probe.run_probe(client, 2026, "2026-09-09"))
        client, _, _ = client_for(league(), [game(status=["Q2"])])
        result = probe.run_probe(client, 2026, "2026-09-09")
        self.assertNotIn("player_statistics", result)
        self.assertEqual(client.calls, 2)

    def test_nonfinite_json_is_rejected(self):
        for value in (b"NaN", b"Infinity", b"-Infinity"):
            with self.subTest(value=value), self.assertRaises(probe.ProbeError):
                probe.decode_response(b'{"errors": [], "response": [{"value": ' + value + b'}]}')

    def test_oversized_body_is_rejected(self):
        opener = Opener([Response(b"x" * (probe.MAX_RESPONSE_BYTES + 1))])
        client = probe.Client("synthetic-secret", opener)
        with self.assertRaisesRegex(probe.ProbeError, "size limit"):
            client.get("games", id=101)

    def test_no_key_echo_or_noninteractive_fallback(self):
        with patch("api_nfl_probe.sys.stdin.isatty", return_value=False), patch("api_nfl_probe.getpass.getpass") as prompt:
            with self.assertRaises(probe.ProbeError):
                probe.read_key()
            prompt.assert_not_called()

    def test_hidden_key_prompt(self):
        with patch("api_nfl_probe.sys.stdin.isatty", return_value=True), patch("api_nfl_probe.getpass.getpass", return_value="synthetic-secret"):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(probe.read_key(), "synthetic-secret")
            self.assertEqual(out.getvalue(), "")

    def test_redaction_handles_echoed_key_in_nested_values_and_field_names(self):
        value = {"token-synthetic-secret": [{"value": "synthetic-secret"}]}
        result = json.dumps(probe.redact(value, "synthetic-secret"))
        self.assertNotIn("synthetic-secret", result)
        self.assertIn("[REDACTED]", result)

    def test_valid_date_is_required(self):
        self.assertEqual(probe.parse_date("2026-09-09"), "2026-09-09")
        with self.assertRaises(probe.argparse.ArgumentTypeError):
            probe.parse_date("2026-02-30")


if __name__ == "__main__":
    unittest.main()
