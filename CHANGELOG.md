# Changelog

Implemented private-build history through September 7, 2026. The [roadmap](docs/roadmap.md) contains future work; design proposals are not releases. Some adjacent private builds were committed together.

## 0.5.4 (32) — September 7, 2026 — cancelled score refreshes

- Preserve Swift and URLSession cancellation as cancellation instead of wrapping it in a user-facing transport failure.
- Keep existing Scores data and warnings during cancelled manual/polling/full refreshes, release loading gates, and permit a later foreground refresh without a false successful-refresh cooldown.
- Replace raw network diagnostic dumps with concise transport-error copy; retain only numeric network codes, never URLs or UserInfo. Genuine errors, rate limits, authentication and uncertain-write safeguards remain intact; no automatic retries are added.
- Add typed cancellation, manual/polling refresh, retry, foreground recovery, safe-error and cancelled-import regressions. See [current status](docs/current-status.md) for actual delivery evidence.

## 0.5.4 (31) — September 7, 2026 — immediate player identity

- Show the tapped player's known name, position and NFL team before ownership finishes; season/game-log reads and matching-week metrics no longer wait for that response.
- Carry only display identity in scoped canonical routes; no ownership, eligibility or mutation authority is inferred. Keep actionable errors and existing reconnect boundaries.
- Add player/scope mismatch coverage and a delayed-ownership native Preview journey. Josh confirmed build 30 fixed the spinner; build 31 addresses his remaining card-latency report. Delivery evidence is recorded in [current status](docs/current-status.md).

## 0.5.4 (30) — September 7, 2026 — player loading follow-up

- Stop optional biography from blocking the primary player card; fetch it on disclosure using its existing cache.
- Reuse loaded player detail on ordinary reappearance; explicit refresh and roster changes still refresh ownership.
- Share game-info requests across screens, cancel on league reset, and allow immediate retry after interruption. Show a spinner only for an actual running request, with a compact inline presentation.
- Add cancellation, shared-read, cache, lazy-biography and scope-isolation regressions; retain mutation gates and rate-limit enforcement. Build 29's navigation fix was confirmed on Josh's phone; build 30's exact delivery/recheck evidence is in [current status](docs/current-status.md).

## 0.5.4 (29) — September 7, 2026 — player cards and matchup navigation

- Add owner names below matchup team names and remove repetitive acronyms/positional subtotals.
- Fix duplicate matchup navigation when opening a player; retain one-step Back and working team shortcuts from pushed team pages.
- Combine player identity, current status/ownership and independently loaded season points/weekly average. Own-team status no longer links to a redundant My Team page.
- Merge weekly availability and scoring; show a paged Week / Points / NFL opponent log, with the owner-approved current-team schedule caveat behind an information button. Biography becomes a secondary disclosure.
- Move Drop into a labeled secondary action menu; explicitly distinguish releasing a player from benching them. Retain eligible-only IR, free-agent Add gates, review/preflight/readback and no automatic write retries.
- Reuse cached scoring and a shared whole-season NFL schedule; no raw NFL stats provider, new storage or permissions. Actual test/installation/merge evidence is in [current status](docs/current-status.md).

## 0.5.3 (28) — September 7, 2026 — cached startup and performance

- Display saved scores, lineup, standings, Board summaries and own-team roster during reconnection; retain them offline with compact status and Retry/Sign in. A first successful load is required to seed the cache.
- Add protected, backup-excluded, session-bound display and daily league metadata caches. Fresh membership remains mandatory; cached lineups cannot edit/submit, and mutation preflight/readback never uses display data.
- Prioritize scores/lineup ahead of optional initial feeds; defer foreground trades until My Team is selected and priority reads finish. Share season-status reads while forcing the foreground week check.
- Reuse one catalog lookup index across repositories and stop re-encoding/rewriting disk cache hits. Preserve original TTLs, stricter balance freshness, per-host cooldowns, single visible poller and no automatic write retries.
- Add cache isolation, offline/expired-session, refresh-order, mutation-invalidation and native cached-startup regressions. See [review and limitations](docs/performance-startup.md) and [current verification](docs/current-status.md); synthetic timing is not a real-phone performance guarantee.

## 0.5.3 (27) — September 6, 2026 — lineup projection comparison

- Move lineup status below the projection-card divider, beside kickoff locks; adapt the footer and numeric layout for larger text.
- Add a signed green/orange projected margin against the selected week's opponent, recalculated from edited starters. Rounded ties read Even; VoiceOver states the full comparison.
- Reuse existing same-week snapshots with no additional API requests. Incomplete projections, unknown/ambiguous matchups and failed score refreshes never imply a lead. This is not a live-score or win-probability forecast.
- Add model/native regression coverage and the [projection contract](docs/lineup-projections.md). Existing review and submission protections are unchanged; [current status](docs/current-status.md) records delivery separately.

