# Shared NFL scoring feed

Build 55 adds API-NFL enrichment to MFL scoring. Fantasy points, lineup state and live estimates remain from MFL. Player rows show a short NFL stat line; the player's Week screen shows grouped box-score fields and their own source receipt. NFL game context uses the provider's actual quarter, clock, halftime, overtime and final status. No synthetic ticking clock or fantasy-point calculation is added.

The pending build-70 kickoff fallback handles a delayed provider `NS` response: a running MFL game/player clock keeps the player live and visible in Live players. The provider's scheduled opponent remains available, while missing NFL scores and player stats stay unavailable until supplied. Kickoff time or fantasy points alone never prove live play. This reconciliation changes presentation only and adds no requests.

Build 56 fixes missing receiving/rushing touchdowns in matchup summaries. Passing and rushing TDs, interceptions thrown, two-point conversions, fumbles lost/recovered, kicking conversions and available distance buckets, individual defensive events and return scores remain visible across all stat groups. Rows wrap to fit; neither a two-group cap nor a three-line cap can hide scoring events. The cached Brenton Strange Week 1 example now reads **2 rec · 23 rec yd · 1 rec TD**. The full player box retains its existing presentation.

## Request budget

The Pro allowance is 7,500 requests per UTC day, shared by the account. One worker on Hephaestus serves every phone from a persistent SQLite cache. Phone reads, navigation and pull-to-refresh never directly invoke API-NFL, and there is no provider-cache bypass parameter.

| Data | Normal refresh while requested |
| --- | --- |
| Shared NFL schedule/game scoreboard | 30 seconds while requested weeks contain live games or are near kickoff; 15 minutes otherwise |
| Live game player box score | 60 seconds per game, containing both teams and all players |
| Recently completed box score | 5 minutes for the first six hours after kickoff; hourly through two days; daily through seven days |
| Final transition / archive | Fetch a final box even if the prior live box is fresh. Make one last correction read on the first requested visit after seven days, then reuse that saved box indefinitely |
| Team roster / position metadata | Daily for live games; fill missing metadata for completed games and reuse known matching identity |
| Season coverage | Daily |

A planning envelope of sixteen four-hour games, fourteen hours of live scoreboard checks plus ten idle hours, 32 rosters, coverage, sixteen final reads and two hours of five-minute final corrections per game is **5,993 calls** before backoff. This is a workload example, not a worst-case guarantee: longer games, retries and additional historical weeks can add work. The service slows live polling at **5,000 / 5,500 / 5,800** calls and stops at **6,000**, leaving 1,500 requests outside its own budget. A process lock prevents duplicate workers for this database; usage reservations happen before I/O and survive restarts and failures. UTC midnight resets the allowance. The separate historical test retains its existing 20/day ceiling.

Fast player-stat polling is limited to active NFL game states (including halftime and overtime). Upcoming, postponed, canceled, suspended and interrupted games do not fetch player boxes. Slower completed-game checks intentionally allow delayed final statistics and corrections to arrive; a strict stop at the final whistle could freeze incomplete data. These checks only run while a phone's viewing demand remains active. Cold historical games get an initial box, while archived games preserve their original source receipt and do not expire simply because time passes. Corrections published after the seven-day window are not automatically fetched for an archived box.

Provider headers supply an additional guard: stop when account-wide remaining requests reach 500, and pause when the minute quota is nearly exhausted. Honor HTTP 429 Retry-After, back off network/decoding failures, and pause on authentication/plan errors. Other tools using the same account still consume its quota; this service cannot control their requests. Direct-dashboard billing does not charge request overages.

## Fast reads and bounded work

Each phone gets cached data immediately, even during an upstream fetch. A cold cache returns a loading response and a short reread interval; partial results arrive as game boxes and roster metadata become available. Viewing a matchup/player prioritizes its NFL teams. Phones send no MFL franchise IDs, player IDs, credentials or private league data to this service. Its reviewed translation table uses public MFL player IDs deployed with service code.

