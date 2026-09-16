# TestFlight readiness — September 16, 2026

This is the original audit. Josh subsequently approved items 1–3; implementation and current distribution blockers are recorded in [current status](current-status.md) and the [build 66 beta instructions](testflight-beta.md).

Read-only review of the build 65 workspace, current Hephaestus service status, and official MFL/Apple documentation. No build was uploaded, no account configuration was changed, and no new background role or polling schedule was enabled. Existing build 65 standings changes and unrelated untracked duplicate files were preserved.

## Recommended order

1. Reduce unnecessary MFL reads and verify throttling behavior using synthetic request-count tests.
2. Retain trade offers and surface their outcomes instead of silently removing them; design background trade notifications separately from public score polling.
3. Prepare a reproducible Release archive, production push configuration, privacy declarations, and App Store Connect beta information.
4. Install through internal TestFlight on Josh's phone and check upgrade/session retention, production pushes, roster browsing, and trade lifecycle behavior. Broader league testing also needs an appropriate backend access model.

Apple now accepts Xcode 27 builds for internal/external TestFlight. Its release list shows iOS 27 and macOS 27 released September 14, satisfying the earlier OS-release waiting condition. The locally selected Xcode still reports build `27A5194q`; use the accepted final/RC toolchain and validate the actual distribution archive. Owner approval to upload/invite remains separate from this investigation.

## MFL rate-limit findings

Josh recalled the warning on a roster page, not scoring. The exact failed request/time is unavailable, so the following are confirmed pressure sources, not proof of which request produced that incident.

- `LiveMFLRepository` spaces requests by 1.25 seconds. `MFLClient` shares cacheable reads and imposes an in-memory per-host cooldown after HTTP 429. It already avoids blind automatic write retries.
- `AppModel.refreshForForeground()` runs a full scores/lineup/waivers/standings/board refresh after 60 seconds, even when the visible task is roster browsing. Several of those repository reads explicitly bypass caches.
- My Team also calls `TransactionsModel.refresh(ifNeeded: true)` for its trade badge. `loadTrades()` requests both pending offers and all league trade assets; both exports currently have zero TTL. Asset loading needed by the composer is coupled to checking for incoming offers.
- My Team roster reads themselves are batched: roster membership plus one YTD-points read, with cached league/player metadata. Pull-to-refresh also refreshes standings. Avoid replacing this with per-player requests.
- The service's `MFL.export()` has no shared request-spacing gate or HTTP 429/Retry-After handling. Live Activity polling and lineup-alert reads have separate caches; several exports can run consecutively. The poller has generic exponential error backoff, but this is per league/week rather than a common upstream-host cooldown. Home Wi-Fi clients and Hephaestus can share an external IP.
- App Retry-After parsing accepts numeric delays only, not HTTP dates. Its cooldown is lost when a client is recreated. These are hardening gaps; neither is established as the cause of this incident.
- App and service identify themselves with different hardcoded User-Agent strings. Verified MFL client registration and the exact registered value remain unconfirmed: the available browser reached a sign-in requirement.

MFL documents variable limits by IP/server, approximately 2.5× higher allowances for verified registered clients, one-second spacing as guidance rather than a guarantee, caching, and cooling down on 429. No fixed requests-per-minute allowance is published. Public non-league feeds should use the API host. Do not rotate hosts or identities to evade throttling.

Proposed implementation:

- Refresh the visible feature when stale; retain independent freshness windows for other tabs. Keep explicit pull-to-refresh useful, and keep fresh preflight/readback for every real mutation.
- Split the lightweight trade inbox/badge read from composer asset loading; reuse short-lived browsing reads and coalesce overlapping requests without serving stale mutation preflight data.
- Apply shared pacing and host cooldowns to the existing background service, and share identical score reads between its existing consumers. Honor Retry-After and keep cached content visible with an accurate stale/error state.
- Record only endpoint category, status, cache/coalescing outcome, duration and cooldown in bounded diagnostics. Never record credentials, full query strings, trade terms, rosters or raw responses. Verify warm re-entry, repeated refresh, concurrent tabs, 429 recovery and mutations with fake transports before real-device checks.

