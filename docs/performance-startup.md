# Cached startup and performance review

September 7, 2026 · **0.5.3 (28)**. This is an engineering review and synthetic verification, not a device-wide Instruments trace or live game-week certification. Exact test, CI and phone delivery evidence lives in [current status](current-status.md).

## Player-card loading follow-up — build 30

The owner reported slow player loading and a lingering game-info spinner on build 29. The optional biography previously held the whole primary read; it now loads on disclosure, from its existing daily memory cache. Ordinary card reappearance no longer forces an ownership request, while explicit refresh and roster changes still do. The league model owns shared availability tasks across screen navigation; scope reset cancels them, interrupted attempts clear their suppression, and UI loading reflects the actual task state. Tests reproduce navigation cancellation and enforce cache/request budgets; phone timing remains an owner check, not an inferred benchmark.

## Outcome

A returning manager sees the last successfully loaded scores, lineup, standings, Board summaries and own-team season roster while the app reconnects. A small “Updating league…” status replaces the blocking reconnect overlay when an eligible cache exists. Offline, content remains with “Offline · Last update shown,” Retry and Sign in. Section timestamps use coarse relative wording, not a running seconds counter.

The first-ever sign-in still needs a successful download: there is nothing truthful to cache before that. An update from build 27 also needs one successful load to seed these new screen snapshots. Missing, expired, corrupt or iOS-evicted caches fall back to the existing bounded/cancellable connection flow. Team logos remain memory-only; initials are the offline fallback. This is not a complete offline app or an offline write queue.

## Findings and changes

| Area reviewed | Finding / action |
| --- | --- |
| Root/app lifecycle | Public player caching did not make any screen available during authentication. Added protected display snapshots and nonblocking reconnect/offline presentation. |
| Startup request ordering | Scores, lineup, waivers, standings, Board and foreground trades competed for MFL's spaced request slots. Scores and lineup now start first; remaining initial feeds wait for both. Foreground trade refresh waits for My Team to be selected and priority reads to finish. |
| League configuration | Stable metadata survived only in memory. Reuse a protected daily league export after fresh account/franchise membership verification; dynamic balance and forced-write policies stay stricter. |
| Player decoding/mapping | Validated catalog decoding was already shared, but repositories rebuilt whole-directory dictionaries. Store one `playersByID` index with the decoded catalog and reuse it across scoring, lineup, waivers, trades, rosters, history and watchlist mapping. |
| Disk I/O | Cache hits previously re-encoded and rewrote the response. A valid disk hit now publishes to memory without rewriting; original expiration remains unchanged. Encoding and file I/O run on cache actors, outside the main actor. |
| Season status | Concurrent consumers could duplicate status reads. Share a 60-second in-memory read; an explicit foreground week check bypasses it so rollover is never hidden by that TTL. |
| Scores/detail | Preserve the single visible foreground poller, jitter and completed-results reads. Saved scorecards have no LIVE claim or current player clocks; cached opponent projections cannot create a fresh lineup advantage. |
| My Team/player research | Preserve batched roster/YTD reads and scoped routes. Build 29 loads two independent targeted YTD/AVG reads for the primary player card and four completed-week scoring reads for its visible log; earlier pages remain explicit. NFL opponent context reuses one shared whole-season schedule, not a per-player/week schedule fan-out. Hydrate the owner's roster for display, but force a normal authenticated reload before considering it recently verified. |
| Lineup/waivers/trades/Board | Preserve draft mergers, fresh mutation preflight/readback, durable ambiguous-action markers and no automatic import retries. Board disk content contains list summaries only, not full posts. |
| Artwork/views | Preserve lazy lists/grids, bounded downsampled image caching, request sharing, failure cooldowns and isolated cookieless artwork requests. No new image provider, dependency, poller or analytics. |

## Storage and trust boundaries

| Cache | Scope / bound | What it can authorize |
| --- | --- | --- |
| Public directory | Season/version; original 24-hour TTL; existing 32 MiB file bound | Nothing; identity lookup only |
| Protected league metadata | One 32 MiB-bounded file; season/host/league plus hash of exact saved session/franchise; at most 24 hours | Only a read optimization after fresh membership; balance display still limits age to 60 seconds and write preflight bypasses it |
| Protected display snapshot | One 4 MiB-bounded file; exact session/season/league/franchise; each section younger than 7 days | Nothing; cached lineup is explicitly noneditable until refreshed |

