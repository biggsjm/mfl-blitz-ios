# MFL Blitz

> Deep enough for MFL. Calm enough for Sunday.

MFL Blitz is an independent, native SwiftUI companion for [MyFantasyLeague](https://www.myfantasyleague.com/). It puts the deadline-sensitive things first: scores, lineups, conditional blind-bid waivers, standings, and the league message board.

<img src="docs/app-icon-source.png" alt="MFL Blitz app icon" width="160">

## Product status

This repository contains a polished, runnable product prototype and a tested MFL API foundation. The app includes an interactive **Champion Hall** preview based on league `41333`; connect mode uses MFL's direct-device API architecture. Live lineup editing and submission are enabled with explicit review and exact saved-starter verification. MFL accepts lineup tiebreakers but does not expose their saved state for readback. Non-transactional waiver replacement and message-board writes remain gated while those paths are validated across MFL configurations.

The current build includes:

- a scores-first game-day dashboard with the user's matchup featured;
- a tap- and swipe-accessible lineup editor with lock, injury, deadline, projection, validation, review, and receipt states;
- an ordered conditional-FAAB queue with search, useful sorting, bid/drop editing, budget checks, reordering, and explicit full-queue confirmation;
- division and overall standings that preserve MFL's official ordering;
- the existing MFL message board presented as readable native threads, with compose and reply flows;
- a no-account interactive preview for Champion Hall;
- iPhone, iPad, dark mode, Dynamic Type, VoiceOver summaries, Reduce Motion, and 44-point controls;
- no ads, analytics SDK, cross-app tracking, or proprietary chat network.

## Why this app

The incumbents are feature-rich, but the opportunity is reliability and clarity—not another checklist:

- [MFL Mobile](https://apps.apple.com/us/app/mfl-mobile-myfantasyleague/id639397317) has broad coverage and a large rating base, while current reviews still identify weak waiver sorting and an interface behind newer fantasy platforms.
- [MFL Platinum](https://apps.apple.com/us/app/mfl-platinum/id452910130) handles unusual league formats well, but its rating and review history point to navigation and draft-flow friction.
- [MFL Modern](https://apps.apple.com/us/app/mfl-modern/id6751516222) looks newer, but has a very small validation base and user reports of stale or configuration-sensitive data.
- [MFL Live](https://apps.apple.com/us/app/mfl-live/id6670762804) is focused, but does not cover the full set of requested waiver and board workflows.
- MFL Pro is an ambitious 2026 newcomer with Live Activities and commissioner tooling, but writes are subscription-gated and it is currently iPhone-only in indexed storefronts.

MFL Blitz differentiates on server-confirmed actions, transparent freshness, rule-driven validation, accessibility, iPad support, privacy, and keeping core league actions free and open.

See [the competitive review](docs/competitive-review.md) and [product brief](docs/product-brief.md).

## Architecture

```text
SwiftUI features
    ↓ view data + explicit user intents
AppModel / repository boundary
    ↓
MFLCore (local Swift package)
    ├── authenticated account/franchise mapping + host discovery
    ├── HTTPS login + in-memory session-cookie authorization
    ├── tolerant DTO decoding + body-level error checks
    ├── request spacing + response caching
    └── lineup, waiver, and message-board imports
```

The local package isolates MFL's legacy wire format from the UI. IDs remain strings, API errors are detected even inside HTTP 200 responses, league hosts are resolved per session, and writes are never blindly retried. Version 0.1 intentionally does not persist the MFL session: closing the app requires signing in again.

Read [API integration notes](docs/api-integration.md) for endpoint details and risks.

## Open and run

Requirements:

- Xcode 16 or later
- iOS 18 or later deployment target
- macOS 15 or later for package tests

1. Open `MFLBlitz.xcodeproj`.
2. Select the `MFLBlitz` scheme and an iPhone or iPad simulator.
3. Run the app and choose **Preview Champion Hall**.
4. Run core tests from Terminal:

   ```sh
   swift test --package-path Packages/MFLCore
   ```

5. Run the app and UI suites with Xcode, or:

   ```sh
   xcodebuild test -project MFLBlitz.xcodeproj -scheme MFLBlitz -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
   ```

## API configuration before distribution

MFL monitors and throttles API clients. Before a public/TestFlight build:

1. Register a client on MFL's API Client Registration page.
2. Set the exact registered User-Agent in the transport configuration.
3. Verify every import call in a disposable test league.
4. Complete the configuration matrix in [the roadmap](docs/roadmap.md).

Do not put MFL credentials, session cookies, private message content, or blind-bid amounts in logs, fixtures, issues, or screenshots.

See the repository's [privacy policy](PRIVACY.md) for the data flow and deletion behavior.

## Independence and trademarks

MFL Blitz is an independent client and is not affiliated with or endorsed by MyFantasyLeague, First Pick Labs, the NFL, any NFL team, or the NFLPA. “MyFantasyLeague” and “MFL” may be trademarks of their respective owners. The app icon is original and contains no league or team marks.

## License

[MIT](LICENSE)