## 0.5.3 (22–26) — September 6, 2026 — direct My Team tools and standings

- Replace Transactions and Manage roster with six direct shortcuts: Schedule, Adds / Drops, Trades, Watchlist, Injured Reserve and League Activity. Two columns become one at accessibility text sizes; every button has its own accessible label and route. Trades alone carries the trade-attention count.
- Build 23 makes every navigation glyph accent green, including Injured Reserve. Contextual medical-bag actions stay neutral; the shortcut is navigation, not a player move.
- Builds 24–25 were interim placement/diagnostic iterations. Build 26 implements the approved [standings pattern](docs/standings-pattern.md): one record/place line, numeric ordinals, division name or actual league-name fallback, and matching-context standings navigation. Preseason does not claim first place; unresolved ranks remain blank.
- Replace the incorrect API-array-index rank with supported league-configured PCT/H2H/PTS/DIVPCT comparisons. Compute division and overall places separately; true exhausted ties use competition ranks. Missing data, unreconciled H2H or cycles fail conservatively. MFL's report remains the authority for custom/manual orders.
- Keep the standings selector visible while scrolling; adapt headers and table rows at accessibility text sizes. Same-name divisions stay distinct by ID. Reuse cached league/standings/schedule reads, with no per-team network fan-out.
- Fix the native IR navigation test to return toward My Team's header after inspecting a player, instead of searching farther down a lazily loaded list. Eligibility and actual-control assertions remain intact; no test is skipped.
- Adds / Drops reuses the available-player browser and saved waiver queue, with a My roster view for standalone drops. Person-plus offers Add now and Place waiver bid when both methods are supported. Search stays below the picker and preserves a separate query for each side.
- Injured Reserve shows capacity, current IR players with activation and eligible active-roster players with neutral medical bags. Drop uses a red person-minus. Existing review, final confirmation, fresh preflight and exact membership readback remain mandatory.
- Scoped roster-tool state rejects mismatched/late results and disables actions after failed refresh without discarding known roster display data. No new backend, private response persistence, automatic writes or polling is introduced.
- Updated native/model regressions and the [direct-tool contract](docs/my-team-shortcuts.md). [Current status](docs/current-status.md) records actual test and phone delivery evidence separately from live-owner acceptance.

## 0.5.2 (21) — September 6, 2026 — My Team and compact player actions

- Player Detail uses compact person-plus Add, red person-minus Drop and neutral medical-bag IR buttons inside its ownership card. IR appears only for an eligible player on the owner's active roster; existing IR players retain Activate. Spoken action/player labels and explicit review/confirmation remain.
- Add now preserves MFL's strict player-specific acquisition decision, including malformed/conflicting flags. Individually locked free agents cannot open immediate-add review. Supported first-come adds remain available in mixed blind-bid/FCFS leagues; the UI does not invent a lock reason or unlock date.
- My Team shows official league standing and matching Transactions, Schedule and Watchlist navigation cards. Its header scrolls with the roster; other-team pages retain their Roster/Schedule picker.
- The own-team roster groups players by position and sorts by actual season-to-date fantasy points. One batched, cached YTD read replaces lineup-assignment fetching. Missing values show “—” and sort last; no projections or placeholder totals are substituted.
- Regression coverage includes strict Add gates, finite/missing/negative season totals, cache/request counts, independent native navigation, symbol accessibility, eligible-only IR and confirmation cancellation. [Current status](docs/current-status.md) records final verification and device delivery separately from live-owner acceptance.

## 0.5.1 (20) — September 6, 2026 — owner-feedback fixes

- Move to IR is disabled in Player Detail, Manage roster and review unless the current scoped injury report lists Out/IR. Loading, failed, stale, other-week and unknown designations cannot enable it. Fresh preflight and MFL's final rules still apply.
- Visible-section refreshes no longer fan out to every main feed. Ordinary watchlist and roster-review reads reuse caches; actual mutation preflight/readback stays fresh. Scoring history loads only after View scoring history is tapped. Default request spacing increases to 1.25 seconds.
- Cooldowns are scoped to the rejecting server as MFL documents, so a public availability-feed 429 does not automatically block a different league server. Same-host requests stop until Retry-After expires; no host switching or automatic import retries.
- Trade composer and team-tool destinations now share typed navigation so player research returns to the asset picker or roster moves with selections intact.
- Compatibility follow-up gives roster menus explicit independent touch targets and stable accessibility identifiers; native tests handle iOS 18 menu/Back-button differences, scroll large-text targets clear of bars and tap the tiebreaker picker's actual value control. Full Xcode 16.4 / iOS 18.5 CI passed before merge; [current status](docs/current-status.md) records exact evidence.
- Signed build installed and launched on Josh's iPhone. See [current status](docs/current-status.md) for regression evidence and remaining live-owner checks; reducing request pressure does not eliminate MFL's variable rate limits.

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
