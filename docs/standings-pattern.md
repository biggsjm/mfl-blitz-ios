# Standings presentation pattern

Approved and implemented September 6, 2026 for **0.5.3 (26)**. [Current status](current-status.md) records test, GitHub and device delivery evidence separately from implementation and live-owner acceptance.

## Shared presentation

- My Team and other-team headers: one compact line, **6–2 · 1st in Warner**. Use the configured division name when assigned; otherwise **6–2 · 3rd in Champion Hall**, using the league name. Ordinals are numeric, not spelled out. Examples are illustrative, not current standings.
- Include game ties only when nonzero: **6–2–1 · 1st in Warner**.
- Division standings tables: rank within the displayed division, starting at 1. Overall tables: league-wide rank. Do not reuse overall rank numbers inside division sections.
- Before results exist: **0–0 · Warner**, without a manufactured first place. Determine this from confirmed season/results state, not merely a single team's zero record.
- Use **T-1st** only when every supported configured criterion compares equal, never merely because teams share a win–loss record. Tables use `T1`, `T2`, etc., with competition ranking (1, 1, 3). Keep game ties separate from ranking ties.
- `T2, T2, 4` requires evidence: for example, tied records with known equal points for the two second-place teams and lower points for the fourth, when points are the final applicable criterion. Missing points or an earlier unresolved H2H criterion must not create those places. The ranked Preview scenario uses explicit synthetic values; it is not Champion Hall's live preseason standing.
- Unavailable rank: retain known record and group; omit the rank. Keep longer explanations and freshness in Standings, not the team identity header.
- My Team and other-team details use the same summary. Tapping it opens Standings in the matching Division/Overall context and scrolls to that franchise, without changing the Lineup/Scores week or drafts. The scope selector remains above the scrolling table. No duplicate standing card or repeated division label.
- Division identity uses IDs, not names; same-name divisions do not merge. No division means no redundant scope selector. Unknown ranks display a dash and sort alphabetically for stable browsing, not fabricated places.
- VoiceOver identifies rank context, team, owner, record and points. At accessibility text sizes, team headers stack and standings rows put identity, record and points on separate lines instead of squeezing fixed columns.

## Rank source and supported rules

The earlier app incorrectly treated `leagueStandings.franchise` array position as rank. A September 6 **read-only authenticated request using the app's own session** returned Champion Hall franchises in ID order, with all records and points zero and no explicit rank field. No credential was extracted or live league data changed. Temporary diagnostic logging was removed before the final build; authenticated responses are not checked into this repository.

The public league configuration reports `PCT,H2H,PTS,DIVPCT,`, start week 1, regular-season end week 14, and division IDs 00/Faulk, 01/Warner and 02/Bruce. The [MFL API reference](https://api.myfantasyleague.com/2026/api_info?STATE=details) describes extra sorting fields via `ALL`, but does not guarantee rank from array order. [MFL's standings FAQ](https://www.myfantasyleague.com/2026/support?CATEGORY=Pools%20%26%20Reports&SUBCATEGORY=Standings) explains pairwise head-to-head comparisons, half-win ties, circular results, preliminary/adjusted records and commissioner custom orders. The [reports guide](https://php01.myfantasyleague.com/wp-new/reports/) also describes report customization and tiebreakers.

`MFLStandingsRanking` resolves each scope from the configured criterion sequence:

- `PCT`: exact win percentage from wins, losses and half-win game ties.
- `H2H`: pairwise confirmed W/L/T results, not a mini-league percentage or a winner inferred from rounded scores. Completed schedule weeks must reconcile exactly with each team's reported record.
- `PTS`: actual points for, including real zero or negative scores.
- `DIVPCT`: exact division record when supplied, otherwise a valid returned division percentage.

No results means no place. Points-only leagues use reported points/completion rather than requiring a win–loss record. Unsupported criteria, incomplete membership/numbers, unreconciled H2H history, and non-transitive/circular comparisons leave the affected scope unranked. Input order and franchise ID never determine rank.

**Limit:** MFL's standings report remains the final authority. Manual/custom orders not exposed in the used API fields are not mirrored. Preliminary, median-win or adjusted records can prevent completed-schedule H2H reconciliation; the app then omits place instead of guessing. This is not playoff seeding or certification of every MFL league format. After-results comparison with the signed-in league's actual report remains a Week 1 owner gate.

## Performance and verification

Standings reuse the 60-second response cache and league configuration's 24-hour memory cache. Only if tied earlier criteria require H2H does the repository consult season status and the shared 15-minute full-schedule cache. There is no per-team request fan-out, new polling or private disk cache. Mutations are unchanged.

Core fixtures cover criteria, real ties, score-tied games with authoritative W/L, H2H cycles/incomplete history, malformed division records, no results, points-only leagues and unsupported data. App fixtures cover numeric suffixes, missing summaries, same-name division IDs, separate scopes, incomplete membership and repeated-read cache reuse. Native Preview journeys cover header navigation, Divisions/Overall, ties, no divisions, maximum Dynamic Type and preserved drafts. Synthetic data is explicitly Preview-only; it does not certify real Week 1 results.

## Remaining acceptance

- [x] Approve and implement the shared numeric-ordinal pattern and context-aware navigation.
- [x] Verify the API array-order flaw through an authenticated read; replace index ranking with supported configured criteria.
- [x] Add conservative preseason/missing/tie handling, cache reuse and model/native regressions.
- [ ] Compare completed Week 1 division/overall places and tiebreakers with MFL, including any commissioner custom order.
- [ ] Complete broader device/manual assistive-technology checks and Week 2 release gates in the [roadmap](roadmap.md).

Final test, install and merge receipts belong in [current status](current-status.md); checked implementation items do not substitute for those receipts.
