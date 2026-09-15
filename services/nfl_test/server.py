#!/usr/bin/env python3
"""Private, manual API-NFL historical evaluation. No MFL data or polling."""

import argparse
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import stat
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

SEASONS = (2024, 2023, 2022)
UPSTREAM = "https://v1.american-football.api-sports.io/"
MAX_BYTES = 5_000_000
TTL = 86_400
MESSAGES = {
    "season": "The free test supports 2022–2024 only, not current-season or live stats.",
    "route": "This test request is not supported.",
    "access": "Use the private Blitz test client over Tailscale.",
    "key": "The test server needs its private API key configured.",
    "budget": "The test server has reached its daily request budget. Cached data is still available.",
    "cooldown": "The provider is cooling down. Try again later; cached data is still available.",
    "plan": "This data is not included in the provider’s free plan.",
    "provider": "The NFL provider could not return this data. Try again later.",
    "shape": "The provider returned an unsupported response. No stats were inferred.",
    "coverage": "Player statistics are not confirmed for this season.",
    "game": "Choose a completed game from this season’s game list.",
    "player": "Choose a player reported in this game’s box score.",
}


class TestError(Exception):
    def __init__(self, code, status=503):
        self.code, self.status = code, status
        super().__init__(MESSAGES[code])


def obj(value):
    return value if isinstance(value, dict) else {}


def array(value, limit=1000):
    if not isinstance(value, list) or len(value) > limit:
        raise TestError("shape")
    return value


def label(value):
    if not isinstance(value, str) or not value.strip() or len(value) > 200:
        raise TestError("shape")
    return value.strip()


def identifier(value):
    if type(value) is not int or not 0 < value < 100_000_000:
        raise TestError("shape")
    return value


def number(value):
    if value is None:
        return None
    if type(value) not in (int, float) or not math.isfinite(value):
        raise TestError("shape")
    return value


def decode(raw):
    def invalid(_):
        raise ValueError()
    try:
        body = json.loads(raw, parse_constant=invalid)
    except (ValueError, UnicodeError):
        raise TestError("shape") from None
    if not isinstance(body, dict):
        raise TestError("shape")
    errors = body.get("errors")
    if not isinstance(errors, (list, dict)) or errors:
        raise TestError("plan" if isinstance(errors, dict) and "plan" in errors else "provider")
    return array(body.get("response"))


def normalize_games(rows, season):
    games, seen = [], set()
    for row in rows:
        league, game = obj(obj(row).get("league")), obj(obj(row).get("game"))
        if league.get("id") != 1 or str(league.get("season")) != str(season):
            raise TestError("shape")
        game_id = identifier(game.get("id"))
        if game_id in seen:
            raise TestError("shape")
        seen.add(game_id)
        teams, scores = obj(row.get("teams")), obj(row.get("scores"))
        home, away = obj(teams.get("home")), obj(teams.get("away"))
        kickoff = number(obj(game.get("date")).get("timestamp"))
        if kickoff is None:
            raise TestError("shape")
        status = obj(game.get("status"))
        phase = status.get("short")
        # Some completed overtime games have a null short code in the real feed.
        if phase is None and status.get("long") == "Final/OT":
            phase = "AOT"
        games.append({"id": game_id, "season": season, "stage": label(game.get("stage")),
                      "week": label(game.get("week")), "kickoff": kickoff,
                      "status": label(phase or "UNKNOWN"),
                      "homeID": identifier(home.get("id")), "home": label(home.get("name")),
                      "awayID": identifier(away.get("id")), "away": label(away.get("name")),
                      "homeScore": number(obj(scores.get("home")).get("total")),
                      "awayScore": number(obj(scores.get("away")).get("total"))})
    return sorted(games, key=lambda game: (game["kickoff"], game["id"]))


def has_player_coverage(rows, season):
    matches = [entry for row in rows if obj(obj(row).get("league")).get("id") == 1
               for entry in array(obj(row).get("seasons"), 50)
               if str(obj(entry).get("year")) == str(season)]
    if len(matches) != 1:
        return False
    games = obj(obj(matches[0].get("coverage")).get("games"))
    # API-NFL uses this misspelling on the wire, verified in the Live Tester.
    return obj(games.get("statisitcs", games.get("statistics"))).get("players") is True


