# Execution plan and remaining work

Updated September 6, 2026 against **0.3.7 (16), `e779e4b`**. Checked items mean implemented, not universal live-league certification. [Current status](current-status.md) records evidence; [the changelog](../CHANGELOG.md) records release history. Earlier “read-only TestFlight” milestone headings are superseded: native write workflows exist, but distribution is still pending.

## Completed baseline

- [x] Native Scores / Lineup / Transactions / Standings / Board and safe interactive preview.
- [x] Account/franchise mapping, validated host discovery, Keychain restore, expiry UI, bounded reconnect and independent tab loading.
- [x] Foreground live scores, positional matchup drill-down/FLEX, pregame projections and official completed results.
- [x] League-derived lineup limits, bench/starter/FLEX replacements and rotations, scoped drafts, modal review and starter-set verification.
- [x] Conditional blind-bid queues, confirmed $0 league fallback, fresh preflight, round replacement/cancellation and partial-outcome recovery.
- [x] Native trades and separate counteroffers, durable unconfirmed-action protection, prominent Create/Resume, draft cancel/rollback and correct first-tap response reviews.
- [x] Official standings/owner names, safe team artwork, native board threads/replies and exact-post verification.
- [x] Daily public player disk cache, stable league memory cache, decoded reuse, request sharing/spacing/cooldowns and no blind write retries.
- [x] Original icons, explicit Week N controls, adaptive layouts and accessibility foundations.
- [x] Performance regressions, four synthetic managers across two accelerated weeks and native UI journeys; private build installed on the owner's phone.
- [x] Coordinated schedule/player/team design documents. This completes design documentation only, not implementation.

## P0 — Week 1 validation and Week 2 release gates

Josh wants to test personally in Week 1 and invite the league in Week 2 if it goes well. Each gate below remains open until its evidence is recorded. A calendar date or passing fixtures is not enough.

| Remaining gate | Owner / action | Done when |
| --- | --- | --- |
| Live scoring and rollover | Josh, with developer triage | Week 1 totals, player points/FLEX, clocks, final corrections, offline recovery and Week 2 selection match MFL; record build/time/result in the [checklist](week-1-testing.md) |
| Real write verification | Josh + consenting league/test owner | Intended lineup, $0/conditional queue and processing, trade proposal/each response, and board thread/reply match MFL; ambiguous outcomes cause no duplicate writes |
| Regression and usability | Developer + owner | Full core/app/UI suites green on candidate; small-screen/iPad, light/dark, large text, VoiceOver, Voice Control/Switch Control, contrast and deadline flows reviewed; release blockers resolved |
| MFL client identity | Repository owner / developer | Registration confirmed and exact approved User-Agent configured; current `MFL Blitz/0.1 (com.biggsjm.MFLBlitz)` must not be assumed registered |
| Apple distribution | Apple account owner / developer | App Store Connect/TestFlight record, signing/archive, beta metadata, privacy/support details, applicable compliance/review requirements and tester access verified; clean install/update tested |
| Support and security | Repository owner | Private reporting route established and documented; GitHub private vulnerability reporting was disabled at the September 6 audit |
| Invite decision | Josh | Above gates passed for the advertised scope, known limits communicated, and MFL fallback/support available |

Josh has reported a successful lineup submission and seeing projections. These observations do not close the entire write or game-week gate. No production registration, TestFlight approval or completed live Week 1 validation is recorded.

Keep unvalidated navigation changes separate from a deadline-critical release. The following designs need their own implementation and regression pass.

## P1 — My Team, schedule and player detail

**Design direction agreed; implementation not started.** Proposed tabs: **Scores / Lineup / My Team / Standings / Board**. My Team replaces only Transactions. No Players tab and no new global search destination; reuse the existing available-player search in Transactions → Waivers.

1. [ ] Implement canonical-ID routes and the shared read-only team shell. My Team exposes Transactions above Roster / Schedule; dedicated Lineup retains editing/submission. Other-team pages never present the owner's inbox as their own. Carry the existing trade-specific badge onto My Team and its Transactions entry.
2. [ ] Add team roster and truthful initial player detail: identity, authoritative ownership/status, available projection/current points and optional supplied bio/contracts. Keep identity taps separate from lineup/waiver/asset-selection actions. See [player-detail plan](player-detail-ux.md).
3. [ ] Validate the official schedule request/schema; add a shared season/league cache and team/league timelines. Use configured week bounds, distinguishing byes, TBD, missing data and multiple matchups. See [schedule plan](schedule-ux.md).
4. [ ] Validate player-scoring history and add progressive, cached season/week history. Do not issue 18 forced full-week reads on first open or substitute zero for missing data.
5. [ ] Integrate contextual links and test back/scroll/search restoration. Browsing must not change `AppModel.selectedWeek`, active lineup edits or saved trade drafts. Preserve explicit trade editor/review identities.
6. [ ] Visually validate native My Team logo/tab sizing, accessibility, older supported OS behavior and iPad adaptation. The separate prototype proved type checking only.

Implementation boundaries: team/player work owns shared identity/routes and roster/player surfaces; schedule work owns schedule data/timelines; transaction work owns mutation flows. Coordinate before editing shared navigation. This documentation release changes no app navigation or API behavior.

## P2 — Broader coverage and polish

- [ ] Multi-league picker/switching with session/draft isolation; underlying account mapping already exists.
- [ ] Broader rule rendering: superflex/IDP, duplicate-player ownership, best ball/total points, doubleheaders and unusual seasons. Keep unsupported capabilities explicit and non-actionable.
- [ ] Native non-conditional BBID, classic priority and FCFS. Today only supported conditional blind bidding writes natively; other windows/formats use MFL.
- [ ] IR/taxi moves, commissioner-on-behalf actions and richer salary/contracts where capabilities allow. Reading a field does not implement its management workflow.
- [ ] Reviewed private-data offline/cold-start storage. Currently only the public player directory persists as a response cache.
- [ ] Rich board HTML/link handling beyond plain-text cleanup, optional standings columns and iPad split-view details.
- [ ] Privacy-redacted diagnostics export and remaining manual accessibility work.
- [ ] Verified injury/opponent/kickoff and season-total enrichment. Placeholder fields are not research data; optional images/news/advanced stats need source and rights verification.

### Configuration coverage matrix

Fixtures cover selected normal/failure cases, not this entire matrix. Add disposable-league and fixture evidence for every advertised format before claiming broad public write support. Untested formats remain outside the supported scope.

- Redraft/keeper/dynasty; offense/superflex/IDP; fixed slots and min–max FLEX.
- Conditional/non-conditional BBID, BBID + FCFS, priority waivers and no waivers.
- Partial lineups, game/league locks, tiebreakers, IR/taxi, salary/contracts and duplicate players.
- Best ball, total points, median/all-play, doubleheaders, byes, playoffs and shortened seasons.
- Small/large leagues (8/12/16/32/48 teams); owners and commissioners with/without a franchise.
- HTTP 200 body errors, 429, interrupted/ambiguous writes, redirects, malformed shapes, expiry and cache conflicts.

## Later — Apple ecosystem and optional research

- [ ] Widgets, Live Activities, App Shortcuts, Spotlight and contextual opt-in notifications.
- [ ] Reviewed background/push architecture and required MFL coordination. No MFL Blitz push backend, webhook integration or notification delivery exists today.
- [ ] Optional strength-of-schedule, calendar export, licensed news/player imagery and deeper research; none are prerequisites for the owner trial.

MFL's documented API does not provide the webhook/APNs contract needed to promise real-time background delivery. Foreground polling is not a background guarantee; new providers require separate scope/privacy review.
