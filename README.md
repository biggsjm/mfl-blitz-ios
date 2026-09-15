# MFL Blitz

Build 64 follows the owner’s compact comparison-row reference, with equal-height player areas and points beside the center position gutter. **Live players** shows active-game starters under pinned official totals. Ownership appears in search and player Week details; scoring rows retain stats while calculations stay in details. League abbreviations and the existing NFL request budget are preserved. See [behavior](docs/matchup-mode-plan.md) and [delivery status](docs/current-status.md).

> Deep enough for MFL. Calm enough for Sunday.

MFL Blitz is an independent, native SwiftUI companion for [MyFantasyLeague](https://www.myfantasyleague.com/). It puts the deadline-sensitive things first: scores, lineups, transactions, standings, and the league message board.

<img src="docs/app-icon-source.png" alt="MFL Blitz app icon" width="160">

## Product status

**0.6.3 (64) — installed and launched on the owner’s iPhone:** Compact mirrored scoring rows have equal tappable heights and centered points, following the supplied reference. Live players filters active-game starters; ownership appears in search and player Week details. Shorter stat labels retain all scoring values, and league abbreviations remain unchanged. Twenty-four native stat/game checks and four final normal/largest-text layout and TD journeys pass; build 63’s eleven ownership/search/timeline checks also pass. Phone readback confirms 64. See [delivery evidence](docs/current-status.md).

**0.6.3 (62) — installed and launched on the owner’s iPhone:** Matchup mode focuses on starters in active NFL games, with completed points and remaining players expandable. All seven approved review packages are implemented. Focused native tests, normal/largest-text mode restoration, shared player-detail journeys, search/tool flows, Live Activity render/OCR checks and 44 background-service tests pass. Phone readback confirms 62. Real notification delivery and manual VoiceOver/Always On validation remain pending. See [delivery evidence](docs/current-status.md).

**0.6.3 (61) — installed and launched on the owner’s iPhone:** The timeline uses a concise empty state and collapsed Recording details, with explanations behind an information button. Eight native checks and normal/largest-text timeline journeys pass; screenshots were inspected and phone readback confirms 61. The independent design review backlog is documented, not yet implemented. See [delivery evidence](docs/current-status.md).

**0.6.3 (60) — installed and launched on the owner’s iPhone:** Global search expands a field and results panel on the current page, with player Back preserving the query. The lineup-alert enable/relaunch crash is fixed. Focused controller/search tests and all six search UI journeys pass; normal and accessibility text layouts were inspected. Device readback confirms build 60. Physical alert connection/delivery confirmation remains pending. See [delivery evidence](docs/current-status.md).

**0.6.3 (56) — installed on the owner’s iPhone:** Matchup stat summaries include receiving/rushing touchdowns, turnovers, two-point conversions and other available scoring events without truncation. Fast NFL player polling is restricted to active games; final corrections slow down and completed boxes are archived after a week. The deployed cache policy and request ceiling are covered by regression tests. Automatic launch was blocked by the phone lock. See the [refresh design](docs/live-nfl-scoring.md) and [delivery evidence](docs/current-status.md).

**0.6.3 (55) — installed and launched on the owner’s iPhone:** Adds player box scores and actual NFL game clocks to scoring through a shared Hephaestus cache. Live fantasy/player scoring refreshes about once a minute, with immediate cached display and separate freshness receipts. The NFL service enforces a persistent 6,000-request daily ceiling below the Pro allowance, coalesces all users, and slows during budget pressure or failures. See the [refresh design](docs/live-nfl-scoring.md) and [current status](docs/current-status.md) for validation and limits.


**Installed private build 0.6.3 (52):** fixes the remaining artwork handoff: the phone and background server receive the exact prepared logos/colors, while newer scores retain that artwork. Installed and launched on Josh’s iPhone, with version 52 verified and both real logos/red-orange palettes retained through two subsequent background updates. All 35 focused native checks pass. See [current status](docs/current-status.md).

**Previous private build 0.6.3 (51):** Fixes Live Activity artwork resetting to blue, replaces activity records with live estimates, adds final-score confirmation and saved lifecycle diagnostics. The private service update is deployed and 77 native/server checks pass. Installed and launched on Josh’s iPhone; version 51 is verified and background scoring received the new projection inputs. The repeated disappearance’s exact cause remains unconfirmed. See [current status](docs/current-status.md).

**Previous private build 0.6.3 (50):** retains an existing Live Activity through incomplete refreshes and breaks between games, and adds Settings → Game day → Restart Live Activity with observed status. Installed and launched on the development iPhone. Background push updates are visibly reaching the phone; the reported disappearance’s exact cause and sustained stability remain under observation. Includes aligned owner/record rows, dynamic team estimates and the deployed server Unicode fix. See [background scoring](docs/background-scoring.md) and [verification status](docs/current-status.md).

**Previous private build 0.6.3 (46):** centers Live Activity scores over team names, moves logos into the header corners and uses stronger dominant colors with a soft transition. Sharper compact logos survive the full activity payload, with initials as the missing-artwork fallback. Installed and launched on the development iPhone; see [verification status](docs/current-status.md).

**Previous private build 0.6.3 (45):** adds current team records to Scores/matchup detail and an Apple Sports-inspired Live Activity with blended team logos/colors, larger actual scores and the latest observed scoring-change batch. Activity projections are removed. Background push updates remain the next step.

**Previous private build 0.6.3 (44):** Start on a full lineup now offers a legal swap; Replace → Move to bench recovers an overfilled draft. Replacement pickers keep player names readable at accessibility text sizes. See [lineup behavior](docs/lineup-starter-swaps.md) and [verification status](docs/current-status.md).

**Previous private build 0.6.3 (43):** adds reviewed player-ID pairs to the DEBUG-only [historical NFL stats test](docs/nfl-stats-service.md) backed by a private cached Hephaestus service, under My Team → Settings. Historical player → Review MFL player match offers candidates without auto-matching; saved pairs can be removed from Reviewed player matches. Free-plan stats testing is limited to 2022–2024, not 2026/live data; real player cards remain unchanged and MFL stays authoritative. Includes build 41's [scoring visual system](docs/scoring-visual-system.md), mirrored matchup halves, `ATL @ DAL` captions, contextual Week / Player detail and collapsed bench totals. Exact tests and phone-delivery status are in [current status](docs/current-status.md); TestFlight remains on hold.

**0.6.2 (39) — installed and launched on the owner’s dev iPhone:** adds [global player search](docs/player-search.md) to all five primary tabs and matchup detail. Cached local matching, direct owner/status results and independent ownership loading make quick player lookups possible; Back restores the query. All 235 app unit tests pass, plus five native search journeys on both iOS 18.4 and iOS 27. Owner game-week acceptance and manual accessibility/iPad checks remain. See [current status](docs/current-status.md) for exact evidence and source-delivery status.

**0.6.1 (38) — previous private build:** preserves the craft fixes and verifies lineup draft/review continuity through short landscape and portrait layouts. The project excludes three older duplicate source copies from compilation while preserving their files. The signed build and final rotation test pass; automatic launch was blocked by the phone lock. Actual Duo runtime qualification awaits iOS 27.1. See [adaptive validation](docs/adaptive-layout-validation.md).

**0.6.1 (37) — previous private build:** open Board messages survive summary refreshes with inline recovery; Scores uses a truthful owner-oriented projected margin and adaptive large text. Week selection uses league bounds and shows Scores/Lineup as each arrives. All 107 core and 224 app tests pass, with focused native recovery/navigation checks and inspected largest-text screenshots. Automatic launch was blocked by the phone lock; open Blitz after unlocking. See [behavior details](docs/craft-refinements.md) and [current status](docs/current-status.md) for precise evidence and remaining checks.

**0.6.0 (36) — previous private build, installed and launched on the owner's dev iPhone, merged in [PR #11](https://github.com/biggsjm/mfl-blitz-ios/pull/11):** player scoring rows add NFL opponent and localized kickoff in place of “Yet to play,” with Live/Final/Bye states and one time-zone caption. Existing weekly schedule caches are shared with Lineup and Player Detail; optional game info never blocks the scores. See [current status](docs/current-status.md) for verification and GitHub delivery.

**0.6.0 (35) — previous private build, merged in [PR #10](https://github.com/biggsjm/mfl-blitz-ios/pull/10):** adds Trading Block inside Trades, a League Calendar inside Schedule, opt-in deadline reminders, selected-event Apple Calendar handoff, and a current-matchup Live Activity. Owner feedback adds a Lineup-style block editor with roster promotion/demotion, pinned review/submit, explicit last-player removal and Settings relocated to My Team. Optional feeds reuse protected last-loaded content and stay outside startup. Live Activities update while Blitz is foregrounded and mark stale scores; no continuous-background push service is included. See the [implementation contract](docs/league-extras-implementation.md), [approved plan and remaining limits](docs/trading-block-calendar-plan.md), and [delivery evidence](docs/current-status.md).

**0.5.4 (32) — previous private build, merged in [PR #9](https://github.com/biggsjm/mfl-blitz-ios/pull/9):** fixes cancelled Scores requests appearing as failures and removes raw network diagnostics from transport-error messages. Existing scores remain visible; genuine errors and uncertain-write safeguards are retained. See [current status](docs/current-status.md) for exact checks and GitHub delivery status.

**Player cards, introduced through 0.5.4 (29–31), merged in [PR #8](https://github.com/biggsjm/mfl-blitz-ios/pull/8).** Redesigned Player Detail puts identity, season points/average and current roster/health status first, consolidates Week information, and adds a visible paged Week / Points / NFL opponent log. The opponent caveat lives behind an information button; biography loads separately when expanded. Drop is a labeled secondary action, not a bench control. Matchup owner names and single-stack player navigation are included. Josh confirmed build 30 fixes the stranded spinner. Build 31 shows identity from the tapped row before waiting for ownership, while Week metrics and research load independently; roster actions still require the completed status read. See [player design](docs/player-detail-ux.md) and [current status](docs/current-status.md) for exact verification and delivery evidence.

**Cached startup, introduced in 0.5.3 (28).** Returning users can see saved scores, lineup, standings, Board summaries and their roster while reconnecting. Startup prioritizes scores/lineup, persists protected daily league metadata and reuses a single player lookup index. The first successful download still seeds the cache; cached content cannot authorize changes. See the [performance review](docs/performance-startup.md) and [current status](docs/current-status.md) for precise test, installation and remaining-work evidence. The designer-reviewed [Lineup card](docs/lineup-projections.md), Schedule-first shortcuts and shared [standings pattern](docs/standings-pattern.md) remain. This is not a public or TestFlight release.

Connect mode talks directly to MFL and permits user-reviewed lineup, supported conditional blind-bid, trade, and board actions with readback and no automatic write retries. MFL does not expose saved lineup tiebreakers for confirmation; accepted trades may still need league approval/processing. **Preview Champion Hall** uses sample data and sends nothing to MFL, including its fictional trade offers.

Verification includes core fixtures, app-model regressions, native UI journeys and the two-week synthetic model scenarios—not two real game weeks or a human usability study. Exact current counts and device evidence are recorded in the status document. See [current status and known limits](docs/current-status.md), the [historical performance report](docs/two-week-synthetic-testing.md), and the [Week 1 checklist](docs/week-1-testing.md) before inviting the league.

The build additionally includes official injury/kickoff/bye context, a game log that loads on opening a player with older weeks on request, a synced watchlist, reviewed native FCFS add/drop and IR moves. See the [approved feature plan and later queue](docs/player-tools-plan.md). Roster writes require explicit owner capabilities and a supported format; unknown/closed states use MFL. Move to IR is hidden on Player Detail and omitted from the eligible IR list without a current Out/IR designation. Star toggles sync immediately and are read back for confirmation. Ordinary browsing reuses caches; pull-to-refresh reloads only the visible main section. MFL cooldowns remain enforced per server without moving requests to another host or retrying failed imports.

The app includes:

- a scores-first game-day dashboard with the user's matchup featured, current team records in the featured and detail cards, and tappable position-by-position live scoring for every matchup;
- a tap- and swipe-accessible lineup editor with league-aware bench/starter/FLEX replacements and rotations, [projected margin against that week's opponent](docs/lineup-projections.md), validation, review, and saved-starter receipts;
- explicit Week N calendar controls on Scores and Lineup, Settings at the upper left of My Team, and an original crossing-play-route Lineup icon;
- an ordered conditional-FAAB queue with search, useful sorting, bid/drop editing, budget checks, reordering, and explicit full-queue confirmation;
- a native My Team tab with franchise logo/initials, contextual division/league standing, six direct [Schedule-first shortcuts](docs/my-team-shortcuts.md), and a position-grouped roster sorted by season-to-date fantasy points; trade attention badges remain visible;
- [global player search](docs/player-search.md) from every primary tab and matchup detail, with local cached matching, fantasy-team/owner/status in results, recent players and preserved Search → Player → Back;
- shared player details with identity, current ownership, available matching-week metrics and optional biography, linked from search, rosters, Lineup and matchup cells;
- team and league season timelines with published opponents, configured week bounds, clear future/playoff states and matchup browsing that preserves lineup edits and the selected week;
- direct Adds / Drops, Trades and League Activity pages inside My Team; native player/pick/FAAB offers, acceptance, decline, withdrawal, and explicitly separate counteroffers;
- a prominent Create trade / Resume trade action, Cancel with draft rollback, Save & close disabled for blank drafts, exact two-sided review, fresh ownership checks, and restart-safe protection against repeating an unconfirmed trade action;
- Trading Block listings, owner-scoped player/pick publication with readback, a separate resumable draft, and Make offer with existing-offer-draft protection;
- Matchups / Calendar modes under Schedule, verified MFL recurring dates, explicit reminder opt-in and one-time event handoff to Apple's editor;
- an on-device Lock Screen / Dynamic Island matchup activity with team logos, a blended team-color background, large scores, records and the latest observed scoring change, with freshness and foreground-update limits made explicit;
- division and overall standings with MFL owner names and supported league-configured tiebreakers; missing/ambiguous places stay blank and MFL's report remains authoritative for custom orders;
- league team artwork in scores, matchup details, and standings, with initials as an offline/missing-image fallback;
- the existing MFL message board presented as readable native threads, with compose and reply flows;
- a no-account interactive preview for Champion Hall;
- one foreground-only scoreboard/detail poller, foreground refresh, and official completed-week result reconciliation;
- MFL/Fantasy Sharks league-scored weekly projections, with missing values shown explicitly;
- MFL current/lineup-week guidance, Keychain session restoration, and team-scoped lineup, waiver-queue, and board drafts;
- explicit partial-round waiver recovery, cancellation of all saved bids, and persistent duplicate-post protection;
- saved-screen presentation during reconnection and offline recovery, plus scores/lineup-first fresh loading after account verification;
- one shared, persistent 24-hour public player directory, with separate freshness limits for stable league settings, displayed balances, and submission checks;
- adaptive iPhone/iPad layouts, light/dark appearance, Dynamic Type, VoiceOver summaries, non-gesture actions, and Reduce Motion; the full manual accessibility/device audit remains a release gate;
- no ads, analytics SDK, cross-app tracking, or proprietary chat network.

## What is next

**Optional NFL statistics:** API-NFL Pro is active through October 14, 2026, following the approved $15 prepaid month with no automatic renewal. Hephaestus's existing key successfully retrieves a completed 2026 game and player breakdown. Build 55 connects a separate shared current-season feed to normal scoring. The historical test remains isolated; live-game timing still needs observation during play. See the [service contract and remaining plan](docs/nfl-stats-service.md) and [exact validation/phone status](docs/current-status.md).

Josh will validate Week 1 on his development device. TestFlight is intentionally on hold until iOS 27 and macOS 27 are both out of beta, followed by the existing release gates and Josh's approval; the earlier Week 2 invitation deadline is superseded. The approved [Trading Block, Calendar, reminders and Live Activity increment](docs/trading-block-calendar-plan.md) is implemented for development-device validation; current status distinguishes tests, installation and owner acceptance. Josh confirmed build 35's last-player trading-block removal works on MFL September 7. Broader game-week checks remain open. New cash listings remain on MFL. The optional private background Live Activity service is approved and activated for the development phone; distribution and broader game-week verification remain separate.

**My Team, schedules and player tools 1–5 are implemented**. Tabs are Scores / Lineup / My Team / Standings / Board. Polls and playoff brackets remain queued after this increment. Complete supported-device/accessibility and real game-week validation remain. Global player search now opens a shared sheet from the existing tabs; no extra Players tab is introduced. Adds / Drops keeps its task-specific search. See the [remaining execution plan](docs/roadmap.md).

## Why this app

The September 5, 2026 [research snapshot](docs/competitive-review.md) informed the focus on reliability and clarity. It is not a continuously updated market comparison:

- Make deadline-sensitive actions easy to find and review.
- Keep league rules, freshness, ambiguous outcomes, and missing data honest.
- Use the league's existing conversations, native controls, and privacy-preserving storage.

The product intent is to keep core league actions free and open. No subscription system is implemented.

See [the competitive review](docs/competitive-review.md) and [product brief](docs/product-brief.md).

## Architecture

```text
SwiftUI features
    ↓ view data + explicit user intents
AppModel / TransactionsModel / scoped browse models
    ↓
MFLCore (local Swift package)
    ├── authenticated account/franchise mapping + host discovery
    ├── HTTPS login + device-only Keychain session-cookie authorization
    ├── tolerant DTO decoding + body-level error checks
    ├── request spacing + response caching
    └── lineup, waiver, trade, trading-block, board, watchlist, FCFS and IR imports

App-owned storage
    ├── device-only Keychain: session, scoped drafts/markers, optional block/calendar snapshots and reminder preferences
    ├── daily public player disk cache + shared decoded lookup index
    ├── protected, non-backed-up league metadata and display snapshot caches
    ├── other private response caches and isolated artwork thumbnails: memory only
    └── system notifications / ActivityKit: minimal opted-in deadline and matchup display payloads
```

The local package isolates MFL's legacy wire format from the UI. IDs remain strings, API errors are detected even inside HTTP 200 responses, league hosts are resolved per session, and writes are never blindly retried. Sessions restore from the device-only Keychain after fresh membership verification. Lineup, waiver, board, and trade drafts survive a restart and are isolated by season, league, and franchise. Refreshes preserve drafts and surface conflicts rather than silently overwriting them. The app owns reviewed mutation workflows, secure storage, and readback; there is no MFL Blitz backend.

Read [API integration notes](docs/api-integration.md) for endpoint details and risks.

## Open and run

Requirements:

- An Xcode toolchain supporting Swift 6 and the iOS 18 deployment target
- macOS 15 or later for package tests

Latest local verification used **Xcode 27 beta with iOS 27 / iPhone 17 Pro and iOS 18.4 / iPhone 16 Pro simulators**. This is not evidence that every supported OS/device has been manually validated. GitHub CI uses the older Xcode 16.4 / iOS 18.5 environment on `macos-15`; see current status for exact passing revisions and counts.

1. Open `MFLBlitz.xcodeproj`.
2. Select the `MFLBlitz` scheme and an iPhone or iPad simulator.
3. Run the app and choose **Preview Champion Hall**.
4. Run core tests from Terminal:

   ```sh
   swift test --package-path Packages/MFLCore
   ```

5. Find an installed simulator with `xcodebuild -showdestinations -project MFLBlitz.xcodeproj -scheme MFLBlitz`. Run the app/UI suites serially with Xcode, or:

   ```sh
   xcodebuild test -project MFLBlitz.xcodeproj -scheme MFLBlitz \
     -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
     -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
   ```

Do not run overlapping jobs on one simulator. See [contributing](CONTRIBUTING.md) for test scope and safe fixtures.

## Documentation

| Document | Purpose |
| --- | --- |
| [Current status](docs/current-status.md) | Shipped build, evidence, known limits and release gates |
| [Startup performance](docs/performance-startup.md) | Cached launch, request ordering, storage boundaries, measurements and follow-ups |
| [Player tools 1–5](docs/player-tools-plan.md) | Approved availability, research, watchlist, add/drop and IR plan; later features |
| [Roadmap](docs/roadmap.md) / [Changelog](CHANGELOG.md) | Remaining execution plan / implemented release history |
| [Product brief](docs/product-brief.md) | Priorities, current navigation and design principles |
| [API integration](docs/api-integration.md) / [MFLCore](Packages/MFLCore/README.md) | Endpoints, cache policies, implementation boundaries |
| [Week 1 testing](docs/week-1-testing.md) / [Synthetic report](docs/two-week-synthetic-testing.md) | Live checklist / historical automated evidence |
| [Lineup swaps](docs/lineup-starter-swaps.md) / [Trade inbox](docs/trade-inbox-ux.md) | Shipped interaction contracts and regressions |
| [Board drafts](docs/board-drafts.md) | Close/save/discard and visible draft recovery |
| [Schedule](docs/schedule-ux.md) / [Player and team detail](docs/player-detail-ux.md) | Implemented first slice, data/state contracts and remaining enrichment |
| [Competitive research](docs/competitive-review.md) / [Icon brief](docs/icon-brief.md) | Dated research and artwork rationale |
| [Privacy](PRIVACY.md) / [Security](SECURITY.md) / [Contributing](CONTRIBUTING.md) | Data handling, safe reporting and development workflow |

## API configuration before distribution

MFL monitors and throttles API clients. Before a public/TestFlight build:

1. Register a client on MFL's API Client Registration page.
2. Set the exact registered User-Agent in the transport configuration. The app currently supplies `MFL Blitz/0.1 (com.biggsjm.MFLBlitz)`; registration of that string is not confirmed.
3. Verify every import call in a disposable test league.
4. Complete the [release gates](docs/roadmap.md) and configuration coverage for the advertised supported scope; do not imply all MFL formats are validated.

Do not put MFL credentials, session cookies, private message content, trade terms, or blind-bid amounts in logs, fixtures, issues, or screenshots. Automated tests use synthetic data.

See the repository's [privacy policy](PRIVACY.md) for the data flow and deletion behavior.

## Independence and trademarks

MFL Blitz is an independent client and is not affiliated with or endorsed by MyFantasyLeague, First Pick Labs, the NFL, any NFL team, or the NFLPA. “MyFantasyLeague” and “MFL” may be trademarks of their respective owners. The app icon is original and contains no league or team marks.

## License

[MIT](LICENSE)
