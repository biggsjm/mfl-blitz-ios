# Changelog

Implemented private-build history through September 6, 2026. The [roadmap](docs/roadmap.md) contains future work; design proposals are not releases. Some adjacent private builds were committed together.

## 0.5.1 (20) — September 6, 2026 — owner-feedback candidate

- Move to IR is disabled in Player Detail, Manage roster and review unless the current scoped injury report lists Out/IR. Loading, failed, stale, other-week and unknown designations cannot enable it. Fresh preflight and MFL's final rules still apply.
- Visible-section refreshes no longer fan out to every main feed. Ordinary watchlist and roster-review reads reuse caches; actual mutation preflight/readback stays fresh. Scoring history loads only after View scoring history is tapped. Default request spacing increases to 1.25 seconds.
- Cooldowns are scoped to the rejecting server as MFL documents, so a public availability-feed 429 does not automatically block a different league server. Same-host requests stop until Retry-After expires; no host switching or automatic import retries.
- Trade composer destinations now share typed navigation so player research returns to the asset picker with selections intact.

## 0.5.0 (19) — September 6, 2026 — player tools

- Shared official injury, opponent/kickoff and bye context in player details, roster, lineup/replacements and available-player rows. Missing reports are not proof of health; acquisition locks remain separate from lineup locks.
- League-scored player history, season total/average and recent-form chart. Initially reads four completed weeks, with explicit earlier-page loading; missing scores remain distinct from zero. Opponent points allowed are position totals, not invented per-game averages.
- MFL watch/unwatch with fresh readback, My Team → Watchlist, waiver filtering and durable uncertain-toggle recovery. Owner-supplied empty/singleton watchlist and abilities responses verified the private formats.
- Reviewed first-come add/drop and IR/activation through My Team → Manage roster and Transactions → Waivers. Exact owner permissions, supported formats, fresh roster/limits and acquisition eligibility gate writes. Activation may include an explicitly reviewed drop.
- Roster changes persist a marker before their only import and require exact current-membership readback. A pending move blocks other roster-affecting writes until checked. Refresh preserves lineup, waiver and trade drafts.
- Contextual player research links in waiver/trade surfaces preserve asset-selection controls. New core/model/native safety and two-week synthetic journeys; [current status](docs/current-status.md) records final test, CI and device evidence.
- The [approved plan](docs/player-tools-plan.md) retains trading block, calendar/reminders, polls and playoff brackets as the next four features, not part of this increment.

## 0.4.1 (18) — September 6, 2026

- Board composers use Close. Empty composers close immediately; meaningful content offers Save draft, Discard draft or Keep editing in a centered alert.
- A visible Drafts section on Board opens saved new threads and replies. Threads with an unfinished reply offer Resume reply.
- Removed the storage-specific composer callout. Empty drafts are omitted; confirmed save/discard failures keep the composer open, and discarded/posted drafts cannot be recreated by late field callbacks.
- Added focused model/native draft regression tests and updated the [Board contract](docs/board-drafts.md), owner checklist, privacy notes and remaining plan. Trade composer controls are unchanged by this Board-specific update.
- Pre-merge compatibility fixes: roster requests use a bounded task group to avoid Swift 6.1 async-let cleanup crashes; player ownership headings/rows have stable accessibility identifiers across iOS versions. No tests were removed or skipped.

## 0.4.0 (17) — September 6, 2026

- My Team replaces only the center Transactions tab, with a native team-logo/initials icon, visible Transactions entry and preserved trade badge. Dedicated Lineup stays one tap away.
- Shared read-only team rosters and Player Detail: canonical identity, current ownership/status, available matching-week metrics and optional MFL biography. Lineup arrows remain independent actions.
- Team and league season schedules use one shared cached export, configured season bounds, explicit future/unset states and route-local matchup scoring. Browsing does not change lineup drafts or the Scores/Lineup week.
- Concise schedule freshness ("Updated just now" / "Updated 2 min ago") without seconds.
- Contextual links from Standings, lineup identity, matchup players/teams and schedule participants; no new global search or second lineup editor.
- Regression coverage for caches, old-session results, draft isolation, duplicate matchups and native navigation. Corrected propagated accessibility identifiers, standings column spacing and synthetic player detail coverage.
- Updated status, remaining plan, API/cache/privacy notes, feature contracts and owner checklist. Full history and additional waiver/trade player links remain planned; see [current verification](docs/current-status.md).

