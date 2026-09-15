#!/usr/bin/env python3
"""Manual, read-only API-NFL evaluation. No third-party packages or app changes.

The key is entered without echo in a local terminal; it is never persisted.
Each invocation makes at most three GETs. Tests use synthetic responses only.
"""

import argparse
from datetime import date, datetime, timezone
import getpass
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import warnings


BASE_URL = "https://v1.american-football.api-sports.io/"
MAX_REQUESTS = 3
MAX_RESPONSE_BYTES = 5_000_000
REQUEST_SPACING_SECONDS = 6.5  # Free tier: 10 requests/minute; no polling/retries.
ACTIVE = {"Q1", "Q2", "Q3", "Q4", "HT", "OT"}
FINISHED = {"FT", "AOT"}
ALLOWED_ENDPOINTS = {"leagues", "games", "games/statistics/players"}


class ProbeError(Exception):
    """Only locally authored, credential-free messages reach the terminal."""


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the API key to a redirected host, even over HTTPS.
        return None


def read_key():
    if not sys.stdin.isatty():
        raise ProbeError("Run in a local interactive terminal to enter the key privately.")
    with warnings.catch_warnings():
        warnings.simplefilter("error", getpass.GetPassWarning)
        try:
            key = getpass.getpass("API-Sports key (hidden; not saved): ").strip()
        except (getpass.GetPassWarning, EOFError):
            raise ProbeError("A hidden terminal prompt is unavailable; no key was read.") from None
    if not key or not key.isascii() or any(char.isspace() or ord(char) < 33 or ord(char) > 126 for char in key):
        raise ProbeError("The key must be a nonempty printable token without whitespace.")
    return key


def decode_response(raw):
    try:
        def reject_constant(value):
            raise ValueError("Non-finite JSON number")

        body = json.loads(raw, parse_constant=reject_constant)
    except (ValueError, UnicodeError):
        raise ProbeError("The provider returned invalid JSON; stopped without retrying.") from None
    if not isinstance(body, dict):
        raise ProbeError("Unexpected response envelope; inspect the provider's Live Tester.")
    errors = body.get("errors")
    if not isinstance(errors, (list, dict)) or errors:
        # Provider messages may echo request values. Do not print raw errors.
        if isinstance(errors, dict) and "plan" in errors:
            raise ProbeError("Plan access restriction; check allowed seasons/dates in the dashboard. No upgrade or retry attempted.")
        raise ProbeError("The provider reported an API error. Check access/coverage/quota in its dashboard.")
    records = body.get("response")
    if not isinstance(records, list) or not all(isinstance(row, dict) for row in records):
        raise ProbeError("Unexpected response records; inspect the provider's Live Tester.")
    return records


class Client:
    def __init__(self, key, opener=None, sleep=time.sleep):
        self._key = key
        self._opener = opener or urllib.request.build_opener(NoRedirects())
        self._sleep = sleep
        self.calls = 0
        self.remaining = None

    def get(self, endpoint, **params):
        if endpoint not in ALLOWED_ENDPOINTS:
            raise ProbeError("This endpoint is outside the evaluation's allowlist.")
        if self.calls >= MAX_REQUESTS:
            raise ProbeError("The three-request limit was reached.")
        if self.remaining is not None and self.remaining <= 0:
            raise ProbeError("The provider reports no daily requests remaining; stopped.")
        if self.calls:
            self._sleep(REQUEST_SPACING_SECONDS)
        url = BASE_URL + endpoint + "?" + urllib.parse.urlencode(params)
        request = urllib.request.Request(url, headers={"x-apisports-key": self._key}, method="GET")
        self.calls += 1
        try:
            with self._opener.open(request, timeout=20) as response:
                quota = response.headers.get("x-ratelimit-requests-remaining")
                if quota is not None and str(quota).isascii() and str(quota).isdigit():
                    self.remaining = int(quota)
                raw = response.read(MAX_RESPONSE_BYTES + 1)
        except urllib.error.HTTPError as error:
            code = error.code
            error.close()
            if code == 429:
                raise ProbeError("Rate limited; stopped. Check the dashboard before another manual attempt.") from None
            if code in {401, 403}:
                raise ProbeError("Access denied; check the key and API-NFL access in the dashboard.") from None
            raise ProbeError("HTTP request failed; stopped without following redirects or retrying.") from None
        except (OSError, urllib.error.URLError, ValueError):
            raise ProbeError("Network request failed; stopped without retrying.") from None
        if len(raw) > MAX_RESPONSE_BYTES:
            raise ProbeError("Response exceeded the evaluation's size limit.")
        return decode_response(raw)


def as_dict(value):
    return value if isinstance(value, dict) else {}


def as_list(value):
    return value if isinstance(value, list) else []


