#!/usr/bin/env python3
"""One private NFL cache and worker. Readers never make upstream calls."""
import argparse
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import threading
import time
import urllib.request
import urllib.parse
import urllib.error
import feed
from player_identity import translated_fields

DAY = 86400
BUDGET = 6000


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


class Service:
    def __init__(self, path, key, season=2026, clock=time.time, opener=None):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.executescript('''
            CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, body TEXT, fetched REAL);
            CREATE TABLE IF NOT EXISTS usage (day INTEGER PRIMARY KEY, count INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value REAL);
            CREATE TABLE IF NOT EXISTS failures (key TEXT PRIMARY KEY, attempts INTEGER, until REAL);
        ''')
        self.key, self.season, self.clock = key, season, clock
        self.opener = opener or urllib.request.build_opener(NoRedirects())
        self.lock, self.worker_lock = threading.RLock(), threading.Lock()
        self.demand = {}
        self.priority_teams = {}
        self.defense_teams = {}
        self.wake = threading.Event()

    def day(self):
        return int(self.clock()) // DAY

    def used(self):
        row = self.db.execute('SELECT count FROM usage WHERE day=?', (self.day(),)).fetchone()
        return row[0] if row else 0

    def state(self, key):
        row = self.db.execute('SELECT value FROM state WHERE key=?', (key,)).fetchone()
        return row[0] if row else 0

    def set_state(self, key, value):
        self.db.execute('INSERT OR REPLACE INTO state VALUES (?,?)', (key, value))
        self.db.commit()

    def get(self, key):
        row = self.db.execute('SELECT body,fetched FROM cache WHERE key=?', (key,)).fetchone()
        return (json.loads(row[0]), row[1]) if row else (None, None)

    def multiplier(self):
        used = self.used()
        return 8 if used >= 5800 else 4 if used >= 5500 else 2 if used >= 5000 else 1

    def due(self, key, ttl):
        _, date = self.get(key)
        failure = self.db.execute('SELECT until FROM failures WHERE key=?', (key,)).fetchone()
        if failure and failure[0] > self.clock():
            return False
        return date is None or not 0 <= self.clock() - date < ttl

    def schedule_ttl(self, games):
        now = self.clock()
        if self.demand:
            games = [g for g in games if g['week'] in self.demand]
        active = any(g['status'] in feed.LIVE or
                     (g['status'] == 'NS' and -21600 < g['kickoff'] - now < 900) for g in games)
        return (30 if active else 900) * self.multiplier()

    def stats_ttl(self, game):
        if game['status'] in feed.LIVE:
            return 60 * self.multiplier()
        if game['status'] not in feed.FINAL:
            return float('inf')
        age = self.clock() - game['kickoff']
        return 300 if age < 21600 else 3600 if age < 2 * DAY else DAY if age < 7 * DAY else float('inf')

    def box_ttl(self, game, box, fetched):
        # Finish a live box and do one final correction read after the first
        # week. Later browsing serves that archived box without refetching it.
        if box and game['status'] in feed.FINAL:
            archive_at = game['kickoff'] + 7 * DAY
            if box['phase'] != game['status'] or fetched < archive_at <= self.clock():
                return 0
        return self.stats_ttl(game)

    def fetch(self, key, endpoint, params, normalize):
        # Reserve before network I/O. Only the worker calls this; readers hold
        # the database lock briefly and never wait for the provider.
        with self.lock:
            now = self.clock()
            if self.used() >= BUDGET or self.state('pause') > now or self.state('last') + 2 > now:
                return False
            self.db.execute('INSERT INTO usage VALUES (?,1) ON CONFLICT(day) DO UPDATE SET count=count+1', (self.day(),))
            self.set_state('last', now)
        request = urllib.request.Request('https://v1.american-football.api-sports.io/' + endpoint + '?' + urllib.parse.urlencode(params),
                                         headers={'x-apisports-key': self.key})
        try:
            with self.opener.open(request, timeout=12) as response:
                with self.lock:
                    remaining = response.headers.get('x-ratelimit-requests-remaining', '')
                    minute = response.headers.get('X-RateLimit-Remaining', '')
                    if str(remaining).isdigit():
                        self.set_state('providerRemaining', int(remaining))
                        self.set_state('providerDay', self.day())
                        if int(remaining) <= 500:
                            self.set_state('pause', (self.day() + 1) * DAY)
                    if str(minute).isdigit() and int(minute) <= 2:
                        self.set_state('pause', max(self.state('pause'), self.clock() + 60))
                raw = response.read(5_000_001)
            if len(raw) > 5_000_000:
                raise ValueError('size')
            body = json.loads(raw)
            if body.get('errors'):
                if isinstance(body['errors'], dict) and any(k.lower() in ('plan', 'token', 'access') for k in body['errors']):
                    with self.lock:
                        self.set_state('pause', self.clock() + 3600)
                raise ValueError('provider')
            value = normalize(body.get('response'))
            with self.lock:
                self.db.execute('INSERT OR REPLACE INTO cache VALUES (?,?,?)', (key, json.dumps(value, allow_nan=False), self.clock()))
                self.db.execute('DELETE FROM failures WHERE key=?', (key,))
                self.db.commit()
            return True
        except Exception as error:
            with self.lock:
                if isinstance(error, urllib.error.HTTPError):
                    if error.code == 429:
                        raw_retry = error.headers.get('Retry-After', '60')
                        try:
                            until = self.clock() + max(60, int(raw_retry))
                        except ValueError:
                            try:
                                until = max(self.clock() + 60, parsedate_to_datetime(raw_retry).timestamp())
                            except (ValueError, TypeError, OverflowError):
                                until = self.clock() + 60
                        self.set_state('pause', max(self.state('pause'), until))
                    elif error.code in (401, 403):
                        self.set_state('pause', self.clock() + 3600)
                    error.close()
                failure = self.db.execute('SELECT attempts FROM failures WHERE key=?', (key,)).fetchone()
                attempts = min(7, (failure[0] if failure else 0) + 1)
                self.db.execute('INSERT OR REPLACE INTO failures VALUES (?,?,?)',
                                (key, attempts, self.clock() + min(1800, 30 * 2 ** (attempts - 1))))
                self.db.commit()
            return False

    def tick(self):
        if not self.worker_lock.acquire(blocking=False):
            return
        try:
            with self.lock:
                self.demand = {w: expires for w, expires in self.demand.items() if expires > self.clock()}
                self.priority_teams = {t: expires for t, expires in self.priority_teams.items() if expires > self.clock()}
                self.defense_teams = {t: expires for t, expires in self.defense_teams.items() if expires > self.clock()}
                if not self.demand or self.used() >= BUDGET or self.state('pause') > self.clock():
                    return
                games, _ = self.get('games')
                games = games or []
                if self.due('coverage', DAY):
                    job = ('coverage', 'leagues', {'id': 1, 'season': self.season}, self.coverage)
                elif self.due('games', self.schedule_ttl(games)):
                    job = ('games', 'games', {'league': 1, 'season': self.season}, lambda rows: feed.games(rows, self.season))
                else:
                    coverage, coverage_date = self.get('coverage')
                    if not coverage or not coverage.get('players') or self.clock() - coverage_date > 2 * DAY:
                        return
                    jobs = []
                    for game in games:
                        if game['week'] not in self.demand or game['status'] not in feed.LIVE | feed.FINAL:
                            continue
                        key = 'box-' + str(game['id'])
                        box, fetched = self.get(key)
                        ttl = self.box_ttl(game, box, fetched)
                        if self.due(key, ttl):
                            priority = -2 if game['home'] in self.priority_teams or game['away'] in self.priority_teams else 0
                            jobs.append((priority + (0 if game['status'] in feed.LIVE else 3), fetched or 0,
                                (key, 'games/statistics/players', {'id': game['id']},
                                 lambda rows, game=game: dict(phase=game['status'], players=feed.players(rows, game)))))
                        for tid in (game['homeID'], game['awayID']):
                            profile_key = 'roster-' + str(tid)
                            if box and self.due(profile_key, DAY if game['status'] in feed.LIVE else float('inf')):
                                priority = -2 if game['home'] in self.priority_teams or game['away'] in self.priority_teams else 0
                                jobs.append((priority + 1, 0, (profile_key, 'players', {'team': tid, 'season': self.season}, feed.profiles)))
                        if game['home'] in self.defense_teams or game['away'] in self.defense_teams:
                            defense_key='defense-'+str(game['id'])
                            defense,date=self.get(defense_key)
                            ttl=120*self.multiplier() if game['status'] in feed.LIVE else self.box_ttl(game,defense,date)
                            if self.due(defense_key,ttl):
                                jobs.append((-1 if game['status'] in feed.LIVE else 2,date or 0,
                                    (defense_key,'games/statistics/teams',{'id':game['id']},
                                     lambda rows,game=game:dict(phase=game['status'],players=feed.defenses(rows,game)))))
                    if not jobs:
                        return
                    job = min(jobs, key=lambda item: (item[0], item[1], item[2][0]))[2]
            self.fetch(*job)
        finally:
            self.worker_lock.release()

    def coverage(self, rows):
        seasons = [s for row in feed.items(rows, 10) if row['league']['id'] == 1
                   for s in row['seasons'] if s['year'] == self.season]
        if len(seasons) != 1:
            raise ValueError('coverage')
        c = seasons[0]['coverage']['games']
        return {'players': c.get('statisitcs', c.get('statistics', {})).get('players') is True}

    def snapshot(self, week, teams=(), defense_teams=()):
        with self.lock:
            self.demand[week] = self.clock() + 300
            for team in set(teams) & set(feed.TEAMS.values()):
                self.priority_teams[team] = self.clock() + 90
            for team in set(defense_teams) & set(feed.TEAMS.values()):
                self.defense_teams[team]=self.clock()+300
            self.wake.set()
            games, fetched = self.get('games')
            result = []
            pending = fetched is None
            for game in games or []:
                if game['week'] != week:
                    continue
                item = dict(game)
                item['checkedAt'] = fetched
                item['stale'] = self.clock() - fetched > max(120, self.schedule_ttl(games) * 2) or bool(self.db.execute('SELECT 1 FROM failures WHERE key=?', ('games',)).fetchone())
                box, box_date = self.get('box-' + str(game['id']))
                people = []
                roster_missing = False
                for player in (box or {}).get('players', []):
                    tid = game['homeID'] if player['team'] == game['home'] else game['awayID']
                    roster, roster_date = self.get('roster-' + str(tid))
                    profile = (roster or {}).get(str(player['providerID']))
                    # Identity is provided only when the game and roster agree.
                    position = profile['position'] if profile and profile['name'] == player['name'] and (game['status'] in feed.FINAL or self.clock() - roster_date < 7 * DAY) else None
                    roster_missing |= roster is None
                    people.append(dict(player, position=position, **translated_fields(self.season, player, position)))
                item['players'] = people
                item['statsCheckedAt'] = box_date
                item['statsStale'] = box_date is None or (game['status'] in feed.FINAL and box['phase'] not in feed.FINAL) or self.clock() - box_date > max(150, self.stats_ttl(game) * 2) or bool(self.db.execute('SELECT 1 FROM failures WHERE key=?', ('box-' + str(game['id']),)).fetchone())
                defense,defense_date=self.get('defense-'+str(game['id']))
                item['defenses']=(defense or {}).get('players',[])
                item['defenseCheckedAt']=defense_date
                item['defenseStale']=defense_date is None or (game['status'] in feed.FINAL and defense['phase'] not in feed.FINAL) or self.clock()-defense_date>max(300,self.stats_ttl(game)*2) or bool(self.db.execute('SELECT 1 FROM failures WHERE key=?',('defense-'+str(game['id']),)).fetchone())
                if item['stale'] or (game['status'] in feed.LIVE | feed.FINAL and (box is None or roster_missing or item['statsStale'])):
                    pending = True
                result.append(item)
            return dict(schema=1, provider='API-NFL', season=self.season, week=week,
                        fetchedAt=fetched, warming=pending and self.used() < BUDGET and self.state('pause') <= self.clock(), retryAfter=5 if pending else 20,
                        games=result)

    def health(self):
        with self.lock:
            return dict(provider='API-NFL', season=self.season, dailyBudget=BUDGET, requestsUsed=self.used(),
                        throttled=self.multiplier() > 1, paused=self.state('pause') > self.clock(),
                        demandWeeks=len(self.demand))