## 0.3.7 (16) — September 6, 2026

[`e779e4b`](https://github.com/biggsjm/mfl-blitz-ios/commit/e779e4b)

- Prominent, persistent Create trade / Resume trade; one confirmed-empty state; secondary refresh/MFL/discard options and visible error recovery.
- Cancel and rollback in trade editing; Save & close disabled for blank drafts; no empty draft just from opening; fresh editor identity and late-autosave protection.
- Fixed first-tap Decline/Withdraw presenting default Accept review by passing one identifiable action payload into a fresh review.
- Full app unit suite plus five trade UI journeys passed: 96 functions / 121 executions. Built, installed and launched on the owner's phone. No real trade action performed by QA.

## 0.3.6 (14) — September 6, 2026

[`9465ce6`](https://github.com/biggsjm/mfl-blitz-ios/commit/9465ce6): shared explicit Week N calendar controls on Scores/Lineup, Settings upper-left on Scores, more legible crossing-route icon, and concise lineup replacement copy without storage-specific footers.

## 0.3.5 (13) — September 6, 2026

[`2a99834`](https://github.com/biggsjm/mfl-blitz-ios/commit/2a99834): eligible starters as well as bench candidates, FLEX swaps and atomic multi-step rotations, scoped slot persistence and concise arrow-based move previews. MFL starter membership remains distinct from local slot placement. See [lineup behavior](docs/lineup-starter-swaps.md).

## 0.3.4 (12) — September 6, 2026

[`e8bff54`](https://github.com/biggsjm/mfl-blitz-ios/commit/e8bff54): original crossing football-play routes for the Lineup tab, native template tinting and accessibility/asset tests.

## 0.3.3 (11) — September 6, 2026

[`d06f25b`](https://github.com/biggsjm/mfl-blitz-ios/commit/d06f25b): decoded catalog reuse, shared-read cancellation fixes, malformed date/Retry-After and duplicate-ID defenses, fewer trade readback downloads, live clock fallback and four synthetic managers across two accelerated weeks. See [audit report](docs/two-week-synthetic-testing.md).

## 0.3.0–0.3.2 (8–10) — September 6, 2026

[`688fcfb`](https://github.com/biggsjm/mfl-blitz-ios/commit/688fcfb) consolidates these private builds:

- **0.3.0:** Transactions hub and native trade proposals/responses, durable verification markers, independent refresh/search improvements and league-aware FLEX replacement.
- **0.3.1:** correct transaction-type/amount parsing, owner names in standings, lineup modal review, clearer waiver wording and confirmed $0 minimum fallback for league 41333/2026.
- **0.3.2:** daily persistent public player catalog, stable league memory caching with fresh balance/preflight exceptions, and shared FLEX allocation for live scores.

## Earlier private milestones — September 5–6, 2026

- **0.2.5:** safe league icons/logos in scores, matchup headers and standings; cookieless bounded image loading and initials fallback.
- **0.2.3–0.2.4:** required-position replacement sheet and starter projection comparison, later expanded by 0.3.0/0.3.5.
- **0.2.2 (4):** projection decoder tolerates anonymous empty rows without dropping the entire valid feed; authenticated read-only device verification.
- **0.2.1:** league-scored MFL/Fantasy Sharks projections and nonblocking section loading after bounded account reconnection.
- **0.2 / initial builds:** foreground scores/final reconciliation, secure session and scoped draft restoration, conditional-waiver and board verification, anchored standings info, direct lineup controls, matchup drill-down and verified lineup submission.
- Initial foundation: SwiftUI five-tab app, original branding, Champion Hall preview, MFLCore, login/host redirect handling and year formatting. Preseason scoring unavailability no longer prevents account entry; connected writes are not mislabeled as safety preview.

## September 6 documentation baseline — before 0.4.0

Updated release status, remaining plan, API/cache/storage descriptions, privacy/security and contributor guidance; consolidated the agreed but unimplemented My Team/schedule/player-detail directions. That earlier documentation-only update did not increment the app version; 0.4.0 subsequently implements the initial My Team slice.
