#!/usr/bin/env python3
"""Private Tailscale Serve backend: MFL reads -> ActivityKit APNs updates.

Bind only loopback. Serve supplies authenticated identity headers. No cookies,
MFL credentials, provider-NFL calls, access logs, or public listener.
"""
import argparse
import base64
from copy import deepcopy
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from scoring import APPLE_EPOCH, array, integer, payload, read_matchup, updated_state, validate_subscription
from mfl_requests import MFL

INTERVAL = 60
MAX_LIFETIME = 7 * 3600 + 50 * 60
MAX_SUBSCRIPTIONS = 8


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None



def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def raw_signature(der):
    # OpenSSL's P-256 DER sequence contains two short unsigned integers.
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2 or der[2] != 2:
        raise ValueError('invalid ES256 signature')
    size = der[3]
    r = der[4:4 + size]
    offset = 4 + size
    if der[offset] != 2 or offset + 2 + der[offset + 1] != len(der):
        raise ValueError('invalid ES256 signature')
    s = der[offset + 2:]
    return int.from_bytes(r, 'big').to_bytes(32, 'big') + int.from_bytes(s, 'big').to_bytes(32, 'big')


class APNs:
    def __init__(self, config):
        self.config = config
        self.cached_jwt = None
        self.issued_at = 0
        self.production = APNs(config['productionAPNs']) if config.get('productionAPNs') else None

    @property
    def ready(self):
        return self.ready_for('sandbox') or self.ready_for('production')

    def ready_for(self, environment):
        if environment == 'production':
            return bool(self.production and self.production.ready_for('sandbox'))
        if environment != 'sandbox': return False
        p = Path(self.config.get('apnsKeyFile', '/nonexistent'))
        return (p.is_file() and p.stat().st_mode & 0o077 == 0
                and bool(re.fullmatch(r'[A-Z0-9]{10}', self.config.get('apnsKeyID', '')))
                and bool(re.fullmatch(r'[A-Z0-9]{10}', self.config.get('apnsTeamID', ''))))

    def jwt(self, now):
        if self.cached_jwt and 0 <= now - self.issued_at < 3000:
            return self.cached_jwt
        header = b64(json.dumps({'alg': 'ES256', 'kid': self.config['apnsKeyID']}, separators=(',', ':')).encode())
        claims = b64(json.dumps({'iss': self.config['apnsTeamID'], 'iat': int(now)}, separators=(',', ':')).encode())
        message = (header + '.' + claims).encode()
        r = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', self.config['apnsKeyFile']],
                           input=message, capture_output=True, timeout=10)
        if r.returncode:
            raise ValueError('push signing unavailable')
        self.cached_jwt = message.decode() + '.' + b64(raw_signature(r.stdout))
        self.issued_at = now
        return self.cached_jwt

    def send(self, subscription, data, now, alert=False, collapse=None):
        host = 'api.sandbox.push.apple.com' if subscription['environment'] == 'sandbox' else 'api.push.apple.com'
        # Sensitive URL/token/JWT and payload travel through stdin, never argv.
        options = {'url': f'https://{host}/3/device/{subscription["token"]}',
                   'request': 'POST', 'data': data.decode(), 'write-out': '\n%{http_code}'}
        signer = self.production if subscription['environment'] == 'production' else self
        if signer is None: return 503
        headers = ['authorization: bearer ' + signer.jwt(now), 'apns-push-type: '+('alert' if alert else 'liveactivity'),
                   'apns-topic: com.biggsjm.MFLBlitz'+('' if alert else '.push-type.liveactivity'), 'apns-priority: '+('10' if alert else '5'),
                   'apns-expiration: ' + str(int(min(now + 210, subscription.get('deliveryExpiresAt', now + 210)) if alert else now + 210)), 'content-type: application/json']
        if alert and collapse: headers.append('apns-collapse-id: '+collapse)
        # curl config strings understand quotes/backslashes/newlines, but not
        # JSON's Unicode escapes: \u2013 becomes the literal text u2013.
        # Preserve UTF-8 here; JSON escapes already inside data stay doubled
        # through this outer quoting layer and reach APNs unchanged.
        config = '\n'.join(f'{k} = {json.dumps(v, ensure_ascii=False)}' for k, v in options.items())
        config += '\n' + '\n'.join('header = ' + json.dumps(h, ensure_ascii=False) for h in headers)
        r = subprocess.run(['curl', '--disable', '--http2', '--silent', '--max-time', '15', '--noproxy', '*', '--config', '-'],
                           input=config.encode(), capture_output=True, timeout=20)
        if r.returncode:
            return 503
        try:
            return int(r.stdout.rsplit(b'\n', 1)[1])
        except (ValueError, IndexError):
            return 503


