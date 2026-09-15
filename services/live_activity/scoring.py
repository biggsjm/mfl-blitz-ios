"""MFL-only Live Activity content. Never infer a play or treat missing data as zero."""
from copy import deepcopy
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import json
import re

APPLE_EPOCH = 978307200
STALE_AFTER = 210


def array(value):
    if isinstance(value, list):
        return value
    return [value] if isinstance(value, dict) else []


def number(value):
    if isinstance(value, bool) or value is None:
        raise ValueError('missing number')
    if isinstance(value, str) and re.fullmatch(r'-?[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?', value):
        value = value.replace(',', '')
    try:
        result = Decimal(str(value))
        if not result.is_finite() or abs(result) > 1000000000000000:
            raise ValueError('invalid number')
        return result
    except InvalidOperation:
        raise ValueError('invalid number') from None


def integer(value, minimum=0, maximum=100000):
    result = number(value)
    if result != int(result) or not minimum <= result <= maximum:
        raise ValueError('invalid integer')
    return int(result)


def ticks(value, precision):
    return number(value).quantize(Decimal(10) ** -precision, rounding=ROUND_HALF_UP)


def score(value, precision):
    result = ticks(value, precision)
    return format(abs(result) if result == 0 else result, f'.{precision}f')


def read_matchup(document, subscription):
    live = document.get('liveScoring', {})
    if integer(live.get('week'), 1, 21) != subscription['week']:
        raise ValueError('wrong week')
    ids = {subscription['homeID'], subscription['awayID']}
    matches = [m for m in array(live.get('matchup'))
               if {f.get('id') for f in array(m.get('franchise'))} == ids
               and len(array(m.get('franchise'))) == 2]
    if len(matches) != 1:
        raise ValueError('ambiguous matchup')
    teams = {}
    for f in array(matches[0]['franchise']):
        total = number(f.get('score'))
        players = array(f.get('players', {}).get('player'))
        starters = {}
        unknown = False
        clocks = []
        player_clocks = {}
        seen = set()
        for p in players:
            pid = p.get('id')
            if not isinstance(pid, str) or pid in seen:
                raise ValueError('duplicate player')
            seen.add(pid)
            status = str(p.get('status', '')).lower()
            if status not in ('starter', 'nonstarter'):
                unknown = True
            if status != 'starter':
                continue
            pid = p.get('id')
            if not isinstance(pid, str) or pid in starters:
                raise ValueError('duplicate starter')
            try:
                points = str(number(p.get('score')))
            except ValueError:
                points = None
            starters[pid] = points
            try:
                clocks.append(integer(p.get('gameSecondsRemaining'), 0, 3600))
            except ValueError:
                clocks.append(None)
            player_clocks[pid] = clocks[-1]
        # Use positively reported starter clocks, matching the native app.
        active = sum(c is not None and 0 < c < 3600 for c in clocks)
        final = bool(clocks) and all(c == 0 for c in clocks) and not unknown
        for key in ('playersYetToPlay', 'playersCurrentlyPlaying', 'gameSecondsRemaining'):
            if key in f:
                try:
                    final = final and integer(f[key]) == 0
                except ValueError:
                    final = False
        side = 'home' if f['id'] == subscription['homeID'] else 'away'
        expected = subscription.get(side + 'StarterIDs')
        if expected is not None and set(expected) != set(starters):
            final = False
        try:
            remaining = integer(f.get('playersYetToPlay'), 0, 100) + integer(f.get('playersCurrentlyPlaying'), 0, 100)
        except ValueError:
            remaining = None
        teams[f['id']] = dict(score=str(total), starters=starters, unknown=unknown,
                              clocks=player_clocks, remaining=remaining, active=active, final=final)
    return teams


def projection(team, subscription, side):
    clocks = team['clocks']
    expected = subscription.get(side + 'StarterIDs')
    if (not clocks or team['unknown'] or expected is None or set(expected) != set(clocks)
            or any(c is None for c in clocks.values())
            or team['remaining'] != sum(c > 0 for c in clocks.values())):
        return None
    total = number(team['score'])
    projections = subscription.get('starterProjections', {})
    for pid, seconds in clocks.items():
        if seconds == 0:
            continue
        if pid not in projections:
            return None
        total += number(projections[pid]) * seconds / 3600
    return score(total, subscription['precision'])


