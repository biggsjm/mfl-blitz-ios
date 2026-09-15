"""Bounded observed score history. Reads never initiate MFL/provider polling."""
import hashlib
import json
from scoring import number, ticks, STALE_AFTER

RETENTION = 21 * 86400
LIMIT = 2000


class Timeline:
    def __init__(self, db):
        self.db = db
        db.executescript('''
            CREATE TABLE IF NOT EXISTS timeline_state (key TEXT PRIMARY KEY, body TEXT NOT NULL, at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS timeline_events (key TEXT NOT NULL, id TEXT NOT NULL, at REAL NOT NULL,
                body TEXT NOT NULL, PRIMARY KEY(key,id));
            CREATE INDEX IF NOT EXISTS timeline_age ON timeline_events(at);
        ''')

    @staticmethod
    def key(season, league, week, away, home):
        return '.'.join(map(str, [season, league, week, *sorted([away, home])]))

    def prune(self, now):
        self.db.execute('DELETE FROM timeline_events WHERE at<?', (now-RETENTION,))
        self.db.execute('DELETE FROM timeline_state WHERE at<?', (now-RETENTION,))
        self.db.execute('DELETE FROM timeline_state WHERE key NOT IN (SELECT key FROM timeline_state ORDER BY at DESC LIMIT 64)')
        self.db.execute('DELETE FROM timeline_events WHERE key NOT IN (SELECT key FROM timeline_state)')

    def record(self, subscription, teams, state, now):
        self.prune(now)
        key = self.key(subscription['season'], subscription['leagueID'], subscription['week'], subscription['awayID'], subscription['homeID'])
        row = self.db.execute('SELECT body,at FROM timeline_state WHERE key=?', (key,)).fetchone()
        if row and now <= row[1]:
            return
        before = json.loads(row[0]) if row else None
        def add(kind, name, tid=None, pid=None, previous=None, current=None):
            identity = f'{key}|{now}|{kind}|{tid}|{pid}'
            event = dict(id=hashlib.sha256(identity.encode()).hexdigest(), at=now, kind=kind, name=name,
                         teamID=tid, playerID=pid, previous=previous, current=current, source='background',
                         fromAt=row[1] if row else None)
            self.db.execute('INSERT OR IGNORE INTO timeline_events VALUES (?,?,?,?)',
                (key,event['id'],now,json.dumps(event,allow_nan=False)))
        if not before:
            add('tracking','Recording started from the first saved score')
        elif now-row[1] >= STALE_AFTER and needs_gap(before, teams, state, now):
            add('gap','Updates were unavailable between saved checks')
        if before:
            for side in ('away','home'):
                tid=subscription[side+'ID']; old=before['teams'].get(tid); new=teams[tid]
                if not old:
                    continue
                if ticks(old['score'],subscription['precision']) != ticks(new['score'],subscription['precision']):
                    add('team', subscription[side+'Abbreviation']+' total', tid,
                        previous=float(number(old['score'])),current=float(number(new['score'])))
                if old['starters'].keys() == new['starters'].keys() and not old['unknown'] and not new['unknown']:
                    for pid,value in new['starters'].items():
                        previous=old['starters'][pid]
                        if value is not None and previous is not None and ticks(value,subscription['precision']) != ticks(previous,subscription['precision']):
                            add('player',subscription['playerNames'].get(pid,'Starter'),tid,pid,float(number(previous)),float(number(value)))
            if state.get('phase')=='final' and before.get('phase')!='final':
                add('final','Final score confirmed by MFL')
        self.db.execute('INSERT OR REPLACE INTO timeline_state VALUES (?,?,?)',
            (key,json.dumps(dict(teams=teams,phase=state.get('phase'),nextKickoff=state.get('nextKickoff')),allow_nan=False),now))
        self.db.execute('DELETE FROM timeline_events WHERE key=? AND id NOT IN '
            '(SELECT id FROM timeline_events WHERE key=? ORDER BY at DESC,id LIMIT ?)',(key,key,LIMIT))

    def read(self, season, league, week, away, home, now):
        self.prune(now)
        key=self.key(season,league,week,away,home)
        rows=self.db.execute('SELECT body FROM timeline_events WHERE key=? ORDER BY at DESC,id LIMIT ?', (key,LIMIT)).fetchall()
        saved=self.db.execute('SELECT at FROM timeline_state WHERE key=?',(key,)).fetchone()
        return dict(schema=1, season=season,leagueID=league,week=week,teamIDs=sorted([away,home]),
                    checkedAt=saved[0] if saved else None,events=[json.loads(row[0]) for row in rows],retentionDays=21)


def needs_gap(before, teams, state, now):
    """Suppress only intervals known to be quiet; a long elapsed gap is not proof."""
    old_teams = before.get('teams', {})
    if old_teams.keys() != teams.keys() or any(
        old_teams[tid].get('unknown') or team.get('unknown') or
        old_teams[tid]['starters'].keys() != team['starters'].keys()
        for tid, team in teams.items()
    ):
        return True
    if before.get('phase') == state.get('phase') == 'final':
        return False
    if before.get('phase') == state.get('phase') == 'waiting':
        # ActivityKit dates use Apple's reference epoch, not Unix time.
        kickoff = before.get('nextKickoff')
        if isinstance(kickoff, (int, float)) and kickoff == state.get('nextKickoff') and now < kickoff + 978307200:
            return False
    return True