Hephaestus read-only check during the September 16 audit: both current scoring services active/running with zero restarts; Live Activity health reported `pushReady=true`, zero subscriptions, 151 accepted pushes, no current issue. Its retained poll row had zero failures. This is current state, not historical proof that no throttling happened or that every push was displayed. No service change was made, so the background-role inventory does not require a change entry for this audit.

## Trade test and missing behavior

Josh reports a successful proposal, followed by the recipient rejecting it. Blitz removed it from pending offers and did not alert him. Record proposal success as owner evidence; this does not verify all trade response paths.

The current model replaces `snapshot.offers` with MFL's pending list. It persists drafts and uncertain writes, but not a durable ledger of observed/sent offers. Its badge counts pending incoming/unresolved offers. Existing push support covers Live Activities and opt-in lineup alerts, not trade events. Thus removal and absence of an alert match a missing feature, rather than proving a failed submission or failed APNs delivery.

The official API documents `pendingTrades` and a `tradeResponse` write with accept/reject/revoke. It does not document a declined-offer history export or a distinct decline transaction type. The current activity view reads recent transactions and recognizes completed `TRADE` records. A disappeared offer alone cannot distinguish decline, withdrawal, expiry, or acceptance.

Proposed behavior: persist incoming/outgoing offers by league, franchise and offer ID; move disappeared offers to History after a successful complete read; retain partner, terms and timestamps; use confirmed outcomes when available, otherwise show “Offer closed — check MFL for the outcome.” Failed/partial reads must never close offers. Surface an unread in-app change and deduplicate events across refresh/relaunch. Do not label an outcome “Declined” based only on disappearance.

Background trade push alerts need opt-in authenticated access to private offer data. The existing Hephaestus score service intentionally holds no MFL account credentials and cannot simply poll `pendingTrades` anonymously. Establish the supported authentication/outcome source before promising timely rejection pushes. A new background role or schedule must be explicitly authorized and documented in the canonical Hephaestus inventory when implemented.

## Distribution work still open

- **Production push:** current installed builds use a development profile and a sandbox-only APNs key. TestFlight uses production APNs. The normal Release target also defaults to empty entitlements and does not opt into `MFL_BACKGROUND_PUSH`; the development build script is not a distribution recipe. Verify the built app and widget, production registration, and actual delivered notifications/Live Activities.
- **Backend access:** current service permits one owner identity and one league through private Tailscale endpoints. This can support Josh's initial beta after production configuration. It is not usable unchanged by arbitrary external testers. Define scoped authenticated tester access before a broader beta; do not expose the current loopback service publicly as a shortcut.
- **Privacy:** the manifest's required-reason API array is empty despite UserDefaults/@AppStorage use. Add the accurate declarations and audit data disclosure/retention against the current background services. A manifest already existing in the tree is not sufficient validation.
- **Release source:** build 65 standings changes remain uncommitted. Numerous unrelated untracked ` 2.*` duplicates appeared in synchronized source folders; prior validation used a clean source copy. Preserve these files while establishing a reproducible source-controlled release checkout.
- **Apple account:** App Store Connect app record, distribution profile/archive validation, beta contact/test instructions, applicable export-compliance answers and tester setup could not be verified because the available browser was signed out. No absence of an existing app record is inferred. External testing adds Apple's beta review; internal testing is the first delivery milestone.
- **Candidate validation:** rerun relevant suites on the final candidate and verify the actual TestFlight upgrade/clean install, saved session/drafts, production pushes and network recovery. The prior build 65 tests are evidence for standings, not a completed distribution test.

More app features are not an Apple upload prerequisite. Request reliability and retained trade outcomes are recommended product gates for a useful league beta; accurate trade push outcomes may remain a clearly communicated limitation until the source/access problem is solved.

## Sources

- [MFL API guidance and throttling](https://api.myfantasyleague.com/2026/api_info)
- [MFL request reference](https://api.myfantasyleague.com/2026/api_info?STATE=details)
- [Apple App Store Connect release notes](https://developer.apple.com/help/app-store-connect/release-notes/)
- [Apple releases](https://developer.apple.com/news/releases/)
- [APNs environment entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment)
- [Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)
- [External testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)
