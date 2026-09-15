"""Reviewed cross-provider IDs. No fuzzy matching or upstream requests."""
import json
from pathlib import Path
import re


def load_table(path):
    document = json.loads(Path(path).read_text())
    if document.get('schema') != 1 or document.get('provider') != 'API-NFL':
        raise ValueError('player translation schema')
    entries = document['entries']
    if not isinstance(entries, list) or len(entries) > 5000:
        raise ValueError('player translation collection')
    provider_ids, mfl_ids = set(), set()
    for entry in entries:
        if (type(entry['season']) is not int or not 2020 <= entry['season'] <= 2100
                or type(entry['providerID']) is not int or not 0 < entry['providerID'] < 100_000_000
                or not re.fullmatch(r'[0-9]{1,12}', entry['mflID'])
                or any(not isinstance(entry[key], str) or not entry[key].strip() or len(entry[key]) > 200
                       for key in ('mflName', 'providerName', 'team', 'position', 'reviewedAt'))
                or not entry.get('evidence')):
            raise ValueError('player translation identity')
        provider_key = (entry['season'], entry['providerID'])
        mfl_key = (entry['season'], entry['mflID'])
        if provider_key in provider_ids or mfl_key in mfl_ids:
            raise ValueError('conflicting player translation')
        provider_ids.add(provider_key); mfl_ids.add(mfl_key)
    return {(entry['season'], entry['providerID']): entry for entry in entries}


TRANSLATIONS = load_table(Path(__file__).with_name('player_translations.json'))


def translated_fields(season, player, position):
    entry = TRANSLATIONS.get((season, player['providerID']))
    # Roster agreement is checked before this function. A changed name, team,
    # position or season needs review; never silently widen the assertion.
    if (entry and entry['providerName'] == player['name']
            and entry['team'] == player['team'] and entry['position'] == position):
        return {'mflID': entry['mflID'], 'mflName': entry['mflName']}
    return {}
