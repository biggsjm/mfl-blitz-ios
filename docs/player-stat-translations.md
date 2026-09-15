# Player stat identity translations

Build 58 addresses a real missing-stat case: MFL player **17045, Cam Skattebo**, is API-NFL player **31107, Cameron Skattebo**. His cached Week 1 box contained 18 carries, 81 rushing yards and one rushing touchdown; exact name matching hid it. The league awards 8 yardage points plus 6 touchdown points, matching MFL's 14.0. This is a lookup correction, not a score change or an extra provider fetch.

## One reviewed table

[`player_translations.json`](../services/nfl_live/player_translations.json) is the single versioned translation table on the NFL cache service. Each entry binds the season, MFL ID/name, provider ID/name, NFL team and position, with a review date and evidence. Both IDs must be unique within a season; duplicate entries fail validation before deployment. Source names and stats remain untouched.

The cache only emits optional `mflID` / `mflName` fields when the box and same-ID roster agree and every table guard matches. The app and background Live Activity use those fields with the actual MFL ID, name, team, position and unique-candidate checks. Players without a translation retain exact normalized name/team/position matching. There is no blanket nickname expansion, suffix stripping, or fuzzy acceptance. Existing clients ignore the optional fields; build 58 is needed once to consume them. Later table updates only need the NFL service deployment.

If a player changes teams, position, displayed name or season, review the assertion again. Unknown or conflicting identities stay unavailable. The historical DEBUG mapping tool remains separate; its saved reviews do not become production mappings.

## September 14, 2026 audit

Compared all **220 Week 1 league roster players**, including the 215 present in MFL's live-scoring export, against the already-saved NFL boxes and rosters:

| Result | Players |
| --- | ---: |
| Exact matches | 171 |
| Reviewed translations | 14 |
| Upcoming games | 14 |
| No matched provider stat record and no listed nonzero MFL points | 21 |

All **172 players with nonzero MFL points** have a unique stat match after translation. This is coverage of the saved Week 1 data, not a claim that every future game/player has complete provider statistics. Absence of a stat record does not prove a player was inactive or had no snaps.

| MFL name / ID | API-NFL name / ID |
| --- | --- |
| Cam Skattebo / 17045 | Cameron Skattebo / 31107 |
| Cam Ward / 17030 | Cameron Ward / 25074 |
| Chris Brooks / 16387 | Christopher Brooks / 17539 |
| Woody Marks / 17053 | Jo'quavious Marks / 23362 |
| Jacory Croskey-Merritt / 17256 | Jacory Merritt / 27317 |
| KC Concepcion / 17501 | Kevin Concepcion / 39201 |
| Michael Pittman / 14842 | Michael Pittman Jr. / 1501 |
| Travis Etienne / 15253 | Travis Etienne Jr. / 72 |
| Brian Robinson / 15716 | Brian Robinson Jr. / 1265 |
| Chris Rodriguez / 16174 | Chris Rodriguez Jr. / 16716 |
| Luther Burden / 17070 | Luther Burden III / 11503 |
| Oronde Gadsden / 17099 | Oronde Gadsden II / 24639 |
| Harold Fannin / 17103 | Harold Fannin Jr. / 19667 |
| Mike Washington Jr. / 17482 | Mike Washington / 18106 |

Evidence comes from the public [MFL catalog](https://api.myfantasyleague.com/2026/export?TYPE=players&JSON=1) and locally cached same-ID API-NFL box/profile pairs. Nickname evidence is also recorded in the table: [Sacramento State's Cameron Skattebo bio](https://hornetsports.com/sports/football/roster/cameron-skattebo/7450), [Giants' Cam Skattebo bio](https://www.giants.com/team/players-roster/cam-skattebo/), [Titans' Cam/Cameron Ward bio](https://www.tennesseetitans.com/team/players-roster/cam-ward/career), [Texans' Woody/Jo'Quavious Marks bio](https://www.houstontexans.com/team/players-roster/woody-marks/), [BYU's Chris/Christopher Brooks page](https://byucougars.com/running-backs), [Alabama State's Jacory Merritt bio](https://bamastatesports.com/sports/football/roster/jacory-merritt/5698), and [NC State's Kevin Concepcion signing roster](https://gopack.com/news/2022/12/20/football-pack23-signing-day-central).

## Reviewing future gaps

Run `scripts/audit_nfl_player_identity.py` against saved exports. It performs no network requests and never edits the table. It reports unmatched players, highlights nonzero fantasy scores that lack a unique stat match, and lists similar same-team/position names only as review leads. Brian and Bijan Robinson, for example, can both be suggestions; neither is accepted by similarity.

```sh
python3 scripts/audit_nfl_player_identity.py \
  --cache /tmp/nfl-cache.json \
  --catalog /tmp/mfl-players.json \
  --rosters /tmp/mfl-rosters.json \
  --scores /tmp/mfl-scores.json \
  --week 1 --strict > /tmp/player-identity-audit.json
```

The cache dump shape is `{key: {value: decodedJSON, fetched: unixSeconds}}`, exported from `cache.sqlite3` for `games`, `box-*` and `roster-*`. MFL inputs are the unchanged JSON export envelopes for `players`, `rosters` and `liveScoring&DETAILS=1` from the same season/week. `--strict` exits 1 when scored players still need review. The current audit uses final boxes; its identity report does not replace runtime freshness checks.

For each gap, compare both IDs and roster/box data, verify the identity, and record the expected names/team/position and evidence. Run `python3 -m unittest discover -s services/nfl_live -p 'test_*.py'`, rerun the audit, then deploy using `scripts/deploy_nfl_live.sh`. No automatic recurring audit was scheduled.

Live-only polling, final correction reads, receipt timestamps and the shared 6,000/day hard cap remain unchanged. Matching reads existing data and makes **zero additional paid requests**.
