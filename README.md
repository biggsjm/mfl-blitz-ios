# MFL Blitz

> Deep enough for MFL. Calm enough for Sunday.

MFL Blitz is an independent, native SwiftUI companion for [MyFantasyLeague](https://www.myfantasyleague.com/). It puts the deadline-sensitive things first: scores, lineups, transactions, standings, and the league message board.

<img src="docs/app-icon-source.png" alt="MFL Blitz app icon" width="160">

## Product status

**In verification: 0.5.2 (21)** — symbol-only Add/Drop, eligible-only IR, consistent immediate-add gating, and My Team's standing/navigation-card/position-roster redesign with actual season points. The installed baseline remains below until [current status](docs/current-status.md) records delivery.

**0.5.1 (20) — installed private build, September 6, 2026.** Build 20 installed and launched on Josh's iPhone, adding player tools and addressing the owner's IR eligibility and rate-limit feedback. This is not a public or TestFlight release. See [current status](docs/current-status.md) for the verified code, test and device baseline.

Connect mode talks directly to MFL and permits user-reviewed lineup, supported conditional blind-bid, trade, and board actions with readback and no automatic write retries. MFL does not expose saved lineup tiebreakers for confirmation; accepted trades may still need league approval/processing. **Preview Champion Hall** uses sample data and sends nothing to MFL, including its fictional trade offers.

Verification includes core fixtures, app-model regressions, native UI journeys and the two-week synthetic model scenarios—not two real game weeks or a human usability study. Exact current counts and device evidence are recorded in the status document. See [current status and known limits](docs/current-status.md), the [historical performance report](docs/two-week-synthetic-testing.md), and the [Week 1 checklist](docs/week-1-testing.md) before inviting the league.

The build additionally includes official injury/kickoff/bye context, on-demand progressive fantasy scoring history, a synced watchlist, reviewed native FCFS add/drop and IR moves. See the [approved feature plan and later queue](docs/player-tools-plan.md). Roster writes require explicit owner capabilities and a supported format; unknown/closed states use MFL. Move to IR remains disabled without a current Out/IR designation. Star toggles sync immediately and are read back for confirmation. Ordinary browsing reuses caches; pull-to-refresh reloads only the visible main section. MFL cooldowns remain enforced per server without moving requests to another host or retrying failed imports.

The app includes:

- a scores-first game-day dashboard with the user's matchup featured and tappable position-by-position live scoring for every matchup;
- a tap- and swipe-accessible lineup editor with league-aware bench/starter/FLEX replacements and rotations, projections, validation, review, and saved-starter receipts;
- explicit Week N calendar controls on Scores and Lineup, Settings at the upper left of Scores, and an original crossing-play-route Lineup icon;
- an ordered conditional-FAAB queue with search, useful sorting, bid/drop editing, budget checks, reordering, and explicit full-queue confirmation;
- a native My Team tab with your franchise logo/initials, roster, schedule and watchlist, with a separate Manage roster workflow, plus a prominent Transactions entry and trade attention badge;
- shared player details with identity, current ownership, available matching-week metrics and optional biography, linked from rosters, Lineup and matchup cells;
- team and league season timelines with published opponents, configured week bounds, clear future/playoff states and matchup browsing that preserves lineup edits and the selected week;
- a Transactions hub inside My Team with Waivers, Trades, and Activity; native player/pick/FAAB offers, acceptance, decline, withdrawal, and explicitly separate counteroffers;
- a prominent Create trade / Resume trade action, Cancel with draft rollback, Save & close disabled for blank drafts, exact two-sided review, fresh ownership checks, and restart-safe protection against repeating an unconfirmed trade action;
- division and overall standings with owner names from MFL that preserve its official ordering;
- league team artwork in scores, matchup details, and standings, with initials as an offline/missing-image fallback;
- the existing MFL message board presented as readable native threads, with compose and reply flows;
- a no-account interactive preview for Champion Hall;
- one foreground-only scoreboard/detail poller, foreground refresh, and official completed-week result reconciliation;
- MFL/Fantasy Sharks league-scored weekly projections, with missing values shown explicitly;
- MFL current/lineup-week guidance, Keychain session restoration, and team-scoped lineup, waiver-queue, and board drafts;
- explicit partial-round waiver recovery, cancellation of all saved bids, and persistent duplicate-post protection;
- independent tab loading after account verification, plus bounded/cancellable session reconnection;
- one shared, persistent 24-hour public player directory, with separate freshness limits for stable league settings, displayed balances, and submission checks;
- adaptive iPhone/iPad layouts, light/dark appearance, Dynamic Type, VoiceOver summaries, non-gesture actions, and Reduce Motion; the full manual accessibility/device audit remains a release gate;
- no ads, analytics SDK, cross-app tracking, or proprietary chat network.

## What is next

First: owner-led live Week 1 validation, MFL client registration/User-Agent confirmation, accessibility/device checks, and Apple/TestFlight preparation. Week 2 invitations depend on those gates, not just automated tests.

**My Team, schedules and player tools 1–5 are implemented**. Tabs are Scores / Lineup / My Team / Standings / Board. The next approved queue is trading block, calendar/reminders, polls and playoff brackets. Complete supported-device/accessibility and real game-week validation remain. Existing waiver search is reused; there is no extra Players tab or new global search destination. See the [remaining execution plan](docs/roadmap.md).

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
    └── lineup, waiver, trade, board, watchlist, FCFS and IR imports

App-owned storage
    ├── device-only Keychain: session, scoped drafts, unconfirmed-action markers
    ├── daily public player disk cache + decoded memory reuse
    └── private response caches and isolated artwork thumbnails: memory only
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
