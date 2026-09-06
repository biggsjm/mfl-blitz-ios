# Contributing

Use Xcode 16 or later and Swift 6. Keep the app dependency-light, native, accessible, and configuration-driven.

Before a pull request:

```sh
swift test --package-path Packages/MFLCore
xcodebuild build -project MFLBlitz.xcodeproj -scheme MFLBlitz -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Do not commit credentials, cookies, private league content, bid values, or raw authenticated payloads. Every new MFL response shape should receive a sanitized fixture and decoder test. Every mutation change needs an ambiguous-outcome test and must not add blind automatic retry.