def normalize_players(rows, game):
    players = {}
    teams_seen = set()
    for row in array(rows, 2):
        team = obj(obj(row).get("team"))
        team_id = identifier(team.get("id"))
        if team_id not in (game["homeID"], game["awayID"]) or team_id in teams_seen:
            raise TestError("shape")
        teams_seen.add(team_id)
        for group in array(row.get("groups"), 30):
            group_name = label(obj(group).get("name"))
            for entry in array(group.get("players"), 150):
                identity = obj(obj(entry).get("player"))
                player_id, name = identifier(identity.get("id")), label(identity.get("name"))
                key = (team_id, player_id)
                player = players.setdefault(key, {"id": f"{team_id}-{player_id}", "providerID": player_id,
                    "name": name, "team": label(team.get("name")), "groups": []})
                if player["name"] != name or any(g["name"] == group_name for g in player["groups"]):
                    raise TestError("shape")
                stats, names = [], set()
                for field in array(entry.get("statistics"), 60):
                    stat_name, value = label(obj(field).get("name")), obj(field).get("value")
                    if stat_name in names:
                        raise TestError("shape")
                    names.add(stat_name)
                    if value is not None:
                        if type(value) in (int, float):
                            value = str(number(value))
                        elif isinstance(value, str):
                            value = value.strip() or None
                        else:
                            raise TestError("shape")
                        if value is not None and len(value) > 100:
                            raise TestError("shape")
                    stats.append({"name": stat_name, "value": value})
                player["groups"].append({"name": group_name, "stats": stats})
    return sorted(players.values(), key=lambda p: (p["team"], p["name"], p["id"]))


def normalize_profile(rows, player_id):
    # Profiles have no documented MFL ID or date of birth. They support human
    # review only; never manufacture either field or infer age as birth date.
    rows = array(rows, 1)
    if len(rows) != 1 or identifier(obj(rows[0]).get("id")) != player_id:
        raise TestError("shape")
    row = rows[0]
    result = {"providerID": player_id, "name": label(row.get("name"))}
    for field in ("position", "college", "height", "weight"):
        value = row.get(field)
        result[field] = None if value is None or value == "-" or value == "" else label(value)
    return result


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward credentials, even to another HTTPS endpoint.


