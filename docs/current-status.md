# Current app status

Audited September 6, 2026. [Roadmap](roadmap.md) is the remaining execution plan; [changelog](../CHANGELOG.md) records private-build history.

## Current private build

- **MFL Blitz 0.4.1 (18): My Team and Board drafts.** Implemented, tested and signed. The final compatibility rebuild was installed and launched successfully on Josh's iPhone on September 6 after the phone became available. Includes the concise schedule update label and Board Close/save/discard with visible draft recovery.
- Previous installed baseline: **0.3.7 (16), [e779e4b](https://github.com/biggsjm/mfl-blitz-ios/commit/e779e4b)**. The documentation baseline was merged in [PR #1](https://github.com/biggsjm/mfl-blitz-ios/pull/1).
- **Private owner testing**, not an App Store/TestFlight release. Production MFL registration and Week 2 invitation readiness remain unconfirmed.
- Tabs: **Scores / Lineup / My Team / Standings / Board**. Transactions is prominently available inside My Team, above Roster / Schedule. Settings remains upper-left on Scores; Scores and Lineup retain Week N controls.
- Connected mode performs real reads and explicitly reviewed writes. Champion Hall preview uses synthetic data, offers, owners and schedules; its actions send nothing to MFL.

## Implemented workflows

| Area | Behavior | Important boundary |
| --- | --- | --- |
| Scores | Featured/all matchups, positional/FLEX detail, foreground refresh and final reconciliation | No background push; projections are not live win forecasts |
| Lineup | League-aware bench/starter/FLEX replacements and rotations, saved drafts, review and starter readback | MFL stores starter IDs, not FLEX placements; saved tiebreakers cannot be read back |
| My Team / team pages | Franchise logo/initials, owner/record, roster and schedule; own-team Transactions entry and trade badge | Read-only roster; another team never shows your inbox as theirs |
| Player Detail | Canonical identity, current ownership/status, matching-week available metrics and optional supplied biography | No complete season history, external imagery/news, guessed opponent or placeholder season totals |
| Season schedule | Shared team/league timelines, configured bounds, current/future/final/unset states and route-local matchup scoring | Ambiguous doubleheaders never select an arbitrary scoring game; missing opponents are not guessed byes |
| Waivers | Available-player search, conditional blind bids, round order/budget/minimum checks, review and partial-save recovery | Native FCFS/classic/non-conditional formats remain unsupported; MFL fallback |
| Trades | Create/Resume, private drafts, Cancel/rollback, blank-save disabled, exact proposal/response review and separate counters | Counter leaves original open; acceptance can await MFL processing; no blind retries |
| Standings | Official overall/division order, owners, artwork, anchored info and team drill-through | Missing owners not guessed; current record is not a projected record |
| Board | Native threads/posts/replies, visible Drafts, Resume reply, Close/save/discard and exact-post readback | Saving a draft sends no post; plain text, not rich HTML or proprietary chat |
| Storage/network | Device-only Keychain sessions/drafts/markers, daily public catalog and private memory caches | No private offline response store, analytics or backend |

Team/player/season reads have session-generation and canonical-route checks. Browsing never changes the active lineup draft, shared scoring week or saved trade terms. Current schedule detail replaces the scoreboard poller while visible; future weeks do not poll. League metadata and public player data remain cached during roster/player refresh.

## Verification evidence

- **MFLCore:** 68 tests in 10 suites passed in a fresh temporary build directory, including schedule wire/request/cache/auth regressions.
- **My Team full native regression:** 147 app/UI functions / 173 executions passed, including all 22 then-existing native UI journeys, with zero failures or reported runtime warnings on iPhone 17 Pro / iOS 27 simulator.
- **My Team follow-up:** all 126 app unit functions plus the current-schedule native journey passed (127 functions / 153 executions), after concise freshness, duplicate-source-ID safety and final-results rollover adjustments. This adds one freshness test to that full-suite baseline.
- **Build 18 final regression:** all 130 app unit functions plus three Board native journeys passed (133 functions / 159 executions), with zero failures or runtime warnings. Covers blank close, Keep editing, save/resume from Drafts, reply recovery, discard/no resurrection, team isolation, storage failures and posting cleanup. The final project contains 130 unit functions and 24 UI journeys; GitHub runs the complete suite. MFLCore remains 68 tests / 10 suites.
- **Compatibility follow-up:** all 130 app unit functions and both player-navigation UI journeys passed after the task-group and accessibility changes (132 functions / 158 executions), zero failures/runtime warnings on the local iOS 27 simulator. All three Board journeys also passed a separate Dark Mode run. The corrected [Xcode 16.4 / iOS 18.5 CI run](https://github.com/biggsjm/mfl-blitz-ios/actions/runs/34054161224) then passed all 130 app unit functions and all 24 UI journeys, plus the separate core job.
- **Coverage:** cache request budgets, stale-account completion, multiple ownership, schedule bounds/duplicates and four synthetic managers across two accelerated weeks. My Team → roster → player → future matchup preserves an edited lineup; current Week 1 matchup → player preserves a separate Week 2 selection. Standings → team → league schedule, maximum Dynamic Type Transactions access, lineup arrows and standings information also passed.
- **Visual inspection:** actual native screenshots reviewed for My Team roster/schedule, player ownership/projection, future-matchup missing-score behavior, league schedule, lineup action separation, tab artwork and large-text trade access. Default-size Light and Dark appearances verified; complete manual accessibility/device coverage remains open.
- **Physical device:** the final signed 0.4.1 (18) compatibility rebuild installed and launched successfully on September 6 once Josh made the phone available. Earlier attempts were blocked by locking/connectivity, not build/signing errors. This confirms delivery and launch, not a complete physical-device workflow audit. Josh reported the earlier My Team screen looked good and supplied a live schedule screenshot; that observation does not certify all opponent data or a full game week. Board's latest native composer, centered close prompt and readable Drafts entry were visually reviewed in Light and Dark appearances in the simulator. No live league writes were performed for installation or launch verification.
- **GitHub:** [PR #2](https://github.com/biggsjm/mfl-blitz-ios/pull/2) was squash-merged as [632a4a6](https://github.com/biggsjm/mfl-blitz-ios/commit/632a4a66dccf5c98f36be10e71d2809fcdd037bc) on September 6 after both core and iOS checks passed for final source revision `2cc036e`. This documentation-only completion record changes no app code or tests. The PR and [CI history](https://github.com/biggsjm/mfl-blitz-ios/actions/workflows/ci.yml) retain the detailed check results.

Development artifacts are outside the repository. Intermediate failures were corrected before final verification: a test fixture initially rejected empty synthetic credentials; a root accessibility identifier hid child identifiers; the beta simulator briefly exposed duplicate tab entries. A synthetic own-team scoring-ID mismatch also required preview-only detail lookup coverage. These earlier failed runs are not counted as passing final tests.

The first complete pre-merge [CI run](https://github.com/biggsjm/mfl-blitz-ios/actions/runs/34052528470) found additional Xcode 16.4 / iOS 18.5 compatibility failures: roster tests aborted during Swift task allocation cleanup, and two player-page UI assertions depended on literal section-heading capitalization. Roster assembly now uses a bounded task group; player ownership uses explicit heading/row identifiers and stable text casing. Existing regression cases remain enabled. The corrected full run passed before merge; neither the failed run nor local beta-toolchain success alone was used as the merge gate.

All native QA explicitly enters preview and performs no live lineup, waiver, trade or board writes. Synthetic managers/weeks are automated scenarios, not human participants or real elapsed game weeks.

## Historical baseline and owner evidence

- Build 16: 96 local app/UI functions / 121 executions; full app unit suite plus five trade journeys, zero failures/runtime warnings. Its [app CI](https://github.com/biggsjm/mfl-blitz-ios/actions/runs/34046368810) passed core and iOS jobs.
- Earlier build 0.3.3 benchmarks and methods remain in the [synthetic report](two-week-synthetic-testing.md); [starter/FLEX behavior](lineup-starter-swaps.md) retains its versioned evidence.
- Josh reported successful lineup submission and visible projections. Earlier authenticated read-only device checks confirmed team artwork, owners, catalog reuse and tradable assets.
- Complete actual Week 1 scoring/rollover/processing and consenting-owner trade validation remain open. Dated counts do not guarantee future league data.

## Known gaps and next work

The next approved increment is [Player tools 1–5](player-tools-plan.md): availability context, player research, synced watchlists, native FCFS add/drop and IR. Its checkboxes track implementation separately from the installed 0.4.1 build; trading blocks, calendars, polls and playoff brackets are explicitly queued afterward.

- Full player scoring history still needs a verified endpoint and progressive cache. Do not issue 18 forced full-week reads on first open.
- Add player links/actions in waiver/trade surfaces with independent asset-selection controls, modal destinations and search/scroll/draft restoration. Existing waiver search remains available-player-only; no Players tab/global directory is introduced.
- Season timelines use league bounds, but the separate Scores/Lineup week picker still uses 1…18.
- Optional live biography fields vary. No headshots/news/licensed raw-stat feed, ADP, verified injury/opponent/kickoff enrichment or reliable season totals are integrated.
- Legacy live Lineup `opponent`/game-time and Lineup/Waiver `seasonPoints`/trend/rostered-percent placeholders are not reused as player research facts.
- Broad league-format certification, multi-league switching, native FCFS/IR/taxi/commissioner management, rich board HTML, private offline snapshots, diagnostics export and iPad split-view remain unfinished.
- Full manual VoiceOver/Voice Control/Switch Control, contrast, small-screen/iPad and older-supported-OS validation remain release gates.
- MFL client registration is unconfirmed. The app still supplies `MFL Blitz/0.1 (com.biggsjm.MFLBlitz)`; do not change a registered-client identity merely to match a marketing version.
- GitHub private vulnerability reporting was disabled at the September 6 audit. Establish a safe private reporting route before wider distribution.
- Apple/App Store Connect/TestFlight setup, actual Week 1 evidence and Josh's invitation decision remain open. Follow the [owner checklist](week-1-testing.md) and P0 [release gates](roadmap.md); My Team does not replace them.