Demand leases expire five minutes after the last phone read. No NFL polling continues indefinitely after everybody leaves scoring. One worker spaces upstream requests by at least two seconds and coalesces identical work for all readers. The season is explicitly configured; the current API covers regular-season weeks 1–18. Unresolved postseason fixtures are excluded from this regular-season view without invalidating legitimate games. Postseason scoring support remains separate.

The phone coalesces concurrent reads, keeps up to three weeks in memory, and rereads the shared cache about every 20 seconds during games (five seconds while warming, one minute otherwise). It pauses with the scene, keeps old data during failures, and backs off failed reads. Original game and box-score receipts stay separate. A failed refresh never relabels saved data as newly checked.

## Player identity and missing data

Build 58 adds a [reviewed player translation table](player-stat-translations.md) on the shared service for confirmed cross-provider name differences. Optional MFL ID/name fields are emitted only when season, provider ID/name, team, position and the same-ID roster agree. Both the app and Live Activity then require the MFL ID/name, team, position and a unique match. Unmapped players still need normalized full name **plus NFL team plus position**. No blanket nickname expansion, suffix removal, guessing from stat categories or name-only match is allowed. The historical manual mapping feature remains separate.

Ambiguous players, missing positions, team changes not reflected in the catalog, and missing provider fields remain unavailable. Nulls display as an em dash; zeroes remain zeroes. Full passing/rushing/receiving/kicking and individual defensive groups are preserved when provided. A fantasy D/ST slot does not match an individual player; aggregate team-defense box stats are not supplied by this player endpoint.

The compact summary supports checking common scoring contributions against a league's rules; it is not a complete league-scoring calculator. Provider omissions can still prevent exact reconstruction (for example, observed kicking distance buckets can all be zero despite made field goals). MFL-specific bonuses, scoring corrections and the two independent feeds' update times can also differ. Repeated return/defensive TD fields use one source rather than adding duplicate totals, and missing stats are never invented to make fantasy points balance.

## MFL refresh review

- Entering Scores or returning to the foreground requests a score check without waiting for the periodic timer. Existing data and the matching newer Live Activity header stay visible.
- One foreground scoring poller serves the selected week and drill-down. Live fantasy scoring checks approximately every 60 seconds; inactive current weeks every two minutes; historical weeks every five minutes. Failures back off to three minutes.
- Concurrent manual refresh joins the ongoing score request. Repeated automatic triggers are suppressed for ten seconds. An entry within fifteen seconds of a fresh score receipt does not issue another request.
- Manual matchup/player refresh starts independent NFL and MFL game reads alongside fantasy scoring. NFL failure cannot erase or block the fantasy score update.
- Background MFL polling changes from 90 to 60 seconds, still one read per league/week shared by registered activities. Existing APNs artwork, final-confirmation, error-backoff and token rules remain.

## Private deployment

`services/nfl_live/` uses Python's standard library. `scripts/deploy_nfl_live.sh` installs `mfl-nfl-live.service`, loopback port 8793 and a separate private Tailscale HTTPS route on 8445. Existing historical (8443) and Live Activity (8444) services remain separate. The existing owner-only API key is read in place; it is never copied to the app. The app receives the service address through `NFL_SCORING_URL` at build time.

Routes require `X-Blitz-NFL: 1`, reject browser-origin requests and expose no arbitrary proxy query. `/v1/status` reports the local request budget without calling the provider or returning account identity. No public hosting or tailnet access rules are changed. Public distribution would require a separately deployed authenticated service.

Verification and phone-delivery evidence are recorded in [current status](current-status.md). Live-game timing must still be observed during an actual game; completed-game reads and simulated transitions cannot prove provider game-day latency.


## Build 57: team defense and Live Activity context

Team-defense demand is explicit (`X-Blitz-NFL-Defense`, public NFL team codes), expires in five minutes, and shares the existing worker, budget reservation, global backoff and cache. The team-stat endpoint has a 120-second live interval; completed games follow the same correction/archive policy. Responses carry separate defense receipts and staleness. No D/ST demand means no team-stat request. See [game-day enhancements](game-day-enhancements.md) for supported fields and MFL scoring semantics.

Registered Live Activities may read this same local cache for their starter context while the phone is closed. Normal lineup notifications use MFL's schedule, saved starters and injuries and do not call the paid provider.
