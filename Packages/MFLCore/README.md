# MFLCore

`MFLCore` is the dependency-free networking and model layer for **MFL Blitz**.
It targets Swift 6, iOS 18, and macOS 15.

## Quick start

```swift
import MFLCore

let reference = try MFLLeagueReference(
    leagueURL: URL(string: "https://www45.myfantasyleague.com/2026/home/41366#0")!
)
let client = MFLClient(
    configuration: MFLClientConfiguration(
        league: reference,
        // Use the exact User-Agent registered with MFL in a production app.
        userAgent: "MFL Blitz/1.0"
    )
)

// Store only the resulting value in an app-owned Keychain item. The client
// does not retain the password and manually sends MFL_USER_ID on later calls.
let cookie = try await client.authenticate(username: username, password: password)

async let league = client.league()
async let roster = client.rosters(franchiseID: "0001")
async let scores = client.liveScoring(week: 7, includeBench: true)
async let standings = client.standings()
```

The primary reads are `league`, `players`, `freeAgents`, `rosters`,
`liveScoring`, `standings`, `messageBoard`, `messageBoardThread`, and
`pendingWaivers`. The three owner writes are:

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
- `MFL_USER_ID` is installed explicitly as a request header. The package does
  not persist credentials; Keychain ownership remains with the app.
- League hosts are validated, discovered from `league.baseURL`, and retained
  for the actor's session. Shared player requests use `api.myfantasyleague.com`.
- Calls are spaced by one second by default. A 429 is surfaced with
  `Retry-After` and is never retried automatically.
- The player catalog is cached for 24 hours. Live scoring uses a conservative
  90-second TTL matching the source-data cadence; other league data has shorter
  endpoint-specific TTLs. Pull-to-refresh can use `.reloadIgnoringCache`, but
  the one-second request gate still applies.
- MFL's singleton-versus-array and string-versus-number JSON variations are
  normalized. Variable standings and pending-waiver fields remain available in
  each model's `values` or `attributes` dictionary.

Run verification with `swift test` from this directory.
