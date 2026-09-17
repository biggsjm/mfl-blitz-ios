# MFL Blitz 0.7.0 (68) — closed league TestFlight

Build 68 adds a smoother saved-login launch, relevant first/last-name search and keyboard/outside-tap dismissal. It is available to Owner Testing and **Waiting for Review** for the 12 existing Champion Hall Owners testers, with automatic notification enabled. Build 67's pending review was withdrawn in favor of build 68. See [current status](current-status.md) for verified delivery; installation of build 68 on a phone is not yet verified.

Build 68 retains build 67's automatic league services for invited owners. Build 67 was installed through the owner TestFlight group; automatic phone enrollment and production lineup registration were confirmed. Visible production notification delivery remains to be tested. See [current status](current-status.md). Build 66 is the earlier owner-only private-service build.

## Tester setup

1. On an iPhone running iOS 18 or later, install Apple's TestFlight app and accept the emailed invitation once Apple approves the beta.
2. Install build 68 or newer. Connect using your own MFL account and team. Co-owners sign in independently.
3. Enhanced NFL stats and background scoring connect automatically. No access code, Tailscale app or server address is needed.
4. For optional lineup alerts, open Lineup's toolbar bell, choose alerts and allow iOS notifications. Live Activity preferences remain in My Team → Settings.

League changes affect the actual MFL league. The interactive preview uses synthetic data and sends no real transactions or pushes.

## What to test

- Cold launch with a saved login: open Scores without a flash of the welcome screen.
- Search first/last names such as Mason and Hunter; exact names lead, with your roster and other rostered players prioritized within equally good matches.
- Hide the search keyboard with Done or scrolling, tap outside to close search, and return from player details to the same query.
- Scores, player stats, Live Activity handoff and foreground score freshness.
- Roster browsing, search, standings and switching tabs; no cancellation alert should appear when leaving a tab.
- Compact lineup checks and alert settings, initial notification permission and returning from iOS Settings.
- Automatic League services connection on Wi-Fi and cellular, without Tailscale, including both co-owners.
- Pending trades moving into retained History, saved sessions/drafts after reopening, and league week rollover.

A missing pending trade is labeled Closed unless its outcome is confirmed. History starts with offers the app observes; it cannot recover previously vanished offers. Accepted means MFL acknowledged acceptance, not necessarily completed league processing. Background trade push alerts are not included.

## Release operations

Use the existing app and testing groups. The closed external group contains 12 invited addresses; initial instructions were emailed. No public TestFlight link or developer staff roles are needed. The [automatic-access runbook](league-beta-access.md) describes private team configuration, independent device credentials, request budgets, revocation and migration. Do not email manual codes or share an owner's MFL credentials.

Archive a clean reviewed revision with `scripts/archive_testflight.sh`, setting both `MFL_BACKGROUND_SYNC_URL` and `NFL_SCORING_URL` to the deployed authenticated gateway. On this Mac use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; stable Xcode 27 (27A266a) is accepted by Apple, while the older beta toolchain was rejected. The script archives only tracked files to exclude unrelated synchronized duplicates. Export using `scripts/TestFlightExportOptions.plist` and validate the IPA with `scripts/verify_testflight_export.py`. Export and upload are separate steps. Xcode requires its own Apple Account login, independent of the App Store Connect browser session.

Production APNs signing is configured on the server. Never include signing keys or provider credentials in source, chat, settings or command arguments. Signed distribution profiles and signer readiness do not prove phone delivery. Verify upgrade, automatic team enrollment and actual Live Activity/lineup behavior on a TestFlight phone. Keep the canonical Hephaestus inventory current when service access or responsibilities change.

Privacy: [PRIVACY.md](../PRIVACY.md). Feedback: TestFlight or an established private contact; omit private league/account details from public issues.

## Historical build 66 qualification

- After account sign-in, the app record and Owner Testing internal group were created. The first signed export passed local validation but Apple rejected its old beta toolchain. The accepted artifact is `/tmp/mfl66-xcode27-export/MFLBlitz.ipa`, archived at `/tmp/MFLBlitz-66-Xcode27.xcarchive` with stable Xcode `27A266a` and SDK `24A430`. App source revision is `027aa802af5082086722ffec96f44111af38244d`; archive checkout is `92b5c26e85793300097105b85bcdf0f5482ad82c`. App/widget signature, distribution-profile, version, private endpoint, privacy-manifest and production push-entitlement checks pass. Upload succeeded at 11:20 CDT, Apple processing completed, and Josh was invited at 11:29 CDT. Phone installation remains unverified.
- Optimized unsigned Release archive succeeded at `/tmp/MFLBlitz-66-Unsigned.xcarchive`. It is compiler/bundle evidence only and cannot be uploaded as-is.
- Backend: 51 synthetic tests passed and changes were deployed to the existing service. With Josh's explicit approval, a production-only, Blitz-topic APNs key was securely installed; key/config and cooldown database are mode 0600. At 11:13:18 CDT, status returned HTTP 200, both sandbox and production ready, and no issue. No production delivery is claimed. Canonical inventory updated.
- Core: 115 tests passed, including HTTP-date cooldown handling. All 374 app tests and three native trade journeys passed. After the final storage safeguards, 29 focused app checks and the native history journey passed, including two new storage regressions. Details and artifact paths are in [current status](current-status.md).
- All six release CI jobs passed. After the toolchain update, 19 additional app/native UI smoke checks passed with no failures or runtime warnings in `/tmp/mfl66-xcode27-smoke.xcresult`.
- Encryption answer verified against the clean archive source, package configuration and linked frameworks: URLSession HTTPS, Security/Keychain/random APIs and CryptoKit hashing are provided by Apple; no bundled or custom encryption implementation was found. **None of the algorithms mentioned above** cleared Missing Compliance. [Apple's OS-encryption guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) informed the answer; revisit if dependencies/security behavior change.
