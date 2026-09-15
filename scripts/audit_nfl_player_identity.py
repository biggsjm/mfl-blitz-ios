#!/usr/bin/env python3
"""Audit saved MFL exports against an NFL cache dump. No network or table edits.

Cache format: {cacheKey: {value: decodedJSON, fetched: unixSeconds}}.
Suggestions are review leads only; they never attach stats or create mappings.
"""
import argparse
from collections import Counter
from difflib import SequenceMatcher
import json
from pathlib import Path
import sys
import unicodedata

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'services/nfl_live'))
from player_identity import translated_fields


def name(value):
    return ''.join(c for c in unicodedata.normalize('NFKD', value).casefold() if c.isalnum())


def array(value):
    return value if isinstance(value, list) else [value] if isinstance(value, dict) else []


def audit(cache, catalog, rosters, scores, week):
    owned = {p['id'] for f in array(rosters['rosters'].get('franchise')) for p in array(f.get('player'))}
    live = {p['id']: p for m in array(scores['liveScoring'].get('matchup'))
            for f in array(m.get('franchise')) for p in array(f.get('players', {}).get('player'))}
    owned.update(live)
    games = [g for g in cache['games']['value'] if g['week'] == week]
    rows = []
    for mfl in catalog['players']['player']:
        if mfl['id'] not in owned:
            continue
        label = ' '.join(s.strip() for s in reversed(mfl['name'].split(',', 1)))
        position = 'K' if mfl['position'] == 'PK' else mfl['position']
        candidates = [g for g in games if mfl['team'] in (g['home'], g['away'])]
        game = candidates[0] if len(candidates) == 1 else None
        box = cache.get('box-' + str(game['id'])) if game else None
        result = 'no unique game' if not game else 'upcoming' if game['status'] == 'NS' else 'no cached box' if not box else 'no matched stats'
        matches, suggestions = [], []
        if box:
            for player in box['value']['players']:
                if player['team'] != mfl['team']:
                    continue
                tid = game['homeID'] if player['team'] == game['home'] else game['awayID']
                profile = cache.get('roster-' + str(tid), {}).get('value', {}).get(str(player['providerID']))
                provider_position = profile['position'] if profile and profile['name'] == player['name'] else None
                fields = translated_fields(game['season'], player, provider_position)
                identity = (fields['mflID'] == mfl['id'] and name(fields['mflName']) == name(label)) if fields else name(player['name']) == name(label)
                if identity and provider_position == position:
                    matches.append((player, bool(fields)))
                if (provider_position == position and
                        (SequenceMatcher(None, name(label), name(player['name'])).ratio() > .7
                         or name(label.split()[-1]) in name(player['name']))):
                    suggestions.append(dict(providerID=player['providerID'], name=player['name']))
            if len(matches) == 1:
                result = 'translated' if matches[0][1] else 'exact'
            elif len(matches) > 1:
                result = 'ambiguous'
        points = live.get(mfl['id'], {}).get('score')
        issue = result not in ('exact', 'translated', 'upcoming') and float(points or 0) != 0
        rows.append(dict(mflID=mfl['id'], name=label, team=mfl['team'], position=position,
                         points=points, result=result, needsReview=issue,
                         candidates=suggestions if result not in ('exact', 'translated') else []))
    return dict(week=week, counts=dict(Counter(r['result'] for r in rows)),
                needsReview=sum(r['needsReview'] for r in rows), players=rows)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('cache', 'catalog', 'rosters', 'scores'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--week', type=int, required=True, choices=range(1, 19))
    parser.add_argument('--strict', action='store_true', help='Exit 1 when a scored player has no unique stat match.')
    args = parser.parse_args()
    report = audit(*(json.loads(getattr(args, key).read_text()) for key in ('cache', 'catalog', 'rosters', 'scores')), args.week)
    print(json.dumps(report, indent=2))
    sys.exit(1 if args.strict and report['needsReview'] else 0)
