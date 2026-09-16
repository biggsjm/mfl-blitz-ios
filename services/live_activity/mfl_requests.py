"""One paced, cached MFL reader shared by existing scoring/alert consumers."""
from copy import deepcopy
from email.utils import parsedate_to_datetime
import json
import math
import re
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class MFLThrottled(Exception):
    pass


class MFL:
    def __init__(self, leagues, state_file=':memory:', *, clock=time.time, sleep=time.sleep, opener=None,
                 user_agent='MFL Blitz/0.1 (com.biggsjm.MFLBlitz)'):
        self.leagues, self.clock, self.sleep = leagues, clock, sleep
        self.user_agent = user_agent
        self.opener = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        self.lock = threading.RLock()
        self.db = sqlite3.connect(str(state_file), check_same_thread=False)
        self.db.execute('CREATE TABLE IF NOT EXISTS limits (host TEXT PRIMARY KEY, next REAL NOT NULL, cooldown REAL NOT NULL)')
        self.cache = {}
        # Bounded counters only. No URLs, IDs, terms, response bodies or tokens.
        self.counts = {'network': 0, 'cache': 0, 'throttled': 0}

    def read(self, season, league, week):
        return self.read_with_receipt(season, league, week)[0]

    def read_with_receipt(self, season, league, week):
        return self._export(season, league, week, 'liveScoring')

    def export(self, season, league, week, kind):
        return self._export(season, league, week, kind)[0]

    def _export(self, season, league, week, kind):
        if kind not in ('liveScoring', 'nflSchedule', 'injuries'): raise ValueError('export')
        league_host = self.leagues[f'{season}.{league}']
        if not re.fullmatch(r'www[0-9]{1,3}\.myfantasyleague\.com', league_host): raise ValueError('invalid MFL host')
        host = league_host if kind == 'liveScoring' else 'api.myfantasyleague.com'
        parameters = dict(TYPE=kind, W=week, DETAILS=1, JSON=1)
        if kind == 'liveScoring': parameters['L'] = league
        key = (host, season, week, kind, league if kind == 'liveScoring' else None)
        with self.lock:
            now = self.clock()
            cached = self.cache.get(key)
            if cached and 0 <= now-cached[1] < 60:
                self.counts['cache'] += 1
                return deepcopy(cached)
            next_at, cooldown = self.db.execute('SELECT next,cooldown FROM limits WHERE host=?', (host,)).fetchone() or (0, 0)
            if cooldown > now:
                self.counts['throttled'] += 1
                raise MFLThrottled('MFL cooldown')
            if next_at > now: self.sleep(next_at-now)
            # Reserve before sending; shared across worker consumers and restarts.
            self.db.execute('INSERT OR REPLACE INTO limits VALUES (?,?,?)', (host, self.clock()+1.25, cooldown))
            self.db.commit()
            request = urllib.request.Request(f'https://{host}/{season}/export?{urllib.parse.urlencode(parameters)}',
                headers={'User-Agent': self.user_agent, 'Accept': 'application/json'})
            self.counts['network'] += 1
            try:
                with self.opener.open(request, timeout=15) as response:
                    data = response.read(2_000_001)
                    if len(data) > 2_000_000: raise ValueError('response too large')
                    if int(response.headers.get('Age', '0')) >= 210: raise ValueError('stale upstream cache')
                    document = json.loads(data)
                    if not isinstance(document, dict) or 'error' in document: raise ValueError('invalid MFL response')
            except urllib.error.HTTPError as error:
                if error.code != 429: raise
                self.counts['throttled'] += 1
                deadline = self.clock() + self.retry_delay(error.headers.get('Retry-After'), self.clock())
                self.db.execute('UPDATE limits SET cooldown=? WHERE host=?', (deadline, host))
                self.db.commit()
                raise MFLThrottled('MFL cooldown') from None
            receipt = (document, self.clock())
            if len(self.cache) >= 64: self.cache.clear()
            self.cache[key] = deepcopy(receipt)
            return receipt

    @staticmethod
    def retry_delay(raw, now):
        try:
            delay = float(raw)
        except (ValueError, TypeError):
            try: delay = parsedate_to_datetime(raw).timestamp() - now
            except (ValueError, TypeError, OverflowError): return 90
        return max(1, delay) if math.isfinite(delay) and 0 <= delay < 2**53 else 90
