#!/usr/bin/env python3
"""Closed-beta gateway. Only this authenticated loopback listener may use Funnel.

MFL sessions are verified transiently with MFL; never stored or logged.
No provider keys, email addresses or request bodies are logged.
The existing private services and their upstream request budgets remain shared.
"""
import argparse
import hashlib
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import sqlite3
import threading
import time


class Denied(Exception):
    pass


class Limited(Exception):
    pass


class Gateway:
    def __init__(self, config_path, database, clock=time.time, transport=None, verify_membership=None):
        self.config_path = Path(config_path)
        self.clock = clock
        self.transport = transport or self.forward
        self.verify_membership = verify_membership or self.mfl_membership
        self.auth_lock = threading.Lock()
        self.lock = threading.RLock()
        self.db = sqlite3.connect(database, check_same_thread=False)
        self.db.execute('PRAGMA secure_delete=ON')
        self.db.execute('CREATE TABLE IF NOT EXISTS registrations(kind TEXT, id TEXT, principal TEXT, device TEXT, expires REAL, PRIMARY KEY(kind,id))')
        self.db.execute('CREATE TABLE IF NOT EXISTS grants(digest TEXT PRIMARY KEY, scope TEXT, expires REAL)')
        self.db.execute('CREATE TABLE IF NOT EXISTS auth_state(key TEXT PRIMARY KEY, value REAL)')
        self.db.execute('CREATE TABLE IF NOT EXISTS limits(bucket TEXT PRIMARY KEY, window INTEGER, count INTEGER)')
        self.db.commit()

    def rate(self, bucket, maximum):
        window = int(self.clock() // 60)
        with self.lock:
            self.db.execute('DELETE FROM limits WHERE window < ?', (window,))
            row = self.db.execute('SELECT count FROM limits WHERE bucket=? AND window=?', (bucket, window)).fetchone()
            count = row[0] if row else 0
            if count >= maximum:
                raise Limited()
            self.db.execute('INSERT OR REPLACE INTO limits VALUES (?,?,?)', (bucket, window, count + 1))
            self.db.commit()

    def principal(self, token):
        self.rate('all', 600)
        if not re.fullmatch(r'[A-Za-z0-9_-]{43}', token):
            raise Denied()
        # Reload on every call so removing a team immediately revokes its access.
        config = json.loads(self.config_path.read_text())
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.lock:
            grant = self.db.execute('SELECT scope,expires FROM grants WHERE digest=?', (digest,)).fetchone()
        user = config.get('teams', {}).get(grant[0]) if grant and grant[1] > self.clock() else None
        if not user or user['expires'] <= self.clock():
            raise Denied()
        if not re.fullmatch(r'blitz-beta-[a-zA-Z0-9-]{1,50}', user['id']):
            raise Denied()
        self.rate('device:' + digest, 60)
        self.rate(user['id'], 240)
        return user

    def request(self, method, path, headers, raw=b''):
        if headers.get('Origin') or len(raw) > 16000:
            raise Denied()
        if method == 'POST' and path == '/v1/access':
            return self.enroll(raw)
        user = self.principal(headers.get('X-Blitz-Access', ''))
        if method == 'GET' and path == '/v1/access':
            return 200, dict(season=user['season'], leagueID=user['leagueID'],
                             franchiseID=user['franchiseID'], expiresAt=user['expires'])
        if method == 'DELETE' and path == '/v1/access':
            digest = hashlib.sha256(headers['X-Blitz-Access'].encode()).hexdigest()
            with self.lock:
                self.db.execute('DELETE FROM grants WHERE digest=?', (digest,))
                self.db.commit()
            return 200, {'removed': True}
        if method == 'GET' and path == '/v1/status':
            code, value = self.transport(8792, method, path, self.sync_headers(user), b'')
            if code != 200:
                return code, {'error': 'Service unavailable'}
            return 200, {key: value.get(key) for key in ('pushReady', 'productionPushReady', 'issue')} | {'subscriptions': 0, 'acceptedPushes': 0}
        nfl = re.fullmatch(r'/v1/seasons/([0-9]{4})/weeks/([1-9]|1[0-8])', path)
        if method == 'GET' and nfl and int(nfl[1]) == user['season']:
            safe = {'X-Blitz-NFL': '1'}
            for key in ('X-Blitz-NFL-Teams', 'X-Blitz-NFL-Defense'):
                if headers.get(key):
                    if not re.fullmatch(r'[A-Z,]{1,160}', headers[key]):
                        raise Denied()
                    safe[key] = headers[key]
            return self.transport(8793, method, path, safe, b'')
        history = re.fullmatch(r'/v1/timeline/([0-9]{4})/([0-9]{5})/([1-9]|1[0-9]|2[01])/([0-9]{4})/([0-9]{4})', path)
        if method == 'GET' and history:
            if int(history[1]) != user['season'] or history[2] != user['leagueID'] or user['franchiseID'] not in history.group(4, 5):
                raise Denied()
            return self.transport(8792, method, path, self.sync_headers(user), b'')
        match = re.fullmatch(r'/v1/(activities|lineup-alerts)/([A-Za-z0-9-]{1,80})', path)
        auth = headers.get('Authorization', '')
        if not match or method not in ('PUT', 'DELETE') or not re.fullmatch(r'Bearer [0-9a-f]{64}', auth):
            raise Denied()
        kind, sid = match.groups()
        device = hashlib.sha256(auth.encode()).hexdigest()
        if method == 'PUT':
            value = json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
            if value.get('season') != user['season'] or value.get('leagueID') != user['leagueID']:
                raise Denied()
            teams = [value.get('homeID'), value.get('awayID')] if kind == 'activities' else [value.get('franchiseID')]
            if user['franchiseID'] not in teams:
                raise Denied()
        with self.lock:
            self.db.execute('DELETE FROM registrations WHERE expires <= ?', (self.clock(),))
            old = self.db.execute('SELECT principal,device FROM registrations WHERE kind=? AND id=?', (kind, sid)).fetchone()
            if old and old != (user['id'], device):
                raise Denied()
            if method == 'DELETE' and not old:
                return 200, {'removed': True}
            if method == 'PUT' and not old:
                count = self.db.execute('SELECT COUNT(*) FROM registrations WHERE kind=? AND principal=?', (kind, user['id'])).fetchone()[0]
                if count >= 4:
                    raise Limited()
                # Reserve before forwarding. An uncertain response must not bypass limits.
                ttl = 8 * 3600 if kind == 'activities' else 8 * 86400
                self.db.execute('INSERT INTO registrations VALUES (?,?,?,?,?)', (kind, sid, user['id'], device, min(user['expires'], self.clock() + ttl)))
                self.db.commit()
            safe = self.sync_headers(user) | {'Authorization': auth, 'Content-Type': 'application/json'}
            code, result = self.transport(8792, method, path, safe, raw)
            if code == 200 and method == 'DELETE':
                self.db.execute('DELETE FROM registrations WHERE kind=? AND id=?', (kind, sid))
                self.db.commit()
            elif code == 200 and method == 'PUT' and isinstance(result.get('expiresAt'), (float, int)):
                self.db.execute('UPDATE registrations SET expires=? WHERE kind=? AND id=?', (min(user['expires'], result['expiresAt']), kind, sid))
                self.db.commit()
            return code, result

    def enroll(self, raw):
        self.rate('all', 600)
        value = json.loads(raw)
        token = value.get('deviceCredential', '')
        cookie = value.get('mflSession', '')
        season, league, franchise = value.get('season'), value.get('leagueID'), value.get('franchiseID')
        if (type(season) is not int or not isinstance(league, str) or not isinstance(franchise, str)
                or not isinstance(token, str) or not re.fullmatch(r'[A-Za-z0-9_-]{43}', token)
                or not isinstance(cookie, str) or not re.fullmatch(r'[!-~]{1,2048}', cookie)
                or any(char in cookie for char in ';,\\"')):
            raise Denied()
        scope = f'{season}.{league}.{franchise}'
        user = json.loads(self.config_path.read_text()).get('teams', {}).get(scope)
        if not user or user['expires'] <= self.clock():
            raise Denied()
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.auth_lock:
            with self.lock:
                self.db.execute('DELETE FROM grants WHERE expires<=?', (self.clock(),))
                grant = self.db.execute('SELECT scope,expires FROM grants WHERE digest=?', (digest,)).fetchone()
                self.db.commit()
            if grant:
                if grant[0] != scope:
                    raise Denied()
                return 200, self.receipt(user)  # Idempotent retry; no extra MFL call.
            self.rate('enrollment', 6)
            self.rate('enroll:' + digest, 2)
            with self.lock:
                cooldown = self.db.execute("SELECT value FROM auth_state WHERE key='next_mfl'").fetchone()
                if cooldown and cooldown[0] > self.clock():
                    raise Limited()
                count = self.db.execute('SELECT COUNT(*) FROM grants WHERE scope=?', (scope,)).fetchone()[0]
                if count >= 6:
                    raise Limited()
                self.db.execute("INSERT OR REPLACE INTO auth_state VALUES ('next_mfl',?)", (self.clock() + 2,))
                self.db.commit()
            try:
                verified = self.verify_membership(season, league, franchise, cookie)
            except Limited:
                with self.lock:
                    self.db.execute("INSERT OR REPLACE INTO auth_state VALUES ('next_mfl',?)", (self.clock() + 300,))
                    self.db.commit()
                raise
            if not verified:
                raise Denied()
            with self.lock:
                self.db.execute('INSERT INTO grants VALUES (?,?,?)', (digest, scope, user['expires']))
                self.db.commit()
        return 200, self.receipt(user)

    @staticmethod
    def receipt(user):
        return dict(season=user['season'], leagueID=user['leagueID'],
                    franchiseID=user['franchiseID'], expiresAt=user['expires'])

    @staticmethod
    def mfl_membership(season, league, franchise, cookie):
        # Fixed TLS origin, no redirects, no caller-supplied URL. Cookie exists
        # only for this request; passwords and complete responses are not retained.
        connection = http.client.HTTPSConnection('api.myfantasyleague.com', timeout=8)
        try:
            connection.request('GET', f'/{season}/export?TYPE=myleagues&JSON=1&YEAR={season}',
                               headers={'Cookie': 'MFL_USER_ID=' + cookie, 'User-Agent': 'MFL Blitz beta membership/0.7'})
            response = connection.getresponse()
            if response.status == 429:
                raise Limited()
            if response.status != 200:
                raise Denied()
            data = response.read(256001)
            if len(data) > 256000:
                raise Denied()
            value = json.loads(data)
            if 'rate' in str(value.get('error', '')).lower() or 'limit' in str(value.get('error', '')).lower():
                raise Limited()
            entries = value.get('leagues', {}).get('league', [])
            if isinstance(entries, dict):
                entries = [entries]
            return any(str(item.get('league_id')) == league and str(item.get('franchise_id')) == franchise for item in entries)
        finally:
            connection.close()

    @staticmethod
    def sync_headers(user):
        return {'X-Blitz-Sync': '1', 'Tailscale-User-Login': user['id']}

    @staticmethod
    def forward(port, method, path, headers, body):
        # Fixed loopback destinations and allowlisted paths; never follow redirects.
        connection = http.client.HTTPConnection('127.0.0.1', port, timeout=8)
        try:
            connection.request(method, path, body=body or None, headers=headers)
            response = connection.getresponse()
            if response.status not in (200, 400, 403, 429):
                return 503, {'error': 'Service unavailable'}
            data = response.read(5_000_001)
            if len(data) > 5_000_000:
                return 503, {'error': 'Service unavailable'}
            return response.status, json.loads(data)
        finally:
            connection.close()


class Server(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, gateway):
        self.gateway = gateway
        self.slots = threading.BoundedSemaphore(16)
        super().__init__(address, Handler)
    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise
    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()
    def handle_error(self, *_):
        pass


class Handler(BaseHTTPRequestHandler):
    server_version = 'Blitz'
    def log_message(self, *_):
        pass
    def setup(self):
        super().setup()
        self.connection.settimeout(8)
    def handle_request(self):
        try:
            if self.headers.get('Transfer-Encoding') or any(len(self.headers.get_all(key, [])) > 1 for key in ('X-Blitz-Access', 'Authorization', 'Content-Length', 'Content-Type')):
                raise Denied()
            length = int(self.headers.get('Content-Length', '0'))
            if length < 0 or length > 16000 or (self.command in ('PUT', 'POST') and self.headers.get_content_type() != 'application/json'):
                raise Denied()
            code, value = self.server.gateway.request(self.command, self.path, self.headers, self.rfile.read(length))
        except Denied:
            code, value = 403, {'error': 'Access denied'}
        except Limited:
            code, value = 429, {'error': 'Please try again later'}
        except (ValueError, TypeError, KeyError, AttributeError):
            code, value = 400, {'error': 'Invalid request'}
        except Exception:
            code, value = 503, {'error': 'Service unavailable'}
        data = json.dumps(value, allow_nan=False).encode()
        self.send_response(code)
        for key, val in [('Content-Type', 'application/json'), ('Cache-Control', 'no-store'), ('X-Content-Type-Options', 'nosniff'), ('Content-Length', str(len(data))), ('Connection', 'close')]:
            self.send_header(key, val)
        if code == 429:
            self.send_header('Retry-After', '60')
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
    do_GET = do_PUT = do_DELETE = do_POST = do_OPTIONS = handle_request


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--state-dir', required=True, type=Path)
    parser.add_argument('--port', type=int, default=8794)
    args = parser.parse_args()
    os.umask(0o077)
    args.state_dir.mkdir(parents=True, exist_ok=True)
    gateway = Gateway(args.config, args.state_dir / 'access.sqlite3')
    Server(('127.0.0.1', args.port), gateway).serve_forever()
