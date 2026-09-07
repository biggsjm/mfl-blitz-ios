# Contributing

Use a toolchain supporting Swift 6, iOS 18 and macOS 15 package tests. The current local verification used Xcode 27 beta/iOS 27; CI uses `macos-15`. Deployment targets are not a claim of manual verification on every OS. Keep the app dependency-light, native, accessible and configuration-driven.

Before a pull request, run the relevant suites and record the actual scope:

```sh
swift test --package-path Packages/MFLCore
xcodebuild build -project MFLBlitz.xcodeproj -scheme MFLBlitz -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild -showdestinations -project MFLBlitz.xcodeproj -scheme MFLBlitz
xcodebuild test -project MFLBlitz.xcodeproj -scheme MFLBlitz \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO
```

Replace the destination with an installed simulator. Run jobs against the same simulator or DerivedData directory serially; independent simulators may run in parallel with separate DerivedData paths. Coordinate the build/install owner when multiple tasks share a checkout. If stale build metadata prevents package signing, use a new temporary `--scratch-path` instead of deleting unrelated build data. A compiler/runner failure is not a passing test. Core tests do not replace app/UI, manual accessibility or live-owner validation.

## Safety and regressions

- Never commit credentials, cookies, private league content, real bid/trade values or raw authenticated payloads. Use synthetic fixtures and scoped staging; preserve other tasks' uncommitted work.
- Give every new MFL response shape a sanitized decoder fixture/test. Every mutation change needs stale-preflight and ambiguous-outcome coverage and must not add blind retry.
- Automated UI final-action journeys must explicitly enter and verify offline preview first. No real lineup, waiver, trade, board, watchlist or roster mutation is a smoke test; live checks require the owner's intended action and consenting participants where relevant.
- Sheet/modal changes must test the very first action and close/reopen behavior, not just model state. Preserve identifiable trade action payloads, explicit view identity, Cancel rollback and late-autosave guards.
- After dismissing an alert or composer, await its disappearance and the destination control's actual interactive state before tapping. Scope Back queries to the active navigation bar instead of a global first match. Use bounded state expectations, not fixed sleeps or removed assertions; the iOS 18 trade/Board timing regressions in build 27 demonstrate why.
- Keep browsing routes separate from the active lineup week/draft. Player identity taps must not replace Start/Replace/Add/Select actions.
- My Team regressions live in `MyTeamNavigationTests`, `TeamPlayerDetailTests`, `SchedulePresentationTests` and MFLCore `ScheduleTests`. Run native roster/player/current-future schedule journeys as well as the existing lineup/trade suite when changing shared routes. Keep whole-season schedule reads shared; do not fan out player scoring for every week.
- Validate large text, VoiceOver labels/action separation, light/dark appearance and native navigation after UI changes. Record incomplete manual checks honestly.
- Standings regressions live in core `StandingsRankingTests`, app `MyTeamNavigationTests`/`MutationRecoveryTests` and native standings journeys. Never infer rank from franchise-array position or ties from matching records alone. Test missing criteria, H2H cycles, division identity, scope-specific places, no-results state and cached-read counts. Ranked Preview launch flags must never affect a live repository.

Player-tools regressions live in core `PlayerToolsTests`, app `PlayerToolsSafetyTests` and native `PlayerToolsUITests`. Roster DTOs may retain legacy read defaults, but write preflight requires explicit statuses. Do not broaden ability matching to descriptions/substrings; use exact owner-scoped IDs. Keep FCFS player locks distinct from lineup locks. Preserve the device-only markers before POST and never replay uncertain imports.

Player-card regression coverage also checks typed live-matchup → player → single Back navigation, usable pushed team shortcuts, static own-team status, action-menu first selection/close/reopen, and game-log information/biography disclosure. Primary YTD/AVG reads must not wait for history. Reuse the shared cookie-free `nflSchedule(W=ALL)` cache; historical opponents are explicitly the current-team approximation approved by the owner, not verified historical NFL affiliation. Never add raw NFL stat scraping to fill this licensed-data gap.