def handler(service):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            if self.headers.get('X-Blitz-NFL') != '1' or self.headers.get('Origin'):
                self.send_error(403)
                return
            match = re.fullmatch(r'/v1/seasons/([0-9]{4})/weeks/([1-9]|1[0-8])', self.path)
            if self.path == '/v1/status':
                value = service.health()
            elif match and int(match[1]) == service.season:
                teams = self.headers.get('X-Blitz-NFL-Teams', '')[:160].split(',')
                defense_teams = self.headers.get('X-Blitz-NFL-Defense', '')[:160].split(',')
                value = service.snapshot(int(match[2]), teams, defense_teams)
            else:
                self.send_error(404)
                return
            data = json.dumps(value, allow_nan=False).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass
    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--state-dir', type=Path, required=True)
    parser.add_argument('--key-file', type=Path, required=True)
    parser.add_argument('--season', type=int, required=True)
    parser.add_argument('--port', type=int, default=8793)
    args = parser.parse_args()
    os.umask(0o077)
    args.state_dir.mkdir(parents=True, exist_ok=True)
    process_lock = (args.state_dir / 'worker.lock').open('a')
    fcntl.flock(process_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    info = args.key_file.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise SystemExit('Key must be an owner-only regular file.')
    key = args.key_file.read_text().strip()
    if not key or len(key) > 512 or not key.isascii() or any(ord(c) < 33 or ord(c) > 126 for c in key):
        raise SystemExit('Invalid key file.')
    service = Service(args.state_dir / 'cache.sqlite3', key, args.season)
    def work():
        while True:
            try:
                service.tick()
            except Exception:
                # A malformed cached record cannot take down reads or spin the worker.
                with service.lock:
                    service.set_state('pause', time.time() + 60)
            service.wake.wait(2)
            service.wake.clear()
    threading.Thread(target=work, daemon=True).start()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), handler(service))
    server.daemon_threads = True
    server.serve_forever()


if __name__ == '__main__':
    main()
