"""API-NFL normalization. No fantasy points and no guessed player identity."""
import math
import re

TEAMS = dict(zip([
    'Arizona Cardinals','Atlanta Falcons','Baltimore Ravens','Buffalo Bills','Carolina Panthers',
    'Chicago Bears','Cincinnati Bengals','Cleveland Browns','Dallas Cowboys','Denver Broncos',
    'Detroit Lions','Green Bay Packers','Houston Texans','Indianapolis Colts','Jacksonville Jaguars',
    'Kansas City Chiefs','Las Vegas Raiders','Los Angeles Chargers','Los Angeles Rams','Miami Dolphins',
    'Minnesota Vikings','New England Patriots','New Orleans Saints','New York Giants','New York Jets',
    'Philadelphia Eagles','Pittsburgh Steelers','San Francisco 49ers','Seattle Seahawks','Tampa Bay Buccaneers',
    'Tennessee Titans','Washington Commanders'],
    'ARI ATL BAL BUF CAR CHI CIN CLE DAL DEN DET GBP HOU IND JAC KCC LVR LAC LAR MIA MIN NEP NOS NYG NYJ PHI PIT SFO SEA TBB TEN WAS'.split()))
LIVE = {'Q1', 'Q2', 'Q3', 'Q4', 'HT', 'OT', 'BT'}
FINAL = {'FT', 'AOT'}


def text(value):
    if not isinstance(value, str) or not value.strip() or len(value) > 200:
        raise ValueError('label')
    return value.strip()


def number(value):
    if value is None:
        return None
    if type(value) not in (float, int) or not math.isfinite(value):
        raise ValueError('number')
    return value


def ident(value):
    if type(value) is not int or not 0 < value < 100_000_000:
        raise ValueError('id')
    return value


def items(value, limit=1000):
    if not isinstance(value, list) or len(value) > limit:
        raise ValueError('collection')
    return value


def games(rows, season):
    result, seen = [], set()
    for row in items(rows):
        if row['league']['id'] != 1 or str(row['league']['season']) != str(season):
            raise ValueError('season')
        g = row['game']
        # Preseason and unresolved postseason fixtures cannot poison a regular-season feed.
        if g['stage'] != 'Regular Season':
            continue
        week = re.fullmatch(r'Week ([1-9]|1[0-8])', text(g['week']))
        if not week:
            raise ValueError('week')
        gid = ident(g['id'])
        if gid in seen:
            raise ValueError('duplicate game')
        seen.add(gid)
        home, away = row['teams']['home'], row['teams']['away']
        h, a = TEAMS.get(home.get('name')), TEAMS.get(away.get('name'))
        if not h or not a or h == a or ident(home['id']) == ident(away['id']):
            raise ValueError('team')
        status = g['status'].get('short')
        if status is None and g['status'].get('long') == 'Final/OT':
            status = 'AOT'
        status = text(status or 'UNKNOWN')
        timer = g['status'].get('timer')
        timer = timer if isinstance(timer, str) and re.fullmatch(r'\d{1,2}:\d{2}', timer) else None
        kickoff = number(g['date']['timestamp'])
        if kickoff is None:
            raise ValueError('kickoff')
        result.append(dict(id=gid, season=season, week=int(week[1]), kickoff=kickoff, status=status,
                           timer=timer, home=h, away=a, homeID=home['id'], awayID=away['id'],
                           homeScore=number(row['scores']['home']['total']),
                           awayScore=number(row['scores']['away']['total'])))
    if not result:
        raise ValueError('empty schedule')
    return result


def profiles(rows):
    result = {}
    for row in items(rows, 300):
        pid = ident(row['id'])
        if str(pid) in result:
            raise ValueError('duplicate profile')
        result[str(pid)] = dict(name=text(row['name']), position=text(row['position']) if row.get('position') else None)
    return result


def defenses(rows, game):
    """Only explicitly supplied team totals; no sums of individual defenders."""
    result=[]; seen=set()
    teams={game['homeID']:game['home'],game['awayID']:game['away']}
    fields={'interceptions':'IC','fumbles_recovered':'FC','sacks':'SK','safeties':'SF','int_touchdowns':'#IR'}
    for row in items(rows,2):
        tid=ident(row['team']['id'])
        if tid not in teams or tid in seen:
            raise ValueError('defense team')
        seen.add(tid); stats=row['statistics']; values=[]
        for field,code in fields.items():
            value=number((stats.get(field) or {}).get('total'))
            if value is not None and value>=0:
                values.append(dict(name=code,value=str(value)))
        points=number((stats.get('points_against') or {}).get('total'))
        opponent_score=game['awayScore'] if tid==game['homeID'] else game['homeScore']
        # MFL TPA explicitly means the full NFL scoreboard total. Other MFL
        # offense/special-teams exclusions are distinct rules and stay missing.
        if points is not None and points==opponent_score:
            values.append(dict(name='TPA',value=str(points)))
        result.append(dict(providerID=tid,name=text(row['team']['name']),team=teams[tid],position='DEF',
            groups=[dict(name='Team defense',stats=values)]))
    if len(seen)!=2:
        raise ValueError('incomplete defense totals')
    return result


def players(rows, game):
    result, teams_seen = {}, set()
    teams = {game['homeID']: game['home'], game['awayID']: game['away']}
    for row in items(rows, 2):
        tid = ident(row['team']['id'])
        if tid not in teams or tid in teams_seen:
            raise ValueError('team')
        teams_seen.add(tid)
        for group in items(row['groups'], 30):
            group_name = text(group['name'])
            for entry in items(group['players'], 150):
                pid, name = ident(entry['player']['id']), text(entry['player']['name'])
                player = result.setdefault(pid, dict(providerID=pid, name=name, team=teams[tid], groups=[]))
                if player['name'] != name or player['team'] != teams[tid] or group_name in [g['name'] for g in player['groups']]:
                    raise ValueError('identity')
                stats, names = [], set()
                for stat in items(entry['statistics'], 60):
                    label, value = text(stat['name']), stat['value']
                    if label in names:
                        raise ValueError('duplicate stat')
                    names.add(label)
                    if type(value) in (float, int):
                        value = str(number(value))
                    if value is not None:
                        if not isinstance(value, str) or len(value) > 100:
                            raise ValueError('stat')
                        value = value.strip() or None
                    stats.append(dict(name=label, value=value))
                player['groups'].append(dict(name=group_name, stats=stats))
    return list(result.values())
