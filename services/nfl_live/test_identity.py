import json
from pathlib import Path
import tempfile
import unittest
from player_identity import TRANSLATIONS, load_table, translated_fields


class IdentityTests(unittest.TestCase):
    def test_reviewed_pairs_require_id_name_team_position_and_season(self):
        self.assertEqual(len(TRANSLATIONS), 14)
        for entry in TRANSLATIONS.values():
            player = dict(providerID=entry['providerID'], name=entry['providerName'], team=entry['team'])
            expected = dict(mflID=entry['mflID'], mflName=entry['mflName'])
            with self.subTest(player=entry['mflName']):
                self.assertEqual(translated_fields(2026, player, entry['position']), expected)
                for field, value in [('providerID', 99999999), ('name', 'Someone Else'), ('team', 'FA')]:
                    self.assertEqual(translated_fields(2026, dict(player, **{field: value}), entry['position']), {})
                self.assertEqual(translated_fields(2025, player, entry['position']), {})
                self.assertEqual(translated_fields(2026, player, None), {})
                self.assertEqual(translated_fields(2026, player, 'UNKNOWN'), {})

    def test_conflicting_ids_fail_validation_instead_of_last_entry_winning(self):
        entry = dict(next(iter(TRANSLATIONS.values())))
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'table.json'
            for conflicting in [dict(entry, mflID='99999'), dict(entry, providerID=99999999)]:
                path.write_text(json.dumps(dict(schema=1, provider='API-NFL', entries=[entry, conflicting])))
                with self.assertRaises(ValueError):
                    load_table(path)