Optional biography must not hold the primary identity/ownership read; fetch it on disclosure and reuse its cache. Shared availability requests must survive the initiating view's cancellation, join concurrent readers, clear interrupted-attempt suppression and reject old-scope results after reset. Cover these behaviors with deterministic suspended loaders, not live-network timing assertions.

Xcode 16.4 / iOS 18.5 can report no accessibility hit point for a visible native toolbar Menu. A measured native touch is acceptable only after asserting the target is wholly inside the visible navigation bar; retain all assertions for the menu's actual actions and reviewed outcomes. Dismiss information popovers with an outside touch, not a semantic tap on a non-actionable title. This is a test-runner accommodation, not permission to bypass disabled controls or invoke app actions directly.

Player-route identity previews are display-only: reject a mismatched ID or active scope, do not infer ownership/eligibility, and keep actions disabled until detail is loaded. The DEBUG-only `--synthetic-slow-player` flag affects DemoLeagueRepository after explicitly entering offline Preview; it holds ownership for 20 seconds so native tests can prove identity/Week content renders first. Never include this flag in phone delivery or treat synthetic timing as a live-network benchmark.

## Documentation and releases

League-extras regressions live in core `LeagueExtrasTests`, app `LeagueExtrasSafetyTests` and native `LeagueExtrasUITests`. Cover empty/singleton/malformed blocks, exact camel-case wire keys, ownership/baseline conflicts, uncertain publication/readback without replay, original cache age and account isolation. Calendar tests must cross-validate JSON/ICS UTC anchors, explicit DST instances and stable occurrence identity despite regenerated ICS UIDs. Do not guess RRULE/time zones or commit the owner's exports.

Reminder tests cover future-only absolute triggers, the 14-day/32-alert budget, overrides, stale reads, permission denial, failed preference restoration and disconnect. Native Preview must never request OS notification permission or create an actual notification/calendar event. The app embeds `MFLBlitzLiveActivity.appex`; shared attributes must compile in both targets, remain small and contain no credentials. Test fresh current-week playing-starter eligibility and explicit staleness; compilation/model tests are not evidence of real game-day Lock Screen delivery. No background timer or APNs token should be introduced without an approved service/privacy plan.

Scores cancellation regressions live in `ReliabilityTests` and core `RefreshCoordinationTests`. Cover Swift cancellation, URLSession `URLError.cancelled`/bridged NSError, cancelled caller tasks, manual and silent refresh, preserved existing warnings, immediate retry and foreground recovery. Cancellation classification must use types/domain/code, not error prose. Never expose full NSError diagnostics or authenticated URLs. Read-only cancellation handling must not discard uncertain mutation markers or replay a cancelled import. Verify Swift Testing filters actually execute tests; a zero-test invocation is not a pass.

Startup/cache regressions live in `StartupCacheTests`, `ScoringAndCacheTests` and core `PersistentCacheTests`. Test display-before-auth, verified-auth-but-stale-lineup, offline/retry, expiry, account isolation, original age, write invalidation and initial request budgets. Never turn cached display into permissions or write preflight. File I/O/encoding belongs on cache actors, not SwiftUI body evaluation.

`--synthetic-cached-startup` and optional `--synthetic-startup-offline` are DEBUG-only native test fixtures with a separate synthetic store and no live network/Keychain. Do not use these flags for phone delivery or represent their timings as real account/network measurements. See [performance evidence](docs/performance-startup.md).

Update [current status](docs/current-status.md), [roadmap](docs/roadmap.md), [changelog](CHANGELOG.md), README and affected API/UX/test/privacy documents when behavior changes. Keep one clear installed baseline and distinguish implemented, automated-tested, owner-observed, unvalidated and proposed work. Historical reports retain their original versions/counts; link newer evidence instead of rewriting history. Never equate synthetic weeks with real elapsed weeks or a human study.

New data sources/storage/permissions require corresponding privacy/security documentation. Check local Markdown links and `git diff --check`. Documentation-only changes do not need an app version bump or phone reinstall. Agree file ownership before editing shared navigation or another task's design doc, and publish/merge only when the user authorizes that workflow.
