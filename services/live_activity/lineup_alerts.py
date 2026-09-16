"""Opt-in, bounded lineup notifications. Saved MFL starters only; no NFL API calls."""
import hashlib
import json
import re
from scoring import array, integer

LIFETIME = 8*86400
OPTIONS = ('reminder', 'unavailable', 'incomplete')


def validate(value, leagues, now):
    season=integer(value['season'],2020,2100); league=value['leagueID']; franchise=value['franchiseID']
    if f'{season}.{league}' not in leagues or not re.fullmatch(r'[0-9]{4}',franchise):
        raise ValueError('scope')
    if not re.fullmatch(r'[0-9a-f]{64,512}',value['token']) or value['environment'] not in ('sandbox','production'):
        raise ValueError('push')
    options=value['options']
    if set(options)!=set(OPTIONS) or any(type(v) is not bool for v in options.values()) or not any(options.values()):
        raise ValueError('options')
    profiles=value['players']
    if not isinstance(profiles,dict) or not 1<=len(profiles)<=100:
        raise ValueError('players')
    for pid,p in profiles.items():
        if not re.fullmatch(r'[0-9]{1,8}',pid) or not isinstance(p,dict): raise ValueError('player')
        if not isinstance(p.get('name'),str) or not 1<=len(p['name'])<=80 or not re.fullmatch(r'[A-Z]{2,3}',p.get('team','')):
            raise ValueError('profile')
    return dict(season=season,leagueID=league,franchiseID=franchise,week=integer(value['week'],1,18),
        required=integer(value['required'],1,40),token=value['token'],environment=value['environment'],options=options,
        players=profiles,revision=integer(value['revision'],1,9_000_000_000_000))


def candidates(body, live, schedule, injuries, now):
    """Fresh reads, explicit current-week scopes, and a still-open kickoff window."""
    week=body['week']; root=live.get('liveScoring',{}); games=schedule.get('nflSchedule',{})
    if integer(root.get('week'),1,21)!=week or integer(games.get('week'),1,21)!=week: raise ValueError('week')
    franchises=[f for m in array(root.get('matchup')) for f in array(m.get('franchise')) if f.get('id')==body['franchiseID']]
    if len(franchises)!=1: return []
    players=array(franchises[0].get('players',{}).get('player'))
    if not players or len({p.get('id') for p in players})!=len(players) or any(p.get('status') not in ('starter','nonstarter') for p in players): return []
    starters={p['id'] for p in players if p['status']=='starter'}
    kickoffs={}
    for game in array(games.get('matchup')):
        start=integer(game.get('kickoff'),1,32_503_680_000)
        for team in array(game.get('team')):
            code=team.get('id')
            if code in kickoffs: raise ValueError('duplicate team')
            kickoffs[code]=start
    # A roster window remains relevant even when no starters were submitted.
    windows=sorted({kickoffs[p['team']] for p in body['players'].values() if p['team'] in kickoffs and 0<kickoffs[p['team']]-now<=1800})
    if not windows: return []
    window=windows[0]; result=[]
    def add(kind,text,pid=''):
        result.append((f'{body["season"]}.{body["leagueID"]}.{body["franchiseID"]}.{week}.{window}.{kind}.{pid}',text))
    if body['options']['incomplete'] and len(starters)<body['required']:
        count=body['required']-len(starters)
        add('incomplete',f'Your saved Week {week} lineup has {count} open starter slot'+('s.' if count!=1 else '.'))
    injury=injuries.get('injuries',{}) if injuries else {}
    try: recent=integer(injury.get('week'),1,21)==week and 0<=now-integer(injury.get('timestamp'),1,32_503_680_000)<48*3600
    except (ValueError,TypeError): recent=False
    if body['options']['unavailable'] and recent:
        entries=array(injury.get('injury')); unique={p['id'] for p in entries if isinstance(p.get('id'),str)}
        if len(unique)==len(entries):
            for p in entries:
                pid=p.get('id'); profile=body['players'].get(pid)
                status=str(p.get('status','')).strip().casefold()
                if pid in starters and profile and kickoffs.get(profile['team'])==window and status in ('out','ir','injured reserve','inactive'):
                    add('unavailable',f'MFL lists saved starter {profile["name"]} as {status}. Check your lineup before kickoff.',pid)
    if body['options']['reminder']:
        add('reminder',f'Week {week}: check your saved lineup before the next kickoff.')
    return result