class Service:
    def __init__(self, config, database, mfl=None, apns=None, clock=time.time):
        self.config = config
        self.clock = clock
        self.mfl = mfl or MFL(config['leagues'], Path(database).with_name('mfl-requests.sqlite3'),
                              user_agent=config.get('mflUserAgent', 'MFL Blitz/0.1 (com.biggsjm.MFLBlitz)'))
        self.apns = apns or APNs(config)
        self.lock = threading.RLock()
        self.db = sqlite3.connect(database, check_same_thread=False)
        self.db.execute('PRAGMA secure_delete=ON')
        self.db.execute('CREATE TABLE IF NOT EXISTS tombstones (id TEXT PRIMARY KEY, expires REAL NOT NULL)')
        self.db.execute('CREATE TABLE IF NOT EXISTS subscriptions (id TEXT PRIMARY KEY, owner TEXT NOT NULL, body TEXT NOT NULL, expires REAL NOT NULL)')
        self.db.execute('CREATE TABLE IF NOT EXISTS polls (id TEXT PRIMARY KEY, due REAL NOT NULL, failures INTEGER NOT NULL)')
        self.db.execute('CREATE TABLE IF NOT EXISTS lifecycle (at REAL NOT NULL, event TEXT NOT NULL)')
        from timeline import Timeline
        self.timeline = Timeline(self.db)
        from nfl_context import NFLCache
        self.nfl = NFLCache()
        from lineup_alerts import LineupAlerts
        self.alerts = LineupAlerts(self)
        self.db.commit()
        self.pause_until = 0
        self.last_error = None
        self.accepted_pushes = 0

    def push_ready(self, environment):
        return self.apns.ready_for(environment) if hasattr(self.apns, 'ready_for') else self.apns.ready

    def lifecycle(self, event):
        # Bounded diagnostic reasons, without activity IDs, teams or credentials.
        self.db.execute('INSERT INTO lifecycle VALUES (?,?)', (self.clock(), event))
        self.db.execute('DELETE FROM lifecycle WHERE rowid NOT IN (SELECT rowid FROM lifecycle ORDER BY rowid DESC LIMIT 64)')

    def prune(self):
        self.timeline.prune(self.clock())
        if self.db.execute('SELECT 1 FROM subscriptions WHERE expires <= ?', (self.clock(),)).fetchone():
            self.lifecycle('Subscription lifetime expired')
        self.db.execute('DELETE FROM tombstones WHERE expires <= ?', (self.clock(),))
        self.db.execute('INSERT OR REPLACE INTO tombstones SELECT id,? FROM subscriptions WHERE expires <= ?', (self.clock() + MAX_LIFETIME, self.clock()))
        self.db.execute('DELETE FROM subscriptions WHERE expires <= ?', (self.clock(),))
        self.db.commit()

    def register(self, sid, owner, value):
        now = self.clock()
        body = validate_subscription(value, now, self.config['leagues'])
        with self.lock:
            self.prune()
            if self.db.execute('SELECT 1 FROM tombstones WHERE id=?', (sid,)).fetchone():
                raise ValueError('activity ended')
            row = self.db.execute('SELECT owner,body,expires FROM subscriptions WHERE id=?', (sid,)).fetchone()
            if row and row[0] != owner:
                raise PermissionError()
            if not row and self.db.execute('SELECT COUNT(*) FROM subscriptions').fetchone()[0] >= MAX_SUBSCRIPTIONS:
                raise OverflowError()
            if row:
                old = json.loads(row[1])
                if body['revision'] <= old['revision']:
                    return {'registered': True, 'pushReady': self.push_ready(old['environment']), 'expiresAt': row[2]}
                identity = ('season', 'leagueID', 'week', 'homeID', 'awayID', 'environment', 'precision')
                if any(old[k] != body[k] for k in identity):
                    raise ValueError('activity scope changed')
                # A foreground re-registration may add artwork or rotate a token,
                # but must never replace a newer server score or its baseline.
                for k in ('baseline', 'baselineAt', 'lastPushAt'):
                    if k in old:
                        body[k] = old[k]
                for side in ('home', 'away'):
                    key = side + 'Artwork'
                    saved = old['state'].get(key)
                    incoming = body['state'].get(key)
                    if saved and not incoming:
                        body['state'][key] = saved
                    elif saved and incoming and not incoming.get('thumbnail') and all(incoming[c] == saved[c] for c in ('red', 'green', 'blue')):
                        if saved.get('thumbnail'):
                            incoming['thumbnail'] = saved['thumbnail']
                if old['state']['updatedAt'] >= body['state']['updatedAt']:
                    for k in ('homeScore', 'awayScore', 'homeProjection', 'awayProjection', 'activePlayers', 'updatedAt', 'latestChange', 'phase',
                              'homePlaying','awayPlaying','homeYetToPlay','awayYetToPlay','nextKickoff','statContext','continuationNeeded'):
                        if k in old['state']:
                            body['state'][k] = old['state'][k]
                        else:
                            body['state'].pop(k, None)
                expiry = row[2]
            else:
                self.lifecycle('Phone registered a new activity')
                expiry = now + MAX_LIFETIME
                body['baselineAt'] = body['state']['updatedAt'] + APPLE_EPOCH
                body['baseline'] = {body[side + 'ID']: {'score': body['state'][side + 'Score'],
                    'starters': {}, 'unknown': True} for side in ('home', 'away')}
            self.db.execute('INSERT OR REPLACE INTO subscriptions VALUES (?,?,?,?)', (sid, owner, json.dumps(body), expiry))
            self.db.commit()
        return {'registered': True, 'pushReady': self.push_ready(body['environment']), 'expiresAt': expiry}

    def delete(self, sid, owner):
        with self.lock:
            row = self.db.execute('SELECT owner FROM subscriptions WHERE id=?', (sid,)).fetchone()
            if row and row[0] != owner:
                raise PermissionError()
            if row:
                self.lifecycle('Phone removed the subscription')
            self.db.execute('INSERT OR REPLACE INTO tombstones VALUES (?,?)', (sid, self.clock() + MAX_LIFETIME))
            self.db.execute('DELETE FROM subscriptions WHERE id=? AND owner=?', (sid, owner))
            self.db.commit()

    def status(self):
        with self.lock:
            self.prune()
            return {'pushReady': self.push_ready('sandbox'), 'productionPushReady': self.push_ready('production'), 'subscriptions': self.db.execute('SELECT COUNT(*) FROM subscriptions').fetchone()[0],
                    'acceptedPushes': self.accepted_pushes, 'issue': self.last_error,
                    'mflRequests': dict(getattr(self.mfl, 'counts', {}))}

    def tick(self):
        with self.lock:
            self.prune()
            now = self.clock()
            if not self.apns.ready or now < self.pause_until:
                return
            rows = self.db.execute('SELECT id,body FROM subscriptions').fetchall()
            groups = {}
            for sid, raw in rows:
                body = json.loads(raw)
                if not self.push_ready(body['environment']): continue
                key = (body['season'], body['leagueID'], body['week'])
                groups.setdefault(key, []).append(sid)
        for key, ids in groups.items():
            poll_id = '.'.join(map(str, key))
            with self.lock:
                prior = self.db.execute('SELECT due,failures FROM polls WHERE id=?', (poll_id,)).fetchone()
                if prior and now < prior[0]:
                    continue
                failures = prior[1] if prior else 0
                # Reserve before network; survives crashes/restarts and new registrations.
                self.db.execute('INSERT OR REPLACE INTO polls VALUES (?,?,?)', (poll_id, now + INTERVAL, failures))
                self.db.commit()
            try:
                if hasattr(self.mfl, 'read_with_receipt'):
                    document, checked = self.mfl.read_with_receipt(*key)
                else:
                    document = self.mfl.read(*key)
                    checked = self.clock()
                # Reject missing/wrong week before advancing any baseline.
                if integer(document.get('liveScoring', {}).get('week'), 1, 21) != key[2]:
                    raise ValueError('wrong week')
            except Exception:
                with self.lock:
                    self.last_error = 'MFL scores unavailable'
                    delay = min(900, INTERVAL * 2 ** min(failures + 1, 4))
                    self.db.execute('UPDATE polls SET due=?,failures=? WHERE id=?', (self.clock() + delay, failures + 1, poll_id))
                    self.db.commit()
                continue
            with self.lock:
                self.db.execute('UPDATE polls SET failures=0 WHERE id=?', (poll_id,))
                self.db.commit()
            with self.lock:
                profiles=[p for sid in ids
                    if (row:=self.db.execute('SELECT body FROM subscriptions WHERE id=?',(sid,)).fetchone())
                    for p in json.loads(row[0]).get('playerProfiles',{}).values()]
            defense_teams={p['team'] for p in profiles if p['position'] in ('DEF','DF','DST','D/ST')}
            nfl_document=self.nfl.read(key[0],key[2],defense_teams) if profiles else None
            for sid in ids:
                with self.lock:
                    # Deletion/scope replacement while MFL was in flight cannot resurrect a subscription.
                    row = self.db.execute('SELECT body,expires FROM subscriptions WHERE id=?', (sid,)).fetchone()
                    if not row or row[1] <= self.clock():
                        continue
                    body = json.loads(row[0])
                    if checked - APPLE_EPOCH < body['state']['updatedAt']:
                        continue
                    try:
                        teams = read_matchup(document, body)
                        state = updated_state(body, teams, checked)
                        from nfl_context import enrich
                        enrich(state,body,nfl_document,checked)
                        state['continuationNeeded']=row[1]-checked <= 1800 and state.get('phase')!='final'
                        self.timeline.record(body, teams, state, checked)
                        final = state['phase'] == 'final'
                        result = self.apns.send(body, payload(state, checked, final, body['attributeBytes']), checked)
                    except Exception:
                        self.last_error = 'Score update unavailable'
                        continue
                    # Keep last observed delta through transient push failures; timestamps
                    # stay tied to successful MFL reads, never to retries or old cached data.
                    body.update(state=state, baseline=teams, baselineAt=checked)
                    if result == 200:
                        self.accepted_pushes += 1
                        self.last_error = None
                        body['lastPushAt'] = checked
                    if result == 410 or (result == 200 and final):
                        self.lifecycle('Apple reported an inactive activity token' if result == 410 else 'Sent confirmed final score and end')
                        self.db.execute('INSERT OR REPLACE INTO tombstones VALUES (?,?)', (sid, self.clock() + MAX_LIFETIME))
                        self.db.execute('DELETE FROM subscriptions WHERE id=?', (sid,))
                    else:
                        self.db.execute('UPDATE subscriptions SET body=? WHERE id=?', (json.dumps(body), sid))
                    if result in (400, 403, 404):
                        self.last_error = 'Apple push configuration needs attention'
                        self.pause_until = self.clock() + 900
                    elif result != 200 and result != 410:
                        self.last_error = 'Apple push temporarily unavailable'
                    self.db.commit()
                    if self.clock() < self.pause_until:
                        return