Both private files use iOS complete file protection and are excluded from backups. Raw cookies, passwords and response headers are not serialized into these cache files. The league export can contain private owner fields and balances, so it is never placed in the public player cache. Pending bids, offers, permissions, watchlists and full player histories have no new response disk store. Existing Keychain drafts/markers are a separate recovery mechanism.

Section age does not reset when a different section refreshes. Wrong-week scores/lineups do not migrate into the newly confirmed week. Late display-cache writes recheck the saved session binding. Explicit disconnect detaches league caching, invalidates in-flight publication and removes private cache files. Revoked/expired identity returns to sign-in rather than presenting it as offline access; drafts remain available for the same team. Imports detach and clear persisted league metadata before sending, even when the outcome is uncertain, so older balances cannot be restored afterward.

## Verification and limits

- The synthetic model displayed cached content in about **10 ms while authentication was deliberately suspended**. This measures the model/cache path on the development simulator—not real cellular latency, first pixel on a phone, or a guaranteed launch time.
- Two synthetic repository launches perform **two fresh membership checks but one league download** with the protected metadata cache; daily public-catalog reuse remains one download across tabs/relaunch.
- A suspended-lineup test proves scores can render before optional waivers/Board/standings/trades start. Another proves successful authentication alone does not enable a still-cached lineup.
- Coverage includes offline retry, expired access, cookie/season/league/franchise isolation, sign-out, corrupt/future/aged cache rejection, per-section dates, no raw cookie persistence, backup exclusion, stricter balance TTLs, forced reads, mutation invalidation and week rollover.
- Explicit DEBUG-only native Preview journeys hold authentication or simulate offline service, verifying saved Scores/Lineup/My Team, disabled lineup actions, reconnect controls and largest-text status placement. Cached score rows never call old scores “Upcoming.” Player detail opened during reconnection explains the connection requirement and reloads when verification finishes. Tests use an isolated synthetic store and never the live Keychain/network.
- Development testing caught and fixed a stale foreground-week check, overlapping reconnect status and overly detailed timestamps. Final counts/results are recorded separately; failed or superseded runs are not passes.
- Final source passes **91 core tests, 173 app unit functions and all 39 native UI journeys** locally and in GitHub compatibility checks. Build 28 is installed/launched on the owner's phone; file metadata confirms approximately 58 KB of display snapshots and 20 KB of protected league metadata. No private response contents were exported for this check. [PR #7](https://github.com/biggsjm/mfl-blitz-ios/pull/7) is merged; see the exact [evidence record](current-status.md).

## Remaining work

1. Owner: the phone cache is now populated. Close/reopen on Wi-Fi/cellular, then test airplane-mode reopening and recovery. Compare current week/data with MFL before intended changes. Record phone time-to-content, not just synthetic timings. A new installation still requires its initial successful load.
2. Profile an archive on the phone with Instruments/App Launch and Time Profiler; capture p50/p95 warm-cache launch and interactive-frame measurements across realistic large leagues. No telemetry is added by this change.
3. Review optional-feed loading on demand and an explicit manual cache-refresh affordance after commissioner rule changes; current fresh write checks remain mandatory.
4. Consider separately scoped offline schedule/player-detail support only if needed; do not broaden private persistence silently. Keep background/push work in the existing feature plan.
5. Complete broader maximum-Dynamic-Type Scores cards/Lineup rows, iPad/small-screen and manual assistive-technology checks in the [release gates](roadmap.md).
6. Profile remaining main-actor work before expanding this pass: available-player filtering/localized sorting on view updates, synchronous Keychain draft writes, and repeated non-player response decoding. Small roster/offer collections do not justify speculative concurrency changes. My Team's trade badge refresh now waits for that tab to be visited; it is not a push notification.

A short physical-phone App Launch trace was attempted twice after successful build-28 installation/launch. Instruments reported a device connection error and produced no timing samples, although CoreDevice reported the phone booted with developer services enabled. This is not a passing trace or evidence of an app hang; a stable profiling connection remains needed.

The approach follows the existing [MFL API cache guidance](https://api.myfantasyleague.com/2026/api_info) and Apple's guidance to keep non-UI work away from interaction-sensitive execution in [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness). See [API policies](api-integration.md), [privacy](../PRIVACY.md) and [security](../SECURITY.md) for the exact implemented contract.