class Service:
    def __init__(self, database, key, budget=20, opener=None, clock=time.time, sleep=time.sleep):
        self.db = sqlite3.connect(database, check_same_thread=False)
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, payload TEXT, fetched REAL);
            CREATE TABLE IF NOT EXISTS usage (day TEXT PRIMARY KEY, count INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value REAL);
            CREATE TABLE IF NOT EXISTS failures (key TEXT PRIMARY KEY, code TEXT, until REAL);
        """)
        self.key, self.budget = key, budget
        self.opener = opener or urllib.request.build_opener(NoRedirects())
        self.clock, self.sleep = clock, sleep
        self.lock = threading.RLock()

    def day(self):
        return datetime.fromtimestamp(self.clock(), timezone.utc).date().isoformat()

    def used(self):
        row = self.db.execute("SELECT count FROM usage WHERE day=?", (self.day(),)).fetchone()
        return row[0] if row else 0

    def state(self, key):
        row = self.db.execute("SELECT value FROM state WHERE key=?", (key,)).fetchone()
        return row[0] if row else 0

    def set_state(self, key, value):
        self.db.execute("INSERT OR REPLACE INTO state VALUES (?,?)", (key, value))
        self.db.commit()

    def upstream(self, endpoint, params):
        if not self.key:
            raise TestError("key")
        if self.used() >= self.budget:
            raise TestError("budget", 429)
        if self.state("cooldown") > self.clock():
            raise TestError("cooldown", 429)
        wait = self.state("last_request") + 6.5 - self.clock()
        if wait > 0:
            self.sleep(min(wait, 6.5))
            if self.state("last_request") + 6.5 > self.clock() + 0.01:
                raise TestError("cooldown", 429)
        # Reserve before I/O, not after success. Failure/restart cannot refund quota.
        self.db.execute("INSERT INTO usage VALUES (?,1) ON CONFLICT(day) DO UPDATE SET count=count+1", (self.day(),))
        self.set_state("last_request", self.clock())
        request = urllib.request.Request(UPSTREAM + endpoint + "?" + urllib.parse.urlencode(params),
                                        headers={"x-apisports-key": self.key}, method="GET")
        try:
            with self.opener.open(request, timeout=20) as response:
                remaining = response.headers.get("x-ratelimit-requests-remaining")
                if remaining is not None and str(remaining).isdigit() and int(remaining) == 0:
                    tomorrow = (int(self.clock()) // TTL + 1) * TTL
                    self.set_state("cooldown", tomorrow)
                raw = response.read(MAX_BYTES + 1)
        except urllib.error.HTTPError as error:
            if error.code == 429:
                retry = error.headers.get("Retry-After", "60")
                try:
                    until = self.clock() + max(60, int(retry))
                except ValueError:
                    try:
                        until = max(self.clock() + 60, parsedate_to_datetime(retry).timestamp())
                    except (ValueError, TypeError, OverflowError):
                        until = self.clock() + 60
                self.set_state("cooldown", until)
            elif error.code in (401, 403):
                self.set_state("cooldown", self.clock() + TTL)
            code = "cooldown" if error.code == 429 else "provider"
            error.close()
            raise TestError(code) from None
        except (OSError, urllib.error.URLError, ValueError):
            raise TestError("provider") from None
        if len(raw) > MAX_BYTES:
            raise TestError("shape")
        return decode(raw)

    def cached(self, key, loader):
        row = self.db.execute("SELECT payload,fetched FROM cache WHERE key=?", (key,)).fetchone()
        if row and 0 <= self.clock() - row[1] < TTL:
            return json.loads(row[0]), row[1], False
        failure = self.db.execute("SELECT code,until FROM failures WHERE key=?", (key,)).fetchone()
        if failure and failure[1] > self.clock():
            if row and 0 <= self.clock() - row[1] < 7 * TTL:
                return json.loads(row[0]), row[1], True
            raise TestError(failure[0])
        try:
            value = loader()
        except TestError as error:
            self.db.execute("INSERT OR REPLACE INTO failures VALUES (?,?,?)",
                            (key, error.code, self.clock() + (TTL if error.code in ("plan", "coverage") else 60)))
            self.db.commit()
            if row and 0 <= self.clock() - row[1] < 7 * TTL:
                return json.loads(row[0]), row[1], True
            raise
        now = self.clock()
        self.db.execute("INSERT OR REPLACE INTO cache VALUES (?,?,?)", (key, json.dumps(value, allow_nan=False), now))
        self.db.execute("DELETE FROM failures WHERE key=?", (key,))
        self.db.commit()
        return value, now, False

    def handle(self, path):
        # One process owns the DB; lock also coalesces concurrent cache misses.
        with self.lock:
            meta = {"provider": "API-NFL", "testOnly": True, "allowedSeasons": list(SEASONS)}
            if path == "/v1/status":
                return dict(meta, requestsUsed=self.used(), dailyBudget=self.budget, keyConfigured=bool(self.key))
            match = re.fullmatch(r"/v1/seasons/(\d{4})/games(?:/([1-9]\d{0,7})/players(?:/([1-9]\d{0,7})/profile)?)?", path)
            if not match:
                raise TestError("route", 404)
            season = int(match[1])
            if season not in SEASONS:
                raise TestError("season", 400)
            games, fetched, stale = self.cached(f"games-v2-{season}", lambda: normalize_games(
                self.upstream("games", {"league": 1, "season": season}), season))
            if match[2] is None:
                return dict(meta, season=season, fetchedAt=fetched, stale=stale, games=games)
            game = next((game for game in games if game["id"] == int(match[2])), None)
            if not game or game["status"] not in ("FT", "AOT"):
                raise TestError("game", 400)
            def load_players():
                coverage, _, coverage_stale = self.cached(f"coverage-{season}", lambda: has_player_coverage(
                    self.upstream("leagues", {"id": 1, "season": season}), season))
                if not coverage or coverage_stale:
                    raise TestError("coverage")
                return normalize_players(self.upstream("games/statistics/players", {"id": game["id"]}), game)
            players, stats_fetched, stats_stale = self.cached(f"players-{season}-{game['id']}", load_players)
            if match[3] is not None:
                player_id = int(match[3])
                if sum(p["providerID"] == player_id for p in players) != 1:
                    raise TestError("player", 400)
                profile, profile_fetched, profile_stale = self.cached(
                    f"profile-by-id-v1-{player_id}", lambda: normalize_profile(
                        self.upstream("players", {"id": player_id}), player_id))
                return dict(meta, season=season, gameID=game["id"], fetchedAt=profile_fetched,
                            stale=stale or stats_stale or profile_stale, profile=profile)
            return dict(meta, season=season, game=game, fetchedAt=stats_fetched,
                        stale=stale or stats_stale, players=players)


def read_private_key(path):
    if not path.exists():
        return ""
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("API key must be an owner-only regular file.")
    key = path.read_text().strip()
    if not key or len(key) > 512 or not key.isascii() or any(ord(c) < 33 or ord(c) > 126 for c in key):
        raise ValueError("API key file is not a valid token.")
    return key


def make_handler(service):
    class Handler(BaseHTTPRequestHandler):
        server_version = "NFLTest"

        def log_message(self, *args):
            pass  # No access logs, query strings, identities, or credentials.

        def do_GET(self):
            try:
                if self.headers.get("X-Blitz-NFL-Test") != "1" or self.headers.get("Origin"):
                    raise TestError("access", 403)
                payload, status = service.handle(self.path), 200
            except TestError as error:
                payload, status = {"error": error.code, "message": str(error)}, error.status
            except Exception:
                payload, status = {"error": "provider", "message": MESSAGES["provider"]}, 500
            data = json.dumps(payload, allow_nan=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass
    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--key-file", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8791)
    parser.add_argument("--daily-budget", type=int, default=20, choices=range(1, 81))
    args = parser.parse_args()
    os.umask(0o077)
    args.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    service = Service(args.state_dir / "cache.sqlite3", read_private_key(args.key_file), args.daily_budget)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(service))
    server.daemon_threads = True
    print("Private historical NFL test listening on loopback. No polling.", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
