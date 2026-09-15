import io
import json
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from server import (Service, TestError, TTL, MAX_BYTES, decode, normalize_games,
                    normalize_players, normalize_profile, has_player_coverage, make_handler, read_private_key, NoRedirects)


def game(game_id=11, season=2024, status="FT"):
    return {"game": {"id": game_id, "stage": "Regular Season", "week": "Week 1",
                     "status": {"short": status}, "date": {"timestamp": 1725583200}},
            "league": {"id": 1, "season": str(season)},
            "teams": {"home": {"id": 1, "name": "Home Team"}, "away": {"id": 2, "name": "Away Team"}},
            "scores": {"home": {"total": 21}, "away": {"total": 7}}}


def coverage(value=True):
    return [{"league": {"id": 1}, "seasons": [{"year": 2024, "coverage": {
        "games": {"statisitcs": {"players": value}}}}]}]


def players(value="0"):
    return [{"team": {"id": 1, "name": "Home Team"}, "groups": [{"name": "Passing", "players": [
        {"player": {"id": 10, "name": "Example Quarterback"}, "statistics": [
            {"name": "yards", "value": value}, {"name": "sacks", "value": None}]}]}]}]


class Response(io.BytesIO):
    def __init__(self, value, headers=None, raw=None):
        super().__init__(raw if raw is not None else json.dumps({"errors": [], "response": value}).encode())
        self.headers = headers or {}


class Opener:
    def __init__(self, *values):
        self.values, self.calls = list(values), []

    def open(self, request, timeout):
        self.calls.append(request.full_url)
        value = self.values.pop(0)
        if isinstance(value, Exception):
            raise value
        return value if isinstance(value, Response) else Response(value)