class LineupAlerts:
    def __init__(self,service):
        self.service=service; self.cache={}; self.next_check=0
        service.db.executescript('''CREATE TABLE IF NOT EXISTS lineup_alerts(id TEXT PRIMARY KEY,owner TEXT NOT NULL,body TEXT NOT NULL,expires REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS lineup_alert_sent(owner TEXT NOT NULL,id TEXT NOT NULL,expires REAL NOT NULL,PRIMARY KEY(owner,id));
        CREATE TABLE IF NOT EXISTS lineup_alert_deleted(id TEXT PRIMARY KEY,expires REAL NOT NULL);''')
    def prune(self,now):
        for table in ('lineup_alerts','lineup_alert_sent','lineup_alert_deleted'):
            self.service.db.execute(f'DELETE FROM {table} WHERE expires<=?',(now,))
    def register(self,sid,owner,value):
        s=self.service; body=validate(value,s.config['leagues'],s.clock())
        with s.lock:
            self.prune(s.clock())
            if s.db.execute('SELECT 1 FROM lineup_alert_deleted WHERE id=?',(sid,)).fetchone(): raise ValueError('removed')
            old=s.db.execute('SELECT owner,body,expires FROM lineup_alerts WHERE id=?',(sid,)).fetchone()
            if old and old[0]!=owner: raise PermissionError()
            if not old and s.db.execute('SELECT COUNT(*) FROM lineup_alerts').fetchone()[0]>=8: raise OverflowError()
            if old and json.loads(old[1])['revision']>=body['revision']:
                return dict(registered=True,pushReady=s.push_ready(json.loads(old[1])['environment']),expiresAt=old[2])
            expires=s.clock()+LIFETIME
            s.db.execute('INSERT OR REPLACE INTO lineup_alerts VALUES (?,?,?,?)',(sid,owner,json.dumps(body),expires));s.db.commit()
        return dict(registered=True,pushReady=s.push_ready(body['environment']),expiresAt=expires)
    def delete(self,sid,owner):
        s=self.service
        with s.lock:
            old=s.db.execute('SELECT owner FROM lineup_alerts WHERE id=?',(sid,)).fetchone()
            if old and old[0]!=owner: raise PermissionError()
            s.db.execute('DELETE FROM lineup_alerts WHERE id=?',(sid,))
            s.db.execute('INSERT OR REPLACE INTO lineup_alert_deleted VALUES (?,?)',(sid,s.clock()+LIFETIME));s.db.commit()
    def read(self,season,league,week,kind,ttl):
        key=(season,league,week,kind); now=self.service.clock(); prior=self.cache.get(key)
        if prior and now-prior[0]<ttl:
            if prior[1] is None: raise ValueError('backoff')
            return prior[1]
        self.cache[key]=(now,None) # Failed requests also back off.
        if len(self.cache)>64: self.cache={key:(now,None)}
        if kind=='liveScoring' and hasattr(self.service.mfl,'read_with_receipt'):
            data,checked=self.service.mfl.read_with_receipt(season,league,week)
        else:
            data=self.service.mfl.read(season,league,week) if kind=='liveScoring' else self.service.mfl.export(season,league,week,kind)
            checked=self.service.clock()
        self.cache[key]=(checked,data);return data
    def tick(self):
        s=self.service; now=s.clock()
        with s.lock:
            self.prune(now);s.db.commit()
            if not s.apns.ready or now<self.next_check: return
            self.next_check=now+60
            rows=s.db.execute('SELECT id,body FROM lineup_alerts').fetchall()
        for sid,raw in rows:
            body=json.loads(raw)
            if not s.push_ready(body['environment']): continue
            try:
                args=(body['season'],body['leagueID'],body['week'])
                prior=self.cache.get((*args,'nflSchedule'))
                soon=prior and prior[1] and any(0<integer(g.get('kickoff'),1,32_503_680_000)-now<=5400 for g in array(prior[1].get('nflSchedule',{}).get('matchup')))
                schedule=self.read(*args,'nflSchedule',300 if soon else 3600)
                # Live scoring and injuries are read only in a pre-kickoff window.
                near=any(0<integer(g.get('kickoff'),1,32_503_680_000)-now<=1800 for g in array(schedule.get('nflSchedule',{}).get('matchup')))
                if not near: continue
                live=self.read(*args,'liveScoring',60)
                try: injuries=self.read(*args,'injuries',300) if body['options']['unavailable'] else {}
                except Exception: injuries={}
                events=candidates(body,live,schedule,injuries,s.clock())
                with s.lock:
                    current=s.db.execute('SELECT owner,body,expires FROM lineup_alerts WHERE id=?',(sid,)).fetchone()
                    if not current or current[1]!=raw or current[2]<=s.clock(): continue
                    fresh=[e for e in events if not s.db.execute('SELECT 1 FROM lineup_alert_sent WHERE owner=? AND id=?',(current[0],e[0])).fetchone()]
                    if not fresh: continue
                    # One useful banner; a warning supersedes a generic reminder.
                    warning=[e for e in fresh if '.reminder.' not in e[0]]
                    selected=warning or fresh
                    text=' '.join(e[1] for e in selected)[:800]
                    scope=f'{body["season"]}.{body["leagueID"]}.{body["franchiseID"]}'
                    destination=f'mflblitz://lineup?scope={scope}&id=lineup&week={body["week"]}'
                    data=json.dumps({'aps':{'alert':{'title':'MFL Blitz · Lineup','body':text},'sound':'default','thread-id':scope},'destination':destination},ensure_ascii=False).encode()
                    delivery=dict(body,deliveryExpiresAt=min(int(e[0].split('.')[4]) for e in fresh))
                    if delivery['deliveryExpiresAt']<=s.clock(): continue
                    result=s.apns.send(delivery,data,s.clock(),alert=True,collapse=hashlib.sha256((current[0]+fresh[0][0]).encode()).hexdigest())
                    if result==200:
                        for event,_ in fresh:
                            s.db.execute('INSERT OR REPLACE INTO lineup_alert_sent VALUES (?,?,?)',(current[0],event,now+LIFETIME))
                    elif result in (400,410): self.delete(sid,current[0])
                    s.db.commit()
            except Exception:
                continue # Never send a guess after a failed or malformed read.
