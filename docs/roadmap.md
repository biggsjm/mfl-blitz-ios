# Execution plan and remaining work

Updated September 7, 2026 for **0.6.0 (33)** implementation; installed baseline and exact delivery evidence are in [current status](current-status.md). Checked items mean implemented, not universal live-league certification. [The changelog](../CHANGELOG.md) records release history. Earlier “read-only TestFlight” milestone headings are superseded: native write workflows exist, but distribution is still pending.

## Completed baseline

- [x] Native Scores / Lineup / My Team / Standings / Board and safe interactive preview; My Team has six direct tools with Schedule first.
- [x] Account/franchise mapping, validated host discovery, Keychain restore, expiry UI, bounded reconnect and independent tab loading.
- [x] Foreground live scores, positional matchup drill-down/FLEX, pregame projections and official completed results.
- [x] League-derived lineup limits, bench/starter/FLEX replacements and rotations, scoped drafts, modal review and starter-set verification.
- [x] Compact [lineup projection comparison](lineup-projections.md): edited starters versus the same week's opponent, signed green/orange margin, status beside kickoff locks, no added API traffic and conservative missing-data behavior.
- [ ] Follow up on Lineup player-row and Starting-header truncation at the largest accessibility text size; the redesigned summary card does not resolve the surrounding editor's layout.
- [x] Conditional blind-bid queues, confirmed $0 league fallback, fresh preflight, round replacement/cancellation and partial-outcome recovery.
- [x] Native trades and separate counteroffers, durable unconfirmed-action protection, prominent Create/Resume, draft cancel/rollback and correct first-tap response reviews.
- [x] MFL standings/owner names, safe team artwork, native board threads/replies and exact-post verification.
- [x] Approved [compact standings pattern](standings-pattern.md): numeric ordinals, division/overall ranks, shared linked team headers, real ties and conservative preseason/missing states. Authenticated read verified array order is not rank; supported configured criteria replace that assumption.
- [x] Board Close/save/discard flow, visible Drafts and Resume reply, blank-draft filtering and storage-failure protection (0.4.1).
- [x] Daily public player disk cache and shared decoded index, protected daily league metadata and display-only cached startup, prioritized initial reads, request sharing/spacing/cooldowns and no blind write retries. See [performance review](performance-startup.md).
- [x] Original icons, explicit Week N controls, adaptive layouts and accessibility foundations.
- [x] Performance regressions, four synthetic managers across two accelerated weeks and native UI journeys; private build installed on the owner's phone.
- [x] Designer-reviewed player summary, unified Week card, automatic paged game log with disclosed current-team NFL opponents, collapsed biography and secondary explicit Drop actions.
- [x] Matchup owner names, simplified position headers and single-stack matchup → player → Back routing; team tools work from pushed destinations.
- [x] Player loading: lazy cached biography, reused primary detail on ordinary reappearance, and model-owned availability reads that survive screen cancellation. Josh confirmed the spinner fix; remaining card latency prompted build 31. Actual phone timing remains open.
- [x] Immediate display-only player identity from the tapped row, independent Week/research loading, and unchanged ownership/action gates (build 31; local/GitHub verification passed, owner latency recheck remains open).
- [x] Normalize URLSession cancellation, keep Scores visible without false refresh alerts, release retry gates, and remove raw transport diagnostic messages (build 32; installed, full local/GitHub checks passed and PR #9 merged; Josh confirmed the fix works September 7).
- [x] Initial My Team/shared team roster, Player Detail, team/league season schedules and canonical-ID navigation. Player tools 1–5 extend this in the installed build.

## P0 — Dev-device Week 1 validation and later release gates

September 7 decision: Josh will validate Week 1 on his development device. TestFlight is on hold until both iOS 27 and macOS 27 leave beta, then still requires the gates below and Josh's go-ahead. This replaces the earlier Week 2 invitation deadline; it is an owner preference, not an asserted Apple requirement. No OS release date is assumed. Each gate remains open until its evidence is recorded; a calendar date or passing fixtures is not enough.

| Remaining gate | Owner / action | Done when |
| --- | --- | --- |
| Live scoring and rollover | Josh, with developer triage | Week 1 totals, player points/FLEX, clocks, final corrections, offline recovery and Week 2 selection match MFL; record build/time/result in the [checklist](week-1-testing.md) |
| Cached startup on phone | Josh + developer | Seed build 28 or newer once; warm relaunch shows known content before reconnect, offline retains it, recovery updates it, and no cached lineup enables a submission. Record Wi-Fi/cellular time-to-content |
| Live standings | Josh + developer | Completed-week division/overall places, H2H and true ties match the signed-in MFL report; identify any commissioner custom order not mirrored by the API |
| Real write verification | Josh + consenting league/test owner | Intended lineup, $0/conditional queue and processing, trade proposal/each response, board thread/reply, watchlist changes, FCFS add/drop and eligible IR moves match MFL; ambiguous outcomes cause no duplicate writes. Exercise unwanted/destructive cases only in a disposable league |
| Regression and usability | Developer + owner | Full core/app/UI suites green on candidate; small-screen/iPad, light/dark, large text, VoiceOver, Voice Control/Switch Control, contrast and deadline flows reviewed; release blockers resolved |
| MFL client identity | Repository owner / developer | Registration confirmed and exact approved User-Agent configured; current `MFL Blitz/0.1 (com.biggsjm.MFLBlitz)` must not be assumed registered |
| Apple distribution | Apple account owner / developer | App Store Connect/TestFlight record, signing/archive, beta metadata, privacy/support details, applicable compliance/review requirements and tester access verified; clean install/update tested |
| Support and security | Repository owner | Private reporting route established and documented; GitHub private vulnerability reporting was disabled at the September 6 audit |
| Invite decision | Josh | Above gates passed for the advertised scope, known limits communicated, and MFL fallback/support available |

Josh has reported a successful lineup submission and seeing projections. These observations do not close the entire write or game-week gate. No production registration, TestFlight approval or completed live Week 1 validation is recorded.

My Team is a separately verified product increment. It does not substitute for real game-week evidence or the distribution gates.

## P1 — My Team, schedule and player detail

- [x] Replace oversized Player Detail action rows with compact accessible buttons; preserve strict acquisition flags so locked free agents cannot open Add review (0.5.2 follow-up). Test/device delivery is tracked in [current status](current-status.md), independently of live-owner acceptance.
- [x] My Team: contextual division/league standing, Schedule / Adds & Drops / Trades / Watchlist / Injured Reserve / League Activity shortcuts, then a position-grouped roster sorted by actual season-to-date points. No overlapping Transactions / Manage roster pages. One batched YTD read replaces assignment fetching; missing totals stay blank. See [direct-tool contract](my-team-shortcuts.md).

**Current installed increment: [Player tools 1–5](player-tools-plan.md).** Josh approved injury/kickoff/bye context, richer league-scored player research, an MFL-synced watchlist, native first-come add/drop and IR management on September 6. The linked plan defines acceptance checks and keeps trading blocks, calendars, polls and playoff brackets queued after those five. All five are implemented in build 20; test/CI/device evidence and live-owner checks are recorded separately.

**Initial slice implemented in 0.4.0 (17).** Tabs: **Scores / Lineup / My Team / Standings / Board**. My Team replaces only Transactions. No Players tab and no new global search destination; reuse the existing available-player search in My Team → Adds / Drops.

1. [x] Implement canonical-ID routes and the shared read-only team shell. My Team exposes the six Schedule-first shortcuts above its roster; dedicated Lineup retains editing/submission. Other-team pages never present owner tools. Preserve the trade-specific badge on My Team and Trades.
2. [x] Add team roster and truthful initial player detail: identity, authoritative ownership/status, available projection/current points and optional supplied bio/contracts. Keep identity taps separate from lineup/waiver/asset-selection actions. See [player-detail plan](player-detail-ux.md).
3. [x] Validate the official schedule request/schema; add a shared season/league cache and team/league timelines. Use configured week bounds, distinguishing byes, TBD, missing data and multiple matchups. See [schedule plan](schedule-ux.md).
4. [x] Visible targeted game log (four completed weeks/page), season totals/average and disclosed current-team NFL opponents; biography loads only when expanded. Missing scores are not zero. Live completed-week comparison remains a Week 1 gate.
5. [x] Waiver identity links, separate trade research controls and modal routing are implemented alongside existing routes. Browsing must not change `AppModel.selectedWeek`, active lineup edits or saved trade drafts. Preserve explicit trade editor/review identities.
6. [ ] Complete supported-device/accessibility validation. Native iPhone simulator journeys cover the My Team logo, team/league routes and large-text direct-tool access; minimum-supported-OS, iPad and full manual assistive-technology review remain.

Implementation boundaries: team/player work owns roster/player surfaces; schedule work owns season data/timelines; native-app work owns shared routes/navigation and existing mutation flows. All slices were coordinated before integration. Schedule browsing uses destination-local scores and preserves active lineup and trade drafts.

## Next feature queue — after player tools 1–5

6. [x] Trading Block: browse listings, publish players/picks/needs with owner preflight and readback, resume drafts and safely start offers. [Approved plan](trading-block-calendar-plan.md); whole-list removal/cash publication remain MFL-only until verified.
7. [x] League Calendar, opt-in deadline reminders and selected-event Apple Calendar handoff. Exact recurring instances/DST verified from owner-provided MFL exports. Development-device validation only until the distribution hold is lifted.
8. [ ] Board polls and voting.
9. [ ] Playoff brackets beside schedules.

Items 6–7 are implemented in 0.6.0 (33); 8–9 remain queued in the [feature plan](player-tools-plan.md). Delivery and live-owner acceptance are distinct. Device reminder delivery, changed deadlines, active-game ActivityKit behavior and new-feature accessibility checks remain open in the [checklist](week-1-testing.md).

## P2 — Broader coverage and polish

- [ ] Multi-league picker/switching with session/draft isolation; underlying account mapping already exists.
- [ ] Broader rule rendering: superflex/IDP, duplicate-player ownership, best ball/total points, doubleheaders and unusual seasons. Keep unsupported capabilities explicit and non-actionable.
- [ ] Broader non-conditional BBID and classic priority waivers. Conditional blind bidding and capability-gated FCFS are implemented; unsupported formats use MFL.
- [ ] Taxi moves, broader IR formats, commissioner-on-behalf actions and richer salary/contracts. Basic Out/IR deactivation and activation with reviewed drops are implemented. Reading a field does not implement its management workflow.
- [x] Bounded private display-only cached startup and daily league metadata with protection, account binding and fresh write checks (build 28). Full offline schedule/player browsing is not implemented.
- [ ] Audit watchlist and research read cancellation on rapid navigation as a follow-up to shared availability reads; keep retry/empty/loading states distinct without relaxing mutation gates.
- [ ] Manual VoiceOver review of missing-value announcements and full player-card comprehension; large-text screenshots and native tests do not substitute for assistive-technology use.
- [ ] Device Instruments launch/CPU traces and realistic p50/p95 measurements; evaluate further on-demand optional feeds based on evidence. See [performance follow-ups](performance-startup.md).
- [ ] Rich board HTML/link handling beyond plain-text cleanup, optional standings columns and iPad split-view details.
- [ ] Privacy-redacted diagnostics export and remaining manual accessibility work.
- [x] Official injury/opponent/kickoff/bye and league-scored research integration. Actual game-week completeness remains under owner validation; licensed news/images/raw stats need separate sourcing.

### Configuration coverage matrix

Fixtures cover selected normal/failure cases, not this entire matrix. Add disposable-league and fixture evidence for every advertised format before claiming broad public write support. Untested formats remain outside the supported scope.

- Redraft/keeper/dynasty; offense/superflex/IDP; fixed slots and min–max FLEX.
- Conditional/non-conditional BBID, BBID + FCFS, priority waivers and no waivers.
- Partial lineups, game/league locks, tiebreakers, IR/taxi, salary/contracts and duplicate players.
- Best ball, total points, median/all-play, doubleheaders, byes, playoffs and shortened seasons.
- Small/large leagues (8/12/16/32/48 teams); owners and commissioners with/without a franchise.
- HTTP 200 body errors, 429, interrupted/ambiguous writes, redirects, malformed shapes, expiry and cache conflicts.

## Later — Apple ecosystem and optional research

- [x] Foreground-updated current-matchup Live Activity and contextual local deadline reminders (build 33); actual game-week/device acceptance remains open.
- [ ] Home Screen widgets, App Shortcuts and Spotlight.
- [ ] Reviewed background/push architecture and required MFL coordination. No MFL Blitz APNs backend or webhook integration exists. Local reminders can fire while closed; matchup scores cannot promise continuous closed-app updates.
- [ ] Optional strength-of-schedule, full calendar subscription, licensed news/player imagery and deeper research; selected-event Apple Calendar handoff is implemented, but these broader items are not prerequisites for the owner trial.

MFL's documented API does not provide the webhook/APNs contract needed to promise real-time background delivery. Foreground polling is not a background guarantee; new providers require separate scope/privacy review.