class ServiceTests(unittest.TestCase):
    def test_profile_is_scoped_to_known_game_player_and_cached(self):
        opener = Opener([game()], coverage(), players(), [{"id": 10, "name": "Example Quarterback",
                        "position": "QB", "college": "Example College", "height": None, "weight": "-"}])
        service = self.service(opener)
        path = "/v1/seasons/2024/games/11/players/10/profile"
        result = service.handle(path)
        self.assertEqual(result["profile"]["providerID"], 10)
        self.assertIsNone(result["profile"]["weight"])
        self.assertEqual(result["gameID"], 11)
        self.assertEqual(result["season"], 2024)
        self.assertEqual(opener.calls[-1], "https://v1.american-football.api-sports.io/players?id=10")
        self.assertEqual(service.handle(path), result)
        self.assertEqual(service.used(), 4)
        with self.assertRaisesRegex(TestError, "reported in this game"):
            service.handle("/v1/seasons/2024/games/11/players/99/profile")
        self.assertEqual(service.used(), 4)

    def test_profile_refuses_wrong_duplicate_or_missing_identity(self):
        for rows in ([], [{"id": 11, "name": "Example"}],
                     [{"id": 10, "name": "Example"}] * 2,
                     [{"id": 10, "name": "Example", "position": {"value": "QB"}}]):
            with self.assertRaises(TestError):
                normalize_profile(rows, 10)

    def test_profile_does_not_bypass_scope_or_budget(self):
        opener = Opener([game()], coverage(), players())
        service = self.service(opener, budget=3)
        with self.assertRaisesRegex(TestError, "daily request budget"):
            service.handle("/v1/seasons/2024/games/11/players/10/profile")
        for path in ("/v1/seasons/2026/games/11/players/10/profile",
                     "/v1/seasons/2024/games/11/players/10/profile?season=2026",
                     "/v1/seasons/2024/games/11/players/0/profile"):
            with self.assertRaises(TestError):
                service.handle(path)
        self.assertEqual(service.used(), 3)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = str(Path(self.temp.name) / "cache.sqlite3")
        self.now = 1_800_000_000
        self.instances = []

    def tearDown(self):
        for instance in self.instances:
            instance.db.close()
        self.temp.cleanup()

    def service(self, opener, budget=20, key="synthetic-not-a-secret"):
        def sleep(delay):
            self.now += delay
        result = Service(self.path, key, budget, opener, lambda: self.now, sleep)
        self.instances.append(result)
        return result

    def test_completed_game_flow_and_persistent_cache(self):
        opener = Opener([game()], coverage(), players())
        service = self.service(opener)
        first = service.handle("/v1/seasons/2024/games/11/players")
        self.assertEqual(len(opener.calls), 3)
        self.assertEqual(first["players"][0]["groups"][0]["stats"][0]["value"], "0")
        self.assertIsNone(first["players"][0]["groups"][0]["stats"][1]["value"])
        self.assertTrue(first["testOnly"])
        self.assertFalse(first["stale"])
        self.assertEqual(first, self.service(Opener()).handle("/v1/seasons/2024/games/11/players"))
        self.assertEqual(service.handle("/v1/status")["requestsUsed"], 3)

    def test_no_current_season_or_arbitrary_queries(self):
        opener = Opener()
        service = self.service(opener)
        for path in ("/v1/seasons/2026/games", "/v1/seasons/2024/games?url=evil", "/v1/seasons/2024/games/0/players", "/leagues", "/../api-key"):
            with self.assertRaises(TestError):
                service.handle(path)
        self.assertEqual(opener.calls, [])

    def test_status_does_not_call_provider(self):
        opener = Opener()
        self.assertFalse(self.service(opener, key="").handle("/v1/status")["keyConfigured"])
        self.assertEqual(opener.calls, [])

    def test_unknown_or_unstarted_game_never_calls_stats(self):
        for status, requested in (("NS", 11), ("FT", 99)):
            with self.subTest(status=status):
                opener = Opener([game(status=status)])
                service = self.service(opener)
                service.db.execute("DELETE FROM cache")
                service.db.commit()
                with self.assertRaisesRegex(TestError, "completed game"):
                    service.handle(f"/v1/seasons/2024/games/{requested}/players")
                self.assertEqual(len(opener.calls), 1)

    def test_coverage_is_required(self):
        opener = Opener([game()], coverage(False))
        with self.assertRaisesRegex(TestError, "not confirmed"):
            self.service(opener).handle("/v1/seasons/2024/games/11/players")
        self.assertEqual(len(opener.calls), 2)
        self.assertFalse(has_player_coverage(coverage("true"), 2024))

    def test_budget_survives_restart_and_failures(self):
        opener = Opener(OSError("sensitive provider text"))
        with self.assertRaises(TestError):
            self.service(opener, budget=1).handle("/v1/seasons/2024/games")
        self.now += 70
        service = self.service(Opener(), budget=1)
        with self.assertRaisesRegex(TestError, "daily request budget"):
            service.handle("/v1/seasons/2023/games")
        self.assertEqual(service.used(), 1)
        self.now += TTL
        self.assertEqual(service.used(), 0)

    def test_concurrent_misses_coalesce(self):
        opener = Opener([game()])
        service = self.service(opener)
        results = []
        threads = [threading.Thread(target=lambda: results.append(service.handle("/v1/seasons/2024/games"))) for _ in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(len(results), 8)
        self.assertEqual(len(opener.calls), 1)

    def test_stale_keeps_original_fetched_date_and_does_not_retry(self):
        opener = Opener([game()], OSError())
        service = self.service(opener)
        first = service.handle("/v1/seasons/2024/games")
        self.now += TTL + 1
        stale = service.handle("/v1/seasons/2024/games")
        self.assertTrue(stale["stale"])
        self.assertEqual(first["fetchedAt"], stale["fetchedAt"])
        service.handle("/v1/seasons/2024/games")
        self.assertEqual(len(opener.calls), 2)

    def test_429_cooldown_persists_across_routes_and_restart(self):
        failure = urllib.error.HTTPError("https://example.test", 429, "sensitive", {"Retry-After": "120"}, None)
        opener = Opener(failure)
        with self.assertRaises(TestError):
            self.service(opener).handle("/v1/seasons/2024/games")
        service = self.service(Opener())
        self.now += 70
        with self.assertRaisesRegex(TestError, "cooling down"):
            service.handle("/v1/seasons/2023/games")
        self.assertEqual(service.used(), 1)

    def test_remaining_zero_stops_next_request(self):
        opener = Opener(Response([game()], {"x-ratelimit-requests-remaining": "0"}))
        service = self.service(opener)
        service.handle("/v1/seasons/2024/games")
        with self.assertRaisesRegex(TestError, "cooling down"):
            service.handle("/v1/seasons/2024/games/11/players")
        self.assertEqual(len(opener.calls), 1)

    def test_body_plan_error_is_cached_and_sanitized(self):
        opener = Opener(Response([], raw=b'{"errors":{"plan":"secret echoed"},"response":[]}'))
        service = self.service(opener)
        for _ in range(2):
            with self.assertRaisesRegex(TestError, "free plan"):
                service.handle("/v1/seasons/2024/games")
        self.assertEqual(len(opener.calls), 1)

    def test_shape_limits(self):
        for raw in (b'null', b'{"errors":[],"response":[NaN]}', b'{"response":[]}', b'{"errors":[],"response":{}}'):
            with self.assertRaises(TestError):
                decode(raw)
        with self.assertRaises(TestError):
            normalize_games([game(season=2023)], 2024)
        with self.assertRaises(TestError):
            normalize_games([game(), game()], 2024)
        with self.assertRaises(TestError):
            normalize_players(players({"bad": "value"}), normalize_games([game()], 2024)[0])
        mismatched = players()
        mismatched[0]["team"]["id"] = 999
        with self.assertRaises(TestError):
            normalize_players(mismatched, normalize_games([game()], 2024)[0])
        opener = Opener(Response([], raw=b' ' * (MAX_BYTES + 1)))
        with self.assertRaises(TestError):
            self.service(opener).handle("/v1/seasons/2024/games")

    def test_null_status_does_not_hide_the_season_or_invent_a_final(self):
        normalized = normalize_games([game(status=None), game(game_id=12)], 2024)
        self.assertEqual(normalized[0]["status"], "UNKNOWN")
        self.assertEqual(normalized[1]["status"], "FT")
        service = self.service(Opener([game(status=None)]))
        with self.assertRaisesRegex(TestError, "completed game"):
            service.handle("/v1/seasons/2024/games/11/players")

    def test_explicit_overtime_long_status_is_final(self):
        overtime = game(status=None)
        overtime["game"]["status"]["long"] = "Final/OT"
        self.assertEqual(normalize_games([overtime], 2024)[0]["status"], "AOT")

    def test_cached_failure_does_not_extend_its_retry_window(self):
        service = self.service(Opener(OSError(), [game()]))
        with self.assertRaises(TestError):
            service.handle("/v1/seasons/2024/games")
        self.now += 50
        with self.assertRaises(TestError):
            service.handle("/v1/seasons/2024/games")
        self.now += 11
        self.assertEqual(len(service.handle("/v1/seasons/2024/games")["games"]), 1)

    def test_secret_permissions_and_redirect_rejection(self):
        path = Path(self.temp.name) / "key"
        self.assertEqual(read_private_key(path), "")
        path.write_text("synthetic")
        path.chmod(0o644)
        with self.assertRaises(ValueError):
            read_private_key(path)
        path.chmod(0o600)
        self.assertEqual(read_private_key(path), "synthetic")
        alias = Path(self.temp.name) / "alias"
        alias.symlink_to(path)
        with self.assertRaises(ValueError):
            read_private_key(alias)
        self.assertIsNone(NoRedirects().redirect_request(None, None, 302, "", {}, "https://evil.test"))

    def test_http_requires_app_header_and_rejects_browser_origin(self):
        service = self.service(Opener())
        server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(service))
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        url = f"http://127.0.0.1:{server.server_port}/v1/status"
        try:
            for headers in ({}, {"X-Blitz-NFL-Test": "1", "Origin": "https://example.test"}):
                with self.assertRaises(urllib.error.HTTPError) as caught:
                    urllib.request.urlopen(urllib.request.Request(url, headers=headers))
                self.assertEqual(caught.exception.code, 403)
                caught.exception.close()
            with urllib.request.urlopen(urllib.request.Request(url, headers={"X-Blitz-NFL-Test": "1"})) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(response.headers["Cache-Control"], "no-store")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
