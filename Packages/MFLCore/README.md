# MFLCore

`MFLCore` is the dependency-free networking and model layer for **MFL Blitz**.
It targets Swift 6, iOS 18, and macOS 15.

Documentation reconciled with app **0.5.3 (26)**, September 6, 2026. The app owns Keychain persistence, reviewed workflows, drafts and reconciliation; this package supplies lower-level transport/models and supported standings ranking. Calling an import directly does not provide the app's complete confirmation/duplicate-prevention workflow.

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

Reads include `myLeagues`, `league`, `players`, `freeAgents`, `rosters`, `playerRosterStatus`, `seasonStatus`, `schedule`, `liveScoring`, `projectedScores`, `weeklyResults`, `standings`, `messageBoard`, `messageBoardThread`, `pendingWaivers`, `pendingTrades`, `tradeAssets`, `injuries`, `nflSchedule`, `nflByeWeeks`, `playerScores`, `pointsAllowed`, `watchList`, and calendar/activity/capability reads.

Owner imports include `submitLineup`, `submitBlindBidWaiverRequest`, `postMessageBoard`, `proposeTrade`, `respondToTrade`, `updateWatchList`, `addDrop` and `moveInjuredReserve`. Illustrative calls below require explicit owner intent and app-level preflight/readback; never execute them as a live smoke test:

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
- Calls are spaced by one second by default; the app uses 1.25 seconds. A 429 is surfaced with `Retry-After`, enforced per host and never retried automatically. Hosts are not switched to evade limits.
- Public players and stable league reads default to 24-hour caching. The app injects a season-specific disk cache only for the full public catalog; decoded memory reuse shares its original expiration. League/private responses remain memory-only. Waiver display limits league/balance age to 60 seconds; mutation preflight is fresh.
- Whole-season schedules and projections use 15 minutes; live scores 90 seconds; rosters 30 seconds; roster state 15 seconds; free agents/standings 60 seconds; board list 30 seconds; thread/pending waivers 15 seconds. Weekly results and trade snapshots use forced reads. See the [cache table](../../docs/api-integration.md) for app-level exceptions and request reuse.
- `.reloadIgnoringCache` still obeys request spacing. Concurrent cacheable reads share a request; forced preflight/readback does not join it, and older responses cannot overwrite newer cache entries. No import is blindly retried after timeout or HTTP failure.
- MFL's singleton-versus-array and string-versus-number JSON variations are
  normalized. Variable standings and pending-waiver fields remain available in
  each model's `values` or `attributes` dictionary.
- Body-level JSON/XML errors are checked even with HTTP 200. Anonymous projection placeholders are skipped; identified missing values stay missing. Duplicate catalog IDs and malformed trade dates fail safely.
- `schedule()` omits W/F to load the whole fantasy season and decodes singleton/array weeks and matchups. Missing scores stay nil; result T alone does not prove a final tie. The app shares one season-scoped snapshot and independent browsing routes.
- Team/player aggregation now uses current rosters, separate week-specific assignments, current ownership and optional targeted biography. Bio caching is separate from the full public directory. Live optional fields still vary; whole-week results are not a complete player-history API.
- `playerScores` supplies targeted weekly or YTD fantasy points, with omitted values distinct from zero. Injury/kickoff/bye and watchlist payloads normalize singleton collections. Missing/malformed acquisition flags must remain unknown rather than silently enabling Add.

## Standings

`MFLLeague.standingsSort` preserves the configured criterion sequence. `MFLStandingsRanking.resolve` is a pure calculation over supplied standings rows and optional completed schedule data; it performs no requests. Pass division members for a division place and all league members for overall place. API array position is not rank.

Supported criteria are PCT, pairwise H2H, PTS and DIVPCT. Game ties count as half wins. H2H requires completed schedule/record reconciliation and authoritative W/L/T, not inferred winners from rounded scores. True exhausted ties use competition ranks; missing/unsupported/cyclic inputs leave the scope unranked. `hasReportedResults` distinguishes preseason from reported records or points-only results. Manual/custom orders not exposed in the used API fields remain MFL-report authority. See the [presentation contract and limits](../../docs/standings-pattern.md).

Run verification with `swift test` from this directory. The September 6 build-26 verification passed **88 tests in 12 suites**, including 13 standings tests and the explicit known-versus-missing T2/T2/4 regression. App/UI and real-owner validation are separate: see [current status](../../docs/current-status.md), [integration notes](../../docs/api-integration.md) and [contributing](../../CONTRIBUTING.md).
