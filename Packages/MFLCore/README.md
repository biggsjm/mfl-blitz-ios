# MFLCore

`MFLCore` is the dependency-free networking and model layer for **MFL Blitz**.
It targets Swift 6, iOS 18, and macOS 15.

Documentation audited with app **0.4.0 (17)**, September 6, 2026. The app owns Keychain persistence, reviewed workflows, drafts and reconciliation; this package supplies lower-level transport/models. Calling an import directly does not provide the app's complete confirmation/duplicate-prevention workflow.

## Quick start

```swift
import MFLCore

let reference = try MFLLeagueReference(
    leagueURL: URL(string: "https://www45.myfantasyleague.com/2026/home/41333#0")!
)
let client = MFLClient(
    configuration: MFLClientConfiguration(
        league: reference,
        // Use the exact User-Agent registered with MFL in a production app.
        userAgent: registeredUserAgent
    )
)

// Store only the resulting value in an app-owned Keychain item. The client
// does not retain the password and sends the MFL_USER_ID cookie on later calls.
let cookie = try await client.authenticate(username: username, password: password)

async let league = client.league()
async let roster = client.rosters(franchiseID: "0001")
async let scores = client.liveScoring(week: 7, includeBench: true)
async let standings = client.standings()
```

The caller supplies credentials, `registeredUserAgent`, and verified franchise/season/week context; these are not hardcoded production defaults. Resolve authenticated membership/host through `myLeagues` before acting for an owner. The package default `MFL Blitz/1.0` and app-supplied `MFL Blitz/0.1 (com.biggsjm.MFLBlitz)` are not evidence of client registration.

Reads include `myLeagues`, `league`, `players`, `freeAgents`, `rosters`, `playerRosterStatus`, `seasonStatus`, `schedule`, `liveScoring`, `projectedScores`, `weeklyResults`, `standings`, `messageBoard`, `messageBoardThread`, `pendingWaivers`, `pendingTrades`, `tradeAssets`, and calendar/activity/capability reads.

Owner imports include `submitLineup`, `submitBlindBidWaiverRequest`, `postMessageBoard`, `proposeTrade`, and `respondToTrade`. Illustrative calls below require explicit owner review and app-level preflight/readback; never execute them as a live smoke test:

```swift
try await client.submitLineup(
    MFLLineupSubmission(week: 7, starterPlayerIDs: starterIDs)
)

try await client.submitBlindBidWaiverRequest(
    MFLBlindBidWaiverRequest(
        round: 1,
        bids: [MFLBlindBid(playerID: addID, amount: 12, dropPlayerID: dropID)]
    )
)

try await client.postMessageBoard(
    MFLMessageBoardPost(subject: "Week 7", body: "Good luck!")
)
```

## API behavior

- All traffic is HTTPS. Login is form-encoded POST, as recommended by MFL.
- `MFL_USER_ID` is sent explicitly inside the HTTP `Cookie` header. The package does
  not persist credentials; Keychain ownership remains with the app.
- The app resolves authenticated membership and host through `myleagues`; the client can also discover a validated `league.baseURL` or narrowly validated league-export GET redirect. Hosts are session-scoped. Login/mutation redirects remain blocked, and cookies are stripped from permitted discovery redirects. Shared player requests use `api.myfantasyleague.com`.
- Calls are spaced by one second by default. A 429 is surfaced with
  `Retry-After` and is never retried automatically.
- Public players and stable league reads default to 24-hour caching. The app injects a season-specific disk cache only for the full public catalog; decoded memory reuse shares its original expiration. League/private responses remain memory-only. Waiver display limits league/balance age to 60 seconds; mutation preflight is fresh.
- Whole-season schedules and projections use 15 minutes; live scores 90 seconds; rosters 30 seconds; roster state 15 seconds; free agents/standings 60 seconds; board list 30 seconds; thread/pending waivers 15 seconds. Weekly results and trade snapshots use forced reads. See the [cache table](../../docs/api-integration.md) for app-level exceptions and request reuse.
- `.reloadIgnoringCache` still obeys request spacing. Concurrent cacheable reads share a request; forced preflight/readback does not join it, and older responses cannot overwrite newer cache entries. No import is blindly retried after timeout or HTTP failure.
- MFL's singleton-versus-array and string-versus-number JSON variations are
  normalized. Variable standings and pending-waiver fields remain available in
  each model's `values` or `attributes` dictionary.
- Body-level JSON/XML errors are checked even with HTTP 200. Anonymous projection placeholders are skipped; identified missing values stay missing. Duplicate catalog IDs and malformed trade dates fail safely.
- `schedule()` omits W/F to load the whole fantasy season and decodes singleton/array weeks and matchups. Missing scores stay nil; result T alone does not prove a final tie. The app shares one season-scoped snapshot and independent browsing routes.
- Team/player aggregation now uses current rosters, separate week-specific assignments, current ownership and optional targeted biography. Bio caching is separate from the full public directory. Live optional fields still vary; whole-week results are not a complete player-history API.

Run verification with `swift test` from this directory. The September 6 My Team verification passed 68 tests in ten suites; the earlier documentation baseline passed 62 tests. App/UI and real-owner validation are separate: see [current status](../../docs/current-status.md), [integration notes](../../docs/api-integration.md) and [contributing](../../CONTRIBUTING.md).
