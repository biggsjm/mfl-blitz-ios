# MFL Blitz 0.7.0 (66) — personal TestFlight candidate

## Test information

MFL Blitz is an independent iPhone/iPad client for MyFantasyLeague. This private beta supports league scores, live NFL context, lineups, standings, team/player research and reviewed league transactions. An existing MFL account and league membership are required. The offline Champion Hall preview uses synthetic data.

**What to test:** roster browsing and switching tabs; leaving/reopening the app; manual refresh during an MFL cooldown; pending offers moving into trade History; league week rollover; Live Activities and opt-in lineup alerts. Account actions affect the actual MFL league. Trade responses require another consenting owner; do not submit throwaway offers, drops or waiver bids to a live league.

**Changes in this candidate:** foreground refreshes target the visible tab; My Team checks pending offers without loading every team's tradable assets; trade History retains terms and an unread outcome indicator; original score fetch times survive backend caching; request pacing and MFL cooldowns are shared by existing background consumers. The build also includes the build 65 standings/tiebreaker fix.

**Known limitations:** a missing pending offer is labeled Closed unless the outcome was confirmed. There are no background trade push notifications. History starts with offers this version observes; it cannot recover previously vanished offers. Accepted means MFL acknowledged acceptance, not necessarily completed league processing. NFL enrichment and background registration currently require the owner's private Tailscale access. Production push delivery is not verified until a real TestFlight install succeeds.

## First installation

1. Complete Apple account sign-in in Xcode and App Store Connect. Create/verify the app record for `com.biggsjm.MFLBlitz` under team `CP6ZMDE546`; use the existing Apple Distribution certificate with App Store distribution profiles for app and extension.
2. Configure a production APNs key restricted to the Blitz topic on Hephaestus. Keep the existing sandbox key for development builds. The service supports a `productionAPNs` config object with `apnsTeamID`, `apnsKeyID` and an owner-only `apnsKeyFile` path. Never put private key content in source, chat, app settings or command arguments. Restart after configuration and verify `/v1/status` reports `productionPushReady=true`. Update the canonical Hephaestus inventory when configured.
3. Confirm the MFL API registration and exact approved User-Agent. The current common value is `MFL Blitz/0.1 (com.biggsjm.MFLBlitz)`; do not assume that it is registered.
4. Commit the reviewed release files. Set `MFL_BACKGROUND_SYNC_URL` and `NFL_SCORING_URL` to the existing private endpoints, then run `bash scripts/archive_testflight.sh`. It exports only tracked files to a temporary source folder, excluding unrelated synchronized duplicates. Use the Apple-accepted Xcode toolchain; validate the actual upload, not just the local compiler version.
5. Export through Xcode or `xcodebuild -exportArchive -archivePath ... -exportPath ... -exportOptionsPlist scripts/TestFlightExportOptions.plist -allowProvisioningUpdates`. Validate the exported app with `python3 scripts/verify_testflight_export.py /path/to/export/MFLBlitz.ipa`. Xcode can re-sign the intermediate archive during export, so distribution checks apply to the exported IPA. The checked-in export settings create an artifact; they do not upload or send invitations automatically.
6. Set the beta contact/feedback details and applicable export-compliance answers in App Store Connect; these must use the account owner's real information. Upload and wait for successful Apple processing. Add Josh to the internal tester group and install from TestFlight.
7. Verify upgrade from the existing development install: saved MFL session/drafts, roster and standings, both app/widget versions, score freshness, and production Live Activity/lineup notification delivery. Apple acceptance of a push is not proof of visible delivery. Record results before inviting others.

## One or two external testers later

Use a named, closed group after Josh's check. External TestFlight review is separate from internal installation. Keep private backend access restricted: each intended tester needs an approved Tailscale identity/device and explicitly allowed league. The current service registration cap is eight. Do not expose its loopback API publicly or share Josh's MFL credentials. Reassess access/retention and record any service-role changes in the Hephaestus inventory before enabling them.

Privacy policy: [PRIVACY.md](../PRIVACY.md). Support: [repository](https://github.com/biggsjm/mfl-blitz-ios), omitting private league/account details; beta feedback uses TestFlight. The app's manifest declares app-only preferences and optional-service identity/email, device registration and fantasy-game content for functionality, with no advertising or tracking.

## September 16 implementation evidence

- The initial signed archive attempt stopped at Xcode's **No Accounts** error. After Josh signed into Xcode, archive and App Store export succeeded. `/tmp/mfl66-testflight-export/MFLBlitz.ipa` passes app/widget signature, distribution-profile, version, private endpoint, privacy-manifest and production push-entitlement checks. App source revision is `027aa802af5082086722ffec96f44111af38244d`. Browser sign-in is still required for App Store Connect/Apple Developer setup. No upload or invitations have occurred.
- Optimized unsigned Release archive succeeded at `/tmp/MFLBlitz-66-Unsigned.xcarchive`. It is compiler/bundle evidence only and cannot be uploaded as-is.
- Backend: 51 synthetic tests passed, changes deployed to the existing service, health and mode-0600 cooldown database verified. Sandbox ready; production credentials not yet configured. Canonical inventory updated.
- Core: 115 tests passed, including HTTP-date cooldown handling. All 374 app tests and three native trade journeys passed. After the final storage safeguards, 29 focused app checks and the native history journey passed, including two new storage regressions. Details and artifact paths are in [current status](current-status.md).
