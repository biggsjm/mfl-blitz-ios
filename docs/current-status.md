# Current app status

Audited September 6, 2026. [Roadmap](roadmap.md) is the remaining execution plan; [changelog](../CHANGELOG.md) records private-build history.

## Current installed private build

**0.5.1 (20)** implements the approved [features 1–5](player-tools-plan.md): official availability, on-demand league-scored history, synced watchlist, reviewed FCFS add/drop and IR activation/deactivation. The signed build from source `067bbeb` installed and launched on Josh's iPhone September 6. It replaces **0.5.0 (19)**, on which Josh reported enabled IR controls for ineligible players and 429 cooldowns on Lineup/My Team. Build 20 adds early IR eligibility gating, section-local refresh, cached browse reads, deferred history, per-host cooldowns and 1.25-second request spacing. Installation/launch is verified; live post-fix browsing and intended roster moves remain owner checks.

Wire validation: Josh supplied abilities, empty/singleton watchlist responses and player 9431's owned status for franchise 0008. Public availability feeds were checked; last season's nonempty points-allowed response verified position totals. No real roster/trade/waiver/lineup/board writes were made by automated QA. Watching another owner's player is valid and does not imply free-agent eligibility.

Build-20 verification:

- **Core:** 75 tests / 11 suites passed, including optional acquisition flags and host-specific cooldown behavior.
- **Local app regression:** all 145 app unit functions and six affected native journeys passed: 151 functions / 183 executions, zero failures, skipped tests or reported runtime warnings (`mfl-player-tools-build20.xcresult`).
- **Final source navigation:** after the shared typed-route follow-up, all nine selected native journeys passed on `067bbeb`: five player-tools journeys plus trade-draft research/back, own-team/future schedule, current-matchup/player and standings/league-schedule navigation. Zero failures, skips or reported runtime warnings (`mfl-player-tools-final-navigation.xcresult`, iPhone 17 Pro / iOS 27).
- **Visual inspection:** actual Light/Dark screenshots reviewed for watchlist, on-demand research, explicit add/drop review, IR confirmation, disabled IR in both Player Detail and the roster menu, and largest-text identity/action. Mixed navigation styles and a task attached to initially empty research content were found and fixed; the corresponding research/return journeys now pass.
- **Baseline, not final-source evidence:** the full build-19 local regression passed 170 app/UI functions / 199 executions before owner-feedback fixes. The later focused results above do not mislabel that older run as build 20.
- **GitHub compatibility follow-up:** run [34062437245](https://github.com/biggsjm/mfl-blitz-ios/actions/runs/34062437245) passed core and all 145 app unit functions, but failed five of 29 native journeys (seven assertions). Failures concerned older-iOS roster-menu discovery and the two-week journey's tiebreaker picker. Local iOS 18.4 reproduced a Back-button identifier difference; its two-week journey passed. The follow-up uses explicit roster-menu identifiers/independent touch targets, title-scoped Back buttons and the tiebreaker picker's actual trailing control. Local and GitHub reruns are pending; [PR #3](https://github.com/biggsjm/mfl-blitz-ios/pull/3) remains unmerged until verified. The phone still has the `067bbeb` build until the final compatibility rebuild is delivered.

Default request spacing reduces pressure but does not guarantee freedom from MFL's variable per-server/per-IP limits. Registered client identity remains unconfirmed. Native IR is conservatively limited to current Out/IR reports verified for Champion Hall; the API does not expose every league-specific IR rule, and MFL still enforces final eligibility.

## Previous installed private build

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
| My Team / team pages | Franchise logo/initials, owner/record, roster, schedule and own-team watchlist; Transactions and Manage roster entries | No second lineup editor; another team never shows your inbox or owner roster controls |
| Player Detail | Identity, ownership/status, weekly metrics, availability, progressive history, totals/average, points allowed, watch star and supplied biography | Missing source data stays absent; no external imagery/news or guessed facts |
| Season schedule | Shared team/league timelines, configured bounds, current/future/final/unset states and route-local matchup scoring | Ambiguous doubleheaders never select an arbitrary scoring game; missing opponents are not guessed byes |
| Waivers / roster moves | Available-player search/watch filtering, conditional blind bids and reviewed FCFS/IR actions with exact membership readback | Supported owner/rule gates only; broader classic/non-conditional, taxi, salary and duplicate-player formats use MFL |
| Trades | Create/Resume, private drafts, Cancel/rollback, blank-save disabled, exact proposal/response review and separate counters | Counter leaves original open; acceptance can await MFL processing; no blind retries |
| Standings | Official overall/division order, owners, artwork, anchored info and team drill-through | Missing owners not guessed; current record is not a projected record |
| Board | Native threads/posts/replies, visible Drafts, Resume reply, Close/save/discard and exact-post readback | Saving a draft sends no post; plain text, not rich HTML or proprietary chat |
| Storage/network | Device-only Keychain sessions/drafts/markers, daily public catalog and private memory caches | No private offline response store, analytics or backend |

Team/player/season reads have session-generation and canonical-route checks. Browsing never changes the active lineup draft, shared scoring week or saved trade terms. Current schedule detail replaces the scoreboard poller while visible; future weeks do not poll. League metadata and public player data remain cached during roster/player refresh.

## Historical My Team / build-18 verification evidence

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

The installed build includes [Player tools 1–5](player-tools-plan.md): availability context, player research, synced watchlists, native FCFS add/drop and IR. Its checkboxes track engineering delivery separately from live-owner certification; trading blocks, calendars, polls and playoff brackets are explicitly queued afterward.

- Compare completed player history, season metrics and points-allowed coverage against MFL after Week 1; the bounded implementation and synthetic fixtures are not live-game evidence.
- Contextual waiver/trade links are implemented. Validate their live-owner use with retained search, selections and drafts. No Players tab/global directory is introduced.
- Season timelines use league bounds, but the separate Scores/Lineup week picker still uses 1…18.
- Optional live biography fields vary. No headshots/news/licensed raw-stat feed or ADP is integrated; official availability and fantasy totals are now implemented.
- Legacy live Lineup `opponent`/game-time and Lineup/Waiver `seasonPoints`/trend/rostered-percent placeholders are not reused as player research facts.
- Broad league-format certification, multi-league switching, broader FCFS/IR formats, taxi/commissioner management, rich board HTML, private offline snapshots, diagnostics export and iPad split-view remain unfinished.
- Full manual VoiceOver/Voice Control/Switch Control, contrast, small-screen/iPad and older-supported-OS validation remain release gates.
- MFL client registration is unconfirmed. The app still supplies `MFL Blitz/0.1 (com.biggsjm.MFLBlitz)`; do not change a registered-client identity merely to match a marketing version.
- GitHub private vulnerability reporting was disabled at the September 6 audit. Establish a safe private reporting route before wider distribution.
- Apple/App Store Connect/TestFlight setup, actual Week 1 evidence and Josh's invitation decision remain open. Follow the [owner checklist](week-1-testing.md) and P0 [release gates](roadmap.md); My Team does not replace them.