def change(old, new, precision, abbreviation, names):
    delta = ticks(new['score'], precision) - ticks(old['score'], precision)
    if not delta:
        return None
    amount = ('+' if delta > 0 else '−') + score(abs(delta), precision) + ' pts'
    summary = f'{abbreviation} {amount}'
    before, after = old['starters'], new['starters']
    if (not after or before.keys() != after.keys() or old['unknown'] or new['unknown']
            or any(v is None for v in [*before.values(), *after.values()])):
        return summary, summary, None
    changed = [(pid, ticks(value, precision) - ticks(before[pid], precision))
               for pid, value in after.items() if ticks(value, precision) != ticks(before[pid], precision)]
    if not changed or sum(d for _, d in changed) != delta:
        return summary, summary, None
    subject = names.get(changed[0][0]) if len(changed) == 1 else f'{len(changed)} starters'
    return (f'{subject} {amount} · {abbreviation}' if subject else summary), summary, (changed[0][0] if len(changed)==1 else None)


def updated_state(subscription, teams, now):
    state = deepcopy(subscription['state'])
    previous = subscription.get('baseline')
    previous_at = subscription.get('baselineAt', 0)
    changes = []
    if previous and 0 < now - previous_at < STALE_AFTER:
        for side in ('away', 'home'):
            tid = subscription[side + 'ID']
            value = change(previous[tid], teams[tid], subscription['precision'],
                           subscription[side + 'Abbreviation'], subscription['playerNames'])
            if value:
                changes.append(value)
        if changes:
            state['latestChange'] = {'text': changes[0][0] if len(changes) == 1 else ' · '.join(c[1] for c in changes),
                                     'checkedAt': now - APPLE_EPOCH}
            if len(changes)==1 and changes[0][2]:
                state['latestChange']['playerID']=changes[0][2]
    else:
        state.pop('latestChange', None)
    for side in ('home', 'away'):
        team = teams[subscription[side + 'ID']]
        state[side + 'Score'] = score(team['score'], subscription['precision'])
        state.pop(side + 'Record', None)
        clocks=team['clocks']
        if clocks and not team['unknown'] and all(c is not None for c in clocks.values()) and team['remaining']==sum(c>0 for c in clocks.values()):
            state[side+'Playing']=sum(0<c<3600 for c in clocks.values())
            state[side+'YetToPlay']=sum(c==3600 for c in clocks.values())
        else:
            state.pop(side+'Playing',None); state.pop(side+'YetToPlay',None)
        estimate = projection(team, subscription, side)
        if estimate is None:
            state.pop(side + 'Projection', None)
        else:
            state[side + 'Projection'] = estimate
    state['activePlayers'] = sum(t['active'] for t in teams.values())
    state['updatedAt'] = now - APPLE_EPOCH
    # A single transient all-zero/partial feed must not remove the activity.
    final = (all(t['final'] for t in teams.values()) and previous
             and 60 <= now - previous_at < STALE_AFTER
             and all(previous.get(tid, {}).get('final')
                     and previous[tid]['starters'].keys() == team['starters'].keys()
                     for tid, team in teams.items()))
    state['phase'] = 'final' if final else ('live' if state['activePlayers'] else 'waiting')
    if final:
        state.pop('homeProjection', None); state.pop('awayProjection', None)
    return state


