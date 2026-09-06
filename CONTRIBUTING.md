# Contributing

Use a toolchain supporting Swift 6, iOS 18 and macOS 15 package tests. The current local verification used Xcode 27 beta/iOS 27; CI uses `macos-15`. Deployment targets are not a claim of manual verification on every OS. Keep the app dependency-light, native, accessible and configuration-driven.

Before a pull request, run the relevant suites and record the actual scope:

```sh
swift test --package-path Packages/MFLCore
xcodebuild build -project MFLBlitz.xcodeproj -scheme MFLBlitz -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild -showdestinations -project MFLBlitz.xcodeproj -scheme MFLBlitz
xcodebuild test -project MFLBlitz.xcodeproj -scheme MFLBlitz \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

Replace the destination with an installed simulator. Run simulator jobs serially and coordinate the build/install owner when multiple tasks share a checkout. If stale build metadata prevents package signing, use a new temporary `--scratch-path` instead of deleting unrelated build data. A compiler/runner failure is not a passing test. Core tests do not replace app/UI, manual accessibility or live-owner validation.

## Safety and regressions

- Never commit credentials, cookies, private league content, real bid/trade values or raw authenticated payloads. Use synthetic fixtures and scoped staging; preserve other tasks' uncommitted work.
- Give every new MFL response shape a sanitized decoder fixture/test. Every mutation change needs stale-preflight and ambiguous-outcome coverage and must not add blind retry.
- Automated UI final-action journeys must explicitly enter and verify offline preview first. No real lineup, waiver, trade or board mutation is a smoke test; live checks require the owner's intended action and consenting participants where relevant.
- Sheet/modal changes must test the very first action and close/reopen behavior, not just model state. Preserve identifiable trade action payloads, explicit view identity, Cancel rollback and late-autosave guards.
- Keep browsing routes separate from the active lineup week/draft. Player identity taps must not replace Start/Replace/Add/Select actions.
- My Team regressions live in `MyTeamNavigationTests`, `TeamPlayerDetailTests`, `SchedulePresentationTests` and MFLCore `ScheduleTests`. Run native roster/player/current-future schedule journeys as well as the existing lineup/trade suite when changing shared routes. Keep whole-season schedule reads shared; do not fan out player scoring for every week.
- Validate large text, VoiceOver labels/action separation, light/dark appearance and native navigation after UI changes. Record incomplete manual checks honestly.

## Documentation and releases

Update [current status](docs/current-status.md), [roadmap](docs/roadmap.md), [changelog](CHANGELOG.md), README and affected API/UX/test/privacy documents when behavior changes. Keep one clear installed baseline and distinguish implemented, automated-tested, owner-observed, unvalidated and proposed work. Historical reports retain their original versions/counts; link newer evidence instead of rewriting history. Never equate synthetic weeks with real elapsed weeks or a human study.

New data sources/storage/permissions require corresponding privacy/security documentation. Check local Markdown links and `git diff --check`. Documentation-only changes do not need an app version bump or phone reinstall. Agree file ownership before editing shared navigation or another task's design doc, and publish/merge only when the user authorizes that workflow.