def phase_of(row):
    phase = as_dict(as_dict(row.get("game")).get("status")).get("short")
    return phase if isinstance(phase, str) else None


def game_summary(row):
    game = as_dict(row.get("game"))
    teams = as_dict(row.get("teams"))
    return {
        "id": game.get("id"),
        "stage": game.get("stage"),
        "week": game.get("week"),
        "date": game.get("date"),
        "status": game.get("status"),
        "away": as_dict(teams.get("away")).get("name"),
        "home": as_dict(teams.get("home")).get("name"),
    }


def run_probe(client, season, game_date, selected_id=None):
    report = {"provider": "API-NFL", "season": season, "date_utc": game_date,
              "checked_at_utc": datetime.now(timezone.utc).isoformat(),
              "notice": "Retrieval time is not provider freshness. No fantasy points calculated."}
    try:
        leagues = client.get("leagues", id=1, season=season)
        seasons = [item for row in leagues if as_dict(row.get("league")).get("id") == 1
                   for item in as_list(row.get("seasons")) if isinstance(item, dict)
                   and str(item.get("year")) == str(season)]
        if len(seasons) != 1:
            raise ProbeError("NFL season coverage is missing or ambiguous; no further requests made.")
        coverage = as_dict(seasons[0].get("coverage"))
        report["coverage"] = coverage
        games = client.get("games", league=1, season=season, date=game_date, timezone="UTC")
        # Refuse to inspect statistics from a different competition or season.
        games = [row for row in games if as_dict(row.get("league")).get("id") == 1
                 and str(as_dict(row.get("league")).get("season")) == str(season)]
        report["games"] = [game_summary(row) for row in games]
        selected = None
        if selected_id is not None:
            matches = [row for row in games if as_dict(row.get("game")).get("id") == selected_id]
            if len(matches) != 1:
                raise ProbeError("Selected game is not unique in this NFL date/season; stopped.")
            selected = matches[0]
        else:
            # Prefer a live game; otherwise use the first finished game returned.
            for phases in (ACTIVE, FINISHED):
                selected = next((row for row in games if phase_of(row) in phases), None)
                if selected is not None:
                    break
        game_coverage = as_dict(coverage.get("games"))
        # API-NFL's published wire spelling is 'statisitcs'.
        stats_coverage = as_dict(game_coverage.get("statisitcs", game_coverage.get("statistics")))
        if stats_coverage.get("players") is not True:
            report["stats_result"] = "Skipped: player-stat coverage is not explicitly enabled."
        elif selected is None:
            report["stats_result"] = "Skipped: no active or finished NFL game on this UTC date."
        else:
            game = as_dict(selected.get("game"))
            report["selected_game"] = game_summary(selected)
            game_id = game.get("id")
            if phase_of(selected) not in ACTIVE | FINISHED:
                report["stats_result"] = "Skipped: this game has not started or its state is unsupported."
            elif type(game_id) is not int or game_id <= 0:
                raise ProbeError("Game ID is missing or invalid; no statistics request made.")
            else:
                stats = client.get("games/statistics/players", id=game_id)
                # Preserve the actual stat shape for local inspection, not a guessed Swift DTO.
                report["player_statistics"] = stats
                report["stats_result"] = "Returned records; coverage/accuracy still need review." if stats else "No player statistics returned; do not treat as zero."
    except ProbeError as error:
        report["error"] = str(error)
    report["requests_attempted"] = client.calls
    report["daily_requests_remaining"] = client.remaining
    return report


def parse_date(value):
    try:
        return date.fromisoformat(value).isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError("Use a valid YYYY-MM-DD UTC game date.") from None


def positive_int(value):
    try:
        number = int(value)
        if number > 0:
            return number
    except ValueError:
        pass
    raise argparse.ArgumentTypeError("Use a positive integer.")


def redact(value, key):
    if isinstance(value, str):
        return value.replace(key, "[REDACTED]")
    if isinstance(value, list):
        return [redact(item, key) for item in value]
    if isinstance(value, dict):
        return {redact(name, key): redact(item, key) for name, item in value.items()}
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=positive_int, required=True, help="NFL season's starting year")
    parser.add_argument("--date", type=parse_date, required=True, help="Game date in UTC (YYYY-MM-DD)")
    parser.add_argument("--game-id", type=positive_int, help="Optional game ID from this date; otherwise prefers live then final")
    args = parser.parse_args()
    try:
        key = read_key()
        result = run_probe(Client(key), args.season, args.date, args.game_id)
        print(json.dumps(redact(result, key), indent=2, ensure_ascii=True, allow_nan=False))
        return 1 if "error" in result else 0
    except ProbeError as error:
        print(str(error), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Cancelled. No automatic retry.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
