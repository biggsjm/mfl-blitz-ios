"""Read only the existing local NFL cache; no paid-provider credentials here."""
import json
import time
import unicodedata
import urllib.request


class NFLCache:
    def __init__(self):
        self.saved = {}
    def read(self, season, week, defense_teams=()):
        defense_teams=tuple(sorted(set(defense_teams)))
        key=(season,week,defense_teams); now=time.time()
        previous=self.saved.get(key)
        if previous and now-previous[0]<30:
            return previous[1]
        try:
            request=urllib.request.Request(f'http://127.0.0.1:8793/v1/seasons/{season}/weeks/{week}',headers={'X-Blitz-NFL':'1','X-Blitz-NFL-Defense':','.join(defense_teams)})
            with urllib.request.urlopen(request,timeout=3) as response:
                data=response.read(5_000_001)
            if len(data)>5_000_000:
                raise ValueError('size')
            value=json.loads(data)
            if value.get('schema')!=1 or value.get('season')!=season or value.get('week')!=week:
                raise ValueError('scope')
            self.saved={key:(now,value)}
            return value
        except Exception:
            self.saved={key:(now,None)}
            return None


def name(value):
    return ''.join(c for c in unicodedata.normalize('NFKD',value).casefold() if c.isalnum())


def enrich(state, subscription, document, now):
    state.pop('nextKickoff',None); state.pop('statContext',None)
    if not document:
        return
    profiles=subscription.get('playerProfiles',{})
    games=document.get('games',[])
    upcoming=[]
    for profile in profiles.values():
        for game in games:
            if profile['team'] in (game['home'],game['away']) and game['status']=='NS' and game['kickoff']>now and not game.get('stale',True):
                upcoming.append(game['kickoff'])
    if upcoming:
        state['nextKickoff']=min(upcoming)-978307200
    pid=(state.get('latestChange') or {}).get('playerID')
    profile=profiles.get(pid)
    if not profile:
        return
    defense=profile['position'] in ('DEF','DF','DST','D/ST')
    matches=[]
    for game in games:
        receipt=game.get('defenseCheckedAt' if defense else 'statsCheckedAt') or 0
        stale=game.get('defenseStale' if defense else 'statsStale',True)
        if profile['team'] not in (game['home'],game['away']) or stale or receipt>now:
            continue
        if game['status'] not in ('FT','AOT') and now-receipt>=(300 if defense else 150):
            continue
        for p in game.get('defenses' if defense else 'players',[]):
            same=p['team']==profile['team']
            if defense: same= same and p.get('position')=='DEF'
            else:
                if p.get('mflID') is not None:
                    identity=p['mflID']==pid and name(p.get('mflName') or '')==name(profile['name'])
                else:
                    identity=name(p['name'])==name(profile['name'])
                same=same and identity and (p.get('position') or '').replace('PK','K')==profile['position'].replace('PK','K')
            if same: matches.append(p)
    if len(matches)!=1:
        return
    parts=[]
    for group in matches[0]['groups']:
        values={s['name']:s['value'] for s in group['stats']}
        kind=group['name'].lower()
        if kind=='receiving':
            fields=[('total receptions','rec'),('yards','rec yd'),('receiving touch downs','rec TD')]
        elif kind=='rushing':
            fields=[('yards','rush yd'),('rushing touch downs','rush TD')]
        elif kind=='passing':
            fields=[('yards','pass yd'),('passing touch downs','pass TD'),('interceptions','INT')]
        elif kind=='fumbles': fields=[('lost','fumbles lost')]
        elif kind=='team defense': fields=[('SK','sacks'),('IC','INT'),('FC','recoveries'),('SF','safeties'),('#IR','INT TD'),('TPA','points allowed')]
        else: fields=[]
        for field,label in fields:
            value=values.get(field)
            if value is not None and (value!='0' or label.endswith('yd')):
                parts.append(f'{value} {label}')
    line=' · '.join(parts)
    if line and len(line)<=160:
        state['statContext']=line