class Handler(BaseHTTPRequestHandler):
    server_version = 'BlitzSync'

    def log_message(self, *_):
        pass

    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def respond(self, code, value):
        data = json.dumps(value, separators=(',', ':')).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(data)

    def handle_request(self):
        service = self.server.service
        # Only tailscaled can reach this loopback backend remotely. Serve strips
        # spoofed identity headers; config explicitly allows the owner's identity.
        login = self.headers.get('Tailscale-User-Login', '')
        if (self.headers.get('Origin') or login not in service.config['allowedLogins']
                or self.headers.get('X-Blitz-Sync') != '1'):
            self.respond(403, {'error': 'Access denied'})
            return
        if self.command == 'GET' and self.path == '/v1/status':
            self.respond(200, service.status())
            return
        history = re.fullmatch(r'/v1/timeline/([0-9]{4})/([0-9]{5})/([1-9]|1[0-9]|2[01])/([0-9]{4})/([0-9]{4})', self.path)
        if self.command == 'GET' and history:
            season,league,week,away,home=history.groups()
            if f'{season}.{league}' not in service.config['leagues'] or away==home:
                self.respond(403, {'error':'Access denied'}); return
            with service.lock:
                result=service.timeline.read(int(season),league,int(week),away,home,service.clock())
                service.db.commit()
            self.respond(200,result)
            return
        match = re.fullmatch(r'/v1/(activities|lineup-alerts)/([A-Za-z0-9-]{1,80})', self.path)
        auth = self.headers.get('Authorization', '')
        if not match or not re.fullmatch(r'Bearer [0-9a-f]{64}', auth):
            self.respond(400, {'error': 'Invalid request'})
            return
        owner = hashlib.sha256((login + '|' + auth).encode()).hexdigest()
        sid = match[2]
        target = service.alerts if match[1] == "lineup-alerts" else service
        try:
            if self.command == 'DELETE':
                target.delete(sid, owner)
                self.respond(200, {'removed': True})
            elif self.command == 'PUT':
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 16000 or self.headers.get('Transfer-Encoding') or self.headers.get_content_type() != 'application/json':
                    raise ValueError('invalid body')
                value = json.loads(self.rfile.read(length))
                self.respond(200, target.register(sid, owner, value))
            else:
                self.respond(405, {'error': 'Unsupported method'})
        except PermissionError:
            self.respond(403, {'error': 'Access denied'})
        except OverflowError:
            self.respond(429, {'error': 'Subscription limit reached'})
        except (ValueError, TypeError, KeyError, AttributeError):
            self.respond(400, {'error': 'Invalid subscription'})
        except Exception:
            self.respond(503, {'error': 'Service unavailable'})

    do_GET = do_PUT = do_DELETE = handle_request


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--state-dir', type=Path, required=True)
    parser.add_argument('--port', type=int, default=8792)
    args = parser.parse_args()
    os.umask(0o077)
    config = json.loads(args.config.read_text())
    if not config.get('allowedLogins') or not config.get('leagues'):
        raise SystemExit('Owner and league configuration required')
    args.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    service = Service(config, str(args.state_dir / 'subscriptions.sqlite3'))
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    server.daemon_threads = True
    server.service = service
    def worker():
        while True:
            try:
                service.tick()
                service.alerts.tick()
            except Exception:
                service.last_error = 'Sync needs attention'
            time.sleep(5)
    threading.Thread(target=worker, daemon=True).start()
    server.serve_forever()


if __name__ == '__main__':
    main()