def payload(state, now, final=False, attribute_bytes=1024):
    # ContentState Date fields use Swift's default Codable reference date;
    # the APNs envelope uses Unix time. Both are verified in native/server tests.
    value = {'aps': {'timestamp': int(now), 'event': 'end' if final else 'update',
                     'content-state': deepcopy(state), 'stale-date': int(now + STALE_AFTER)}}
    if final:
        value['aps'].pop('stale-date')
        value['aps']['dismissal-date'] = int(now + 900)
    def encode():
        return json.dumps(value, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode()
    state_bytes = len(json.dumps(state, separators=(',', ':'), ensure_ascii=False).encode())
    if len(encode()) > 4000 or state_bytes + attribute_bytes > 3900:
        for side in ('homeArtwork', 'awayArtwork'):
            if value['aps']['content-state'].get(side):
                value['aps']['content-state'][side].pop('thumbnail', None)
    data = encode()
    if len(data) > 4096:
        raise ValueError('push too large')
    return data


def validate_subscription(value, now, allowed_leagues):
    """Allowlist fields: never persist arbitrary request data, URLs or credentials."""
    def text(key, pattern, maximum):
        v = value.get(key)
        if not isinstance(v, str) or len(v) > maximum or not re.fullmatch(pattern, v):
            raise ValueError('invalid ' + key)
        return v
    season = integer(value.get('season'), 2020, 2100)
    league = text('leagueID', r'[0-9]{5}', 5)
    if f'{season}.{league}' not in allowed_leagues:
        raise ValueError('league not enabled')
    result = dict(season=season, leagueID=league, week=integer(value.get('week'), 1, 21),
                  precision=integer(value.get('precision'), 0, 4), revision=integer(value.get('revision'), 1, 10**15),
                  homeID=text('homeID', r'[0-9]{4}', 4), awayID=text('awayID', r'[0-9]{4}', 4),
                  token=text('token', r'[0-9a-f]{64,512}', 512),
                  environment=text('environment', r'sandbox|production', 10))
    if result['homeID'] == result['awayID']:
        raise ValueError('duplicate teams')
    for side in ('home', 'away'):
        result[side + 'Abbreviation'] = text(side + 'Abbreviation', r'[^\x00-\x1f]{1,5}', 5)
    names = value.get('playerNames', {})
    if not isinstance(names, dict) or len(names) > 100:
        raise ValueError('invalid names')
    result['attributeBytes'] = integer(value.get('attributeBytes', 1024), 1, 2048)
    result['playerNames'] = {k: v for k, v in names.items() if isinstance(k, str) and re.fullmatch(r'[0-9]{1,8}', k)
                             and isinstance(v, str) and 0 < len(v) <= 48 and not any(ord(c) < 32 for c in v)}
    result['playerProfiles']={}
    profiles=value.get('playerProfiles',{})
    if not isinstance(profiles,dict) or len(profiles)>100:
        raise ValueError('invalid profiles')
    for pid,profile in profiles.items():
        if pid not in result['playerNames'] or not isinstance(profile,dict):
            raise ValueError('invalid profile identity')
        team=profile.get('team'); position=profile.get('position')
        if not isinstance(team,str) or not re.fullmatch(r'[A-Z]{2,3}',team) or not isinstance(position,str) or not re.fullmatch(r'[A-Z/]{1,5}',position):
            raise ValueError('invalid profile')
        result['playerProfiles'][pid]=dict(name=result['playerNames'][pid],team=team,position=position)
    for side in ('home', 'away'):
        key = side + 'StarterIDs'
        if key in value:
            ids = value[key]
            if (not isinstance(ids, list) or not 1 <= len(ids) <= 50
                    or any(not isinstance(pid, str) or not re.fullmatch(r'[0-9]{1,8}', pid) for pid in ids)
                    or len(set(ids)) != len(ids)):
                raise ValueError('invalid starter IDs')
            result[key] = sorted(ids)
    projections = value.get('starterProjections', {})
    if not isinstance(projections, dict) or len(projections) > 100:
        raise ValueError('invalid projections')
    result['starterProjections'] = {}
    for pid, estimate in projections.items():
        if not isinstance(pid, str) or not re.fullmatch(r'[0-9]{1,8}', pid):
            raise ValueError('invalid projection player')
        result['starterProjections'][pid] = str(number(estimate))
    source = value.get('state', {})
    checked = float(number(source.get('updatedAt'))) + APPLE_EPOCH
    if not 0 <= now - checked < STALE_AFTER:
        raise ValueError('stale registration')
    state = {'homeScore': score(source.get('homeScore'), result['precision']),
             'awayScore': score(source.get('awayScore'), result['precision']),
             'activePlayers': integer(source.get('activePlayers'), 0, 100), 'updatedAt': checked - APPLE_EPOCH}
    for side in ('home', 'away'):
        estimate = source.get(side + 'Projection')
        if estimate is not None:
            state[side + 'Projection'] = score(estimate, result['precision'])
        art = source.get(side + 'Artwork')
        if isinstance(art, dict):
            color = {c: float(number(art.get(c))) for c in ('red', 'green', 'blue')}
            if not all(0 <= c <= 1 for c in color.values()):
                raise ValueError('invalid color')
            thumbnail = art.get('thumbnail')
            if isinstance(thumbnail, str) and re.fullmatch(r'[A-Za-z0-9_=-]{0,1200}', thumbnail):
                color['thumbnail'] = thumbnail
            state[side + 'Artwork'] = color
    latest = source.get('latestChange')
    if isinstance(latest, dict) and isinstance(latest.get('text'), str) and len(latest['text']) <= 180:
        at = float(number(latest.get('checkedAt')))
        if 0 <= checked - (at + APPLE_EPOCH) < 8 * 3600:
            state['latestChange'] = {'text': latest['text'], 'checkedAt': at}
            if latest.get('playerID') in result['playerNames']:
                state['latestChange']['playerID']=latest['playerID']
    for side in ('home','away'):
        for suffix in ('Playing','YetToPlay'):
            if source.get(side+suffix) is not None:
                state[side+suffix]=integer(source[side+suffix],0,100)
    if source.get('nextKickoff') is not None:
        kickoff=float(number(source['nextKickoff']))
        if now < kickoff+APPLE_EPOCH < now+7*86400:
            state['nextKickoff']=kickoff
    if isinstance(source.get('statContext'),str) and len(source['statContext'])<=160:
        state['statContext']=source['statContext']
    result['state'] = state
    payload(state, now, attribute_bytes=result['attributeBytes'])
    return result
