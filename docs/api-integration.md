# MFL 2026 API integration

Implementation audit: September 7, 2026, **0.5.3 (28)**. Versioned observations below are historical evidence, not promises about future feed contents. See [current status](current-status.md) and [remaining work](roadmap.md).

Primary sources: [general API guidance](https://api.myfantasyleague.com/2026/api_info), [request reference](https://api.myfantasyleague.com/2026/api_info?STATE=details), and [sample code](https://api.myfantasyleague.com/2026/api_info?STATE=example).

Standings correction: an authenticated read through the app's own session verified franchise-ID-ordered, all-zero preseason rows without explicit ranks. Array position is no longer used as rank. The shared resolver compares the league's configured PCT/H2H/PTS/DIVPCT sequence separately for divisions and overall; pairwise H2H requires complete schedule/record reconciliation. Missing, unsupported or cyclic data stays unranked. Manual/custom orders not exposed by the used API fields are not mirrored; MFL's report remains authoritative. See the [implemented pattern and verification limits](standings-pattern.md). No authenticated response or diagnostic credentials are stored in this repository.

Ranking reuses cached league and standings exports. A tied earlier criterion requiring H2H can consult season status and one shared full-season schedule read (15-minute cache); there is no per-team fan-out, new polling or private response persistence. Synthetic tests cover ranking, malformed inputs, same-name division IDs, incomplete membership and repeated-read cache reuse. Actual completed-week report comparison remains an owner release gate.

## Authentication and routing

MFL does not provide OAuth. Sign-in is an HTTPS `POST` to:

```text
https://api.myfantasyleague.com/{season}/login
```

The form contains `USERNAME`, `PASSWORD`, and `XML=1`. A successful XML response contains `MFL_USER_ID`; subsequent requests send it as the `MFL_USER_ID` cookie. Logout is local cookie deletion. The alternate `APIKEY` works only for restricted exports, not imports, so it cannot power lineup, waiver, or message-board writes.

After authentication, resolve the requested league's franchise id and current `wwwXX` host through `TYPE=myleagues`. Validate the returned HTTPS MFL URL, select its host, then fetch authenticated league data directly from that host. As a fallback for unauthenticated discovery, the generic client can follow MFL's league-export GET redirect only after validating HTTPS, the MFL domain, and an unchanged path/query; it strips the session cookie from that redirected request. Login and mutation redirects remain blocked. MFL warns that leagues can move between hosts, so a host is scoped to a session. A multi-league picker is planned, but the underlying account-to-league mapping is implemented in version 0.1.

## Priority endpoint map

All league calls use `https://{resolved-host}/{season}/` and include `L={leagueID}`.

| Capability | Request |
|---|---|
| Account league/franchise mapping | `export?TYPE=myleagues&YEAR={season}&JSON=1` |
| Current week | `https://api.myfantasyleague.com/fflnetdynamic{season}/mfl_status.json` |
| Public player catalog | `https://api.myfantasyleague.com/{season}/export?TYPE=players&JSON=1`; optional `PLAYERS={ids}&DETAILS=1` for targeted detail |
| League/capabilities | `export?TYPE=league&JSON=1`; authenticated `TYPE=abilities&DETAILS=1` |
| Live scores | `export?TYPE=liveScoring&W={week}&DETAILS=1&JSON=1` |
| League-scored projections | `export?TYPE=projectedScores&W={week}&JSON=1` |
| Fantasy season schedule | `export?TYPE=schedule&JSON=1`; omit `W` and `F` for the entire season |
| Final results | `export?TYPE=weeklyResults&W={week}&JSON=1` |
| Roster | `export?TYPE=rosters&FRANCHISE={id}&JSON=1`; optional `W={week}`, omitted for current team membership |
| Player lineup state | `export?TYPE=playerRosterStatus&P={ids}&W={week}&F={franchise}&JSON=1` |
| Submit lineup | `import?TYPE=lineup&W={week}&STARTERS={ids}&TIEBREAKERS={ids}` |
| Free agents | `export?TYPE=freeAgents&POSITION={position}&JSON=1` |
| Saved waiver requests | `export?TYPE=pendingWaivers&JSON=1` |
| Submit conditional BBID round | `import?TYPE=blindBidWaiverRequest&ROUND={n}&PICKS={add_bid_drop,...}&REPLACE=1` |
| Pending owner trades | `export?TYPE=pendingTrades&FRANCHISE_ID={owner}&JSON=1` |
| Tradable assets | `export?TYPE=assets&JSON=1` |
| Propose trade | `import?TYPE=tradeProposal`; POST `OFFEREDTO`, `WILL_GIVE_UP`, `WILL_RECEIVE`, `COMMENTS`, `EXPIRES`, `FRANCHISE_ID` |
| Respond to trade | `import?TYPE=tradeResponse`; POST `TRADE_ID`, `RESPONSE=accept/reject/revoke`, `FRANCHISE_ID`; optional rejection `COMMENTS` |
| Recent transaction activity | `export?TYPE=transactions&TRANS_TYPE=DEFAULT&COUNT=50&JSON=1` |
| Standings | `export?TYPE=leagueStandings&COLUMN_NAMES=1&ALL=1&JSON=1` |
| Board summaries | `export?TYPE=messageBoard&COUNT={count}&JSON=1` |
| Board thread | `export?TYPE=messageBoardThread&THREAD={id}&JSON=1` |
| New board post | `import?TYPE=messageBoard&SUBJECT={subject}&BODY={body}` |
| Board reply | `import?TYPE=messageBoard&THREAD={id}&BODY={body}` |

`playerRosterStatus` is the authoritative readback for saved starter assignments (`S` and `NS`). MFL documents `locked` only for free-agent acquisition state, not rostered-player lineup deadlines, and does not expose a saved lineup tiebreaker. The app therefore uses NFL game progress only to disable obviously started players, lets MFL enforce the league's final lock rules, and describes tiebreaker submission as sent rather than readback-confirmed.

For a blind bid, `0000` is the no-drop sentinel. Conditional leagues require `ROUND`; `REPLACE=1` means the app must send the complete desired state for that round. MFL offers no idempotency key or dry-run mode.

The private Week 1 build persists the cookie and scoped drafts in device-only Keychain items using [Apple’s When Unlocked accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly). Restored cookies undergo fresh membership/franchise verification. The public `mfl_status` request carries no cookie; its `CurrentWeek`, `LineupWeek`, and `CompletedWeek` are distinct. Completed weeks use fresh `weeklyResults` reads.

Version 0.2.1 requests MFL's `projectedScores`, which converts Fantasy Sharks projections to the league's scoring rules. Requests explicitly select a week and use the authenticated league host, with a 15-minute cache. Individual missing/ambiguous values stay nil; a team projection requires every starter's projection. These are pregame projections, not a continuously updated final-score forecast. Availability for private leagues requires the owner's app session.

Build 27's [Lineup margin](lineup-projections.md) subtracts the same-week opponent's projected starter total from the edited lineup total using already loaded snapshots. It adds no requests or cache changes. Complete starter counts, exact owner/matchup identity and finite projections are required; unknown, failed or ambiguous comparisons remain absent. It never substitutes actual live scores or the owner's saved scoreboard total.

Version 0.2.2 corrects a live-feed decoding failure verified on the connected iPhone on September 5, 2026: the authenticated Week 1 response contained 447 rows, including an anonymous `{"id":"","score":""}` placeholder. The previous strict player decoder rejected the whole array. Projection decoding now omits anonymous placeholders while preserving identified rows with missing scores and duplicate-ID checks. The trimmed `projected-scores-placeholder.json` regression fixture includes the observed blank row and a valid live player projection, plus a synthetic trailing zero to prove decoding continues past the placeholder. Lineup and waiver notes distinguish decoding, authorization, and rate-limit failures from an actually empty projection feed. Debug diagnostics contain aggregate counts only, never cookies or raw response bodies.

The corrected 0.2.2 (4) device build was installed and launched with the existing saved session. Its live read decoded 446 usable Week 1 projections and mapped projections to 17 of the 18 roster players. The remaining player has no value in that response and remains blank. This verification performed reads only; it did not submit a lineup, waiver bid, or board post.

Reconnect has a 15-second account-verification deadline and a cancel-to-sign-in action. Build 28 displays eligible protected screen snapshots before verification, with a compact updating/offline status. Without a cache, the bounded overlay remains. Fresh scores/lineup start before optional initial feeds; each result publishes independently. A cached/loading lineup cannot edit or submit before its fresh server baseline arrives. See [startup contract](performance-startup.md).

Blind-bid writes compare fresh pending requests with the user-reviewed baseline, then verify the entire intermediate queue after each changed round. Empty `PICKS` explicitly clears a round. A failed request stops the sequence and triggers readback, not resubmission. Unknown queue structures fail closed. Calendar dates use explicit future `WAIVER_BBID` events when available; recurrence is not guessed. Recent processed acquisitions use `transactions` filtered to `BBID_WAIVER,WAIVER,FREE_AGENT`; the MFL website remains the full processing report.

Before a board import, a durable marker records the intended body, subject/thread, and existing IDs. Readback must find a new post with the same owner and full body; new threads require a thread-detail fetch, not just a matching summary subject. An ambiguous send remains blocked across relaunch until readback confirms it or the user explicitly verifies MFL and resolves the warning.

Version 0.4.1 changes only Board draft presentation/persistence, not the import contract: Close offers save/discard for meaningful text, and Board → Drafts exposes new-thread and per-thread reply recovery. Blank drafts are omitted, failed secure writes cannot close as a successful save/discard, and an editor's late field callbacks cannot recreate discarded text. Discard preserves unconfirmed-send markers. See [Board drafts](board-drafts.md).

## League 41333 profile

The supplied [Champion Hall league metadata](https://www45.myfantasyleague.com/2026/export?TYPE=league&L=41333&JSON=1) reports:

- 12 franchises in Faulk, Warner, and Bruce divisions;
- 18-player rosters plus three IR positions;
- nine starters: QB 1, RB 2–4, WR 3–5, TE 1–3;
- partial lineups disallowed and one nonstarter tiebreaker;
- conditional `BBID_FCFS`, up to eight rounds, $100 season limit, $1 increment;
- standings order `PCT,H2H,PTS,DIVPCT`.

These values explain the app's conditional queue and flexible position-count validator. They must remain dynamic in production. The export omits `bbidMinimum`; on September 6, 2026, Josh confirmed a $0 minimum. Version 0.3.1 uses that confirmation only as a fallback for league 41333 in 2026. An explicit MFL minimum always wins, including during fresh write preflight. Other leagues/seasons with an unknown minimum remain read-only. This is a league-specific confirmed rule, not an inference that omitted numeric fields mean zero.

Standings use the authenticated league export's `owner_name`/`ownerName` under the team name; divisions remain group headings. MFL restricts personal owner information in its API, so an absent/blank name is shown as “Owner not listed,” never replaced with an email, guessed identity, or public-profile lookup. Demo owners are synthetic.

Version 0.3.1 parses activity by transaction type. `BBID_WAIVER` uses `addedIDs|bidAmount|droppedIDs`, whereas `FREE_AGENT` uses `addedIDs|droppedIDs`; blank/zero no-drop sentinels are omitted. Trade/IR/taxi moves use named fields. The formatter is shared by Activity and recent waiver results. Formats were cross-checked against the [ffscrapr MFL transaction implementation](https://github.com/ffverse/ffscrapr/blob/main/R/mfl_transactions.R). Unrecognized formats are not guessed.

## Defensive client rules

Matchup player game context (build 36) reuses the existing `PlayerToolsModel` weekly availability read and `nflSchedule` cache (6 hours), alongside cached injury/bye feeds. One screen-level load serves every row, not one request per player. Normal visits and pull-to-refresh use the cache rather than forcing schedule/injury requests. Results require the same scope and inspected week; optional failures retain existing scoring and safe status fallbacks. The existing live-scoring player clock supplies Live/Final states; a scheduled future kickoff is not final, and missing schedule entries do not imply a bye. No endpoint, credential scope, storage, permission or provider is added.

1. Keep player and franchise IDs as strings, including leading zeroes.
2. Decode numbers and booleans from MFL's string-valued JSON fields.
3. Support both singleton objects and arrays where MFL varies container shape.
4. Inspect the body for JSON `error.$t` or XML `<error>` even when HTTP status is 200.
5. Space API requests by at least one second. Poll live scoring at roughly 90 seconds or slower, with jitter.
6. Share one full player directory across all tabs and persist it for 24 hours; cache stable league configuration aggressively. The API supports `SINCE`, but this app currently refreshes the full catalog once its daily cache expires.
7. Honor 429 without an immediate retry. Show cached data and a clear stale state.
8. Never blindly retry a write. Refetch submitted state first after an ambiguous outcome.
9. Authenticate priority workflows even when an individual league exposes some score/roster endpoints publicly.
10. Reject or replace arbitrary non-HTTPS franchise artwork; never add a global ATS exception.
11. Redact passwords, cookies, bid amounts, and message bodies from logs and diagnostics.
12. Keep unsupported league configurations read-only with an explicit handoff to the MFL web report.

## Franchise artwork

Version 0.2.5 uses the league export's `icon` and `logo` URLs in score cards, matchup headers, and standings. Prefer the compact icon, then try the logo, then retain the team's initials. Preserve returned paths exactly: this league still references artwork stored under older seasons and league IDs. Only credential-free HTTPS URLs on the default HTTPS port are eligible; HTTP images are skipped without an ATS exception.

Artwork loads independently from league data through an ephemeral, cookieless, credential-free session. Redirects and authentication challenges (other than normal TLS trust validation) are rejected. Responses must be successful images and are capped at 2 MiB while streaming. ImageIO creates a maximum-256-pixel thumbnail; GIFs use a still first frame. Concurrent marks share requests, decoded artwork is reused from a bounded memory cache for up to 15 minutes, and failures have a 60-second retry cooldown. No image failure blocks account restoration, scores, or lineup editing. The offline preview retains local initials and makes no artwork requests.

Read-only verification against the public league export successfully downloaded and decoded artwork for all 12 franchises with this native loader. Regression tests cover JPEG/PNG/GIF decoding, downsampling, safe URL selection, cookie isolation, caching, failed-image fallback, and artwork mapping into live/completed matchups and official standings.

## Cache and refresh policies

These are current defaults, not a cache-everything rule. Private read retention and write preflight have different requirements.

| Data | Retention/freshness | Exceptions |
| --- | --- | --- |
| Full public player directory | 24-hour disk entry plus validated decoded memory reuse, scoped by season/version | Original fetch time survives relaunch; invalid/expired data is rejected; no private payloads/headers on disk |
| Stable league configuration | 24-hour protected disk entry plus memory cache | Attach only after fresh membership; season/host/league/session/franchise scoped; waiver balance display imposes 60-second maximum age; write preflight bypasses cache |
| Last loaded screen display | Per-section maximum 7 days; one 4 MiB protected, backup-excluded file | Exact saved session/season/league/franchise; never permission, preflight or readback; no current-clock/LIVE claim; cached lineup noneditable |
| Season status | Shared 60-second memory read | Foreground week verification forces a fresh read; current/lineup/completed weeks remain distinct |
| Targeted player biography | Separate 24-hour memory cache, keyed by requested IDs/details | Ownership refresh does not re-download biography or basic catalog |
| Fantasy season schedule | One shared 15-minute season/league/session snapshot, plus request sharing | Explicit refresh reloads schedule; no per-team or per-week scoring fan-out |
| Pregame league projections | 15-minute memory cache, league/week scoped | Missing values remain nil; not a live forecast |
| Live scoring | 90-second memory TTL and one foreground scoreboard/detail poller | Completed weeks use forced `weeklyResults`; foreground lifecycle and read guards prevent duplicate pollers |
| Rosters / player roster status / free agents | 30 / 15 / 60-second memory TTLs | Mutation preflight/readback bypass cache |
| Standings / board list / board thread / pending waivers | 60 / 30 / 15 / 15-second memory TTLs | Explicit refresh/readback can force fresh data |
| Pending trades / assets / transaction activity | Forced client reads; model-level reuse on recent section visits | Fresh trade preflight/readback; no stale or failed read becomes a confirmed-empty state |
| Franchise artwork | Bounded 15-minute memory thumbnails; 60-second failure cooldown | Isolated cookieless loader; no disk cache |

The full player directory and one validated ID index are shared across tabs. A disk hit retains its original age without re-encoding/rewriting the file. Targeted detailed-player and season-schedule caching are implemented in memory; player-scoring history uses bounded targeted pages and separate memory caching, as detailed below. Roster/player pull-to-refresh refreshes volatile roster/ownership state while reusing day-cached league metadata. An explicit team-metadata refresh can bypass that cache. MFL supports incremental `SINCE`, but the app currently refreshes the full public catalog after its daily expiry.

Version 0.3.2 persists only the public, full player directory in the app's Caches folder, scoped by season and cache-format version. Entries retain their original fetch time across relaunches; corrupt, wrong-season, future-dated, and expired entries cannot be used. Decoding succeeds before saving, writes are atomic and size-bounded, and disk failures do not block fresh reads. Score and lineup lookups now use the same full catalog as waivers/trades, eliminating separate per-roster subset downloads. Concurrent cacheable reads still share one request.

Build 28 extends stable league reads to a separate protected 24-hour disk cache, attached only after fresh membership verification. The export includes changing owner balances, so waiver browsing still imposes a 60-second maximum age. Bid submission bypasses both limits and rechecks fresh rules, balance, pool, roster and saved queue. Before imports, persisted league data is detached/invalidated/removed, including on ambiguous outcomes. Display snapshots can retain last-loaded points/projections and summaries but never authorize a change. No private payload enters the public player cache; no cache change introduces automatic write retries. The earlier 0.3.2 memory-only private-storage behavior above is historical.

Scoring and lineup editing now share deterministic positional allocation: required minimums are filled first, with qualifying extra starters displayed as FLEX. Assignment is stable across different feed ordering. Player NFL positions and points remain unchanged; incomplete or unsupported scoring lineups do not get guessed FLEX assignments.

Versions 0.3.5–0.3.6 add user-chosen starter/FLEX placement and atomic two/three-player rotations. Private placements are scoped by season/league/franchise/week and validated against restored starters/rules. Swapping existing starters alone changes no MFL starter IDs and sends no import; changing membership still requires Review & submit. Live scores use the server starter set, not an unsubmitted draft. User-facing copy does not make managers reason about this storage distinction; [lineup documentation](lineup-starter-swaps.md) retains the technical contract.

Version 0.3.3 also retains the validated decoded catalog in memory under the same cache entry and expiry. Completed shared reads publish even if their initiating caller was canceled; forced preflight/readback and invalidation still supersede older reads. Duplicate catalog IDs and malformed trade dates fail closed. Nonfinite/out-of-range Retry-After values use the finite fallback. Successful trade readbacks carry their snapshot to the inbox instead of triggering a duplicate download. Reported active starter clocks can establish live status when team-level live counts are absent. See the [performance and synthetic two-week report](two-week-synthetic-testing.md) for regression evidence and limits.

Version 0.3.0 trades use fresh `pendingTrades` and `assets` reads before every POST and for confirmation. Asset tokens preserve players, `DP_round_pick` (zero-based current-year indices), `FP_franchise_year_round`, and positive `BB_amount` FAAB. Unsupported assets or unverifiable offer direction disable native actions. Missing proposer IDs are inferred only from a unique owner of every non-cash offered asset, never from description text.

A device-only marker is written before a trade POST. A proposal needs a new pending ID with exact recipient, asset sets, comments, and expiration. A response needs positive MFL acknowledgment plus disappearance from the fresh pending list; disappearance after a timeout alone cannot prove acceptance. No trade import is automatically retried. MFL has no atomic counteroffer endpoint: counters are separate offers, with an explicit acknowledgment that the original stays open. Approval, deadlines, and roster enforcement remain MFL's responsibility.

Version 0.3.7 retains those mutation safeguards while fixing presentation state. Response review uses one identifiable action payload and explicit view identity, so first-tap Decline/Withdraw cannot default to Accept. Each composer session has a fresh identity and immutable saved-draft snapshot; Cancel rolls back meaningful autosaves and late callbacks cannot restore canceled edits. Empty/whitespace-only drafts do not persist or enable Save & close. A partner, assets, nonblank message or counteroffer constitutes content; changing only the expiry does not. See [trade interaction/regression evidence](trade-inbox-ux.md).

The request gate rechecks spacing after suspension to prevent resume bursts. Concurrent cacheable exports share their in-flight read; forced mutation preflight/readback never joins it, and an older response cannot overwrite a newer cache entry. Quick foreground transitions and repeated transaction-section visits reuse recent results. HTTP 429 honors the advertised Retry-After duration (90 seconds when absent), with disabled countdown retry controls and no automatic retry loop. Activity uses the documented DEFAULT transaction filter instead of the broader combination that returned invalid parameters.

Build 32 treats both Swift cancellation and Foundation's typed URLSession cancellation (`NSURLErrorDomain` / `NSURLErrorCancelled`, including bridged NSError) as `CancellationError`. No diagnostic-string matching is used. Scores manual/polling and full-refresh reads retain their previous data and warnings rather than reporting cancellation as failure; cancelled full refreshes do not establish the successful foreground cooldown. Actual failures still surface. Transport wrapping stores only the numeric network code, while localized transport messages omit the payload entirely. Do not suppress uncertain mutation outcomes or infer that a cancelled POST was not applied; durable pending markers/readback and no-replay protections remain required.

## League extras — 0.6.0 (33)

See the [implementation contract](league-extras-implementation.md) for exact decoding, recurrence, persistence, lifecycle and failure boundaries.

| Surface | Request | Cache / authority |
| --- | --- | --- |
| Trading Block | export `tradeBait&INCLUDE_DRAFT_PICKS=1` | 5 minutes, original age; protected scoped display snapshot |
| Publish own block | import `tradeBait`, `WILL_GIVE_UP`, `IN_EXCHANGE_FOR` | Fresh exact membership, abilities, assets and baseline before the only POST; durable marker and uncached exact readback |
| Calendar | export `calendar` | Shared 15-minute cache for agenda and waiver processing date |
| Explicit recurring instances | export `ics`, without `JSON=1` | 15 minutes; fetched only for repeating JSON events; JSON anchor validation before UTC interpretation |
| Live Activity | existing current-week `liveScoring` | No new provider; fresh owner matchup and playing-starter clocks, foreground only |

Owner-provided JSON verifies camel-case `willGiveUp` / `inExchangeFor`, an empty container and singleton listing. Unknown assets remain visible but block silent partial replacement; new publication supports players/picks, not cash. Build 35 adds explicit whole-list removal using a separate `removeTradingBlock` entry point: one POST with both `WILL_GIVE_UP=` and `IN_EXCHANGE_FOR=` present. Fresh baseline/account/permission checks and a durable marker still apply. Only successful fresh readback with the owner absent or both asset/needs fields empty confirms removal; an unchanged listing or failed read cannot. MFL documents full replacement but not empty-list semantics. Josh confirmed September 7 that last-player removal works on MFL; this is owner-reported acceptance of that workflow, not an independent payload capture or universal format certification. A timed-out publication/removal is never replayed automatically.

The supplied ICS expands recurring events, rather than providing RRULE/TZID. Its date strings correspond to JSON UTC epochs despite lacking `Z`; all base UID/time anchors must agree before interpreting repetitions. Generated occurrence UIDs change between exports and are not reminder identities. Stable JSON-series IDs plus occurrence indices identify events; explicit future instances preserve the November DST change. Count/shape/anchor mismatches stay partial with no guessed recurrence. Raw private exports are not checked in.

Opt-in reminders use absolute, nonrepeating local notifications for verified future events, at most 32 over a rolling 14-day horizon. Disabled preferences remove alerts even offline; disconnect drains reads and removes app-owned pending/delivered alerts. No commissioner `calendarEvent` import, APNs registration or continuous background scoring is implemented. Apple Calendar handoff uses the system event editor without requesting access to read the user's calendars.

## Distribution and unimplemented data surfaces

The app currently supplies `MFL Blitz/0.1 (com.biggsjm.MFLBlitz)` on sign-in/restore. MFLCore separately defaults to `MFL Blitz/1.0`. Neither string proves registration; confirm production registration and configure the exact approved identity before distribution. Do not change it simply to match the marketing version without considering registered-client identity.

Version 0.4.0 implements the official whole-season `schedule` export, flexible week/matchup/participant decoding, shared timelines and route-local matchup scoring. Configured season bounds drive those timelines; the separate existing Scores/Lineup week picker still uses `1...18`. Schedule `result=T` without a score is not a final tie. Missing opponents are not guessed byes; repeated pairs never select an arbitrary scoring game. See the [schedule contract](schedule-ux.md).

Team rosters always read current membership without `W`. My Team's 0.5.2 position view requests no lineup-assignment week and uses one batched `playerScores(PLAYERS,W=YTD)` read instead, with the existing one-hour cache and explicit refresh bypass. Other-team starter/bench assignments remain a separate batched `playerRosterStatus` read. Generic R/ROSTER membership is not inferred to mean Bench. Missing/failed/duplicate season totals are not replaced with zero or projections. Player Detail aggregates canonical identity, current-franchise acquisition status, potentially multiple ownership assignments, matching-week available metrics and optional supplied biography. Missing bio/status can fail independently, while auth/cancellation propagate. Old-account completions are rejected. Browsing changes no lineup week, draft or trade terms; see [player detail](player-detail-ux.md).

Pre-merge CI on Xcode 16.4 / iOS 18.5 exposed task-allocation crashes during roster assembly, matching the reported [Swift async-let teardown issue](https://github.com/swiftlang/swift/issues/81771). Roster metadata/catalog/membership reads now use a bounded throwing task group that finishes before assignment reads and model mapping. Requests remain parallel, with unchanged caches, session checks and cancellation. Swift's [6.3.1 release notes](https://forums.swift.org/t/announcing-swift-6-3-1/86080) describe upstream fixes for this class of allocator crash; CI compatibility is verified rather than assumed from the newer local compiler.

Player Detail now requests optional targeted `DETAILS=1`; live field population still varies and needs owner validation. A whole-week `weeklyResults` response is not proof of complete player season history. Current lineup/waiver placeholder fields must not be reused as opponent, kickoff or season-total facts. Board HTML currently receives plain-text tag/entity cleanup and is rendered with native Text; richer HTML and safe link handling are unfinished.

MFL expressly forbids browser JavaScript from outside its domains and does not provide permissive CORS. Native `URLSession` is unaffected, which is another reason to remain a genuine native client.

The API does not include raw NFL player statistics or third-party news because of licensing. It also has no documented webhook and no reliable third-party APNs contract. Rich news/play-by-play requires a separate licensed source; push scoring likely requires written MFL coordination plus a minimal backend.


Build 30 makes `DETAILS=1` biography a disclosure-triggered read rather than a dependency of primary identity/ownership (except targeted identity fallback when the catalog cannot name a player). Ordinary card reappearance reuses the detail cache; explicit refresh and roster changes still refresh ownership. Availability reads are shared by the league model across screens, cancelled on scope reset, and interrupted attempts can be retried. UI spinners reflect actual in-flight state; cached/read-only data never grants mutation authority.

Build 31 carries display-only canonical player identity in scoped navigation routes, reusing the source row without another request. Ownership no longer holds first-frame identity or matching-week metrics/research. Pending/failed ownership cannot create Free agent/Starting/Bench claims or enable roster actions; mutation preflight/readback and reconnect boundaries are unchanged. This is not a new private response cache.

## Player tools and roster actions — 0.5.0 / 0.5.1

Build 29 supersedes the earlier View scoring history gate: the primary summary independently loads two targeted cached YTD/AVG reads, while the visible game log loads at most four completed-week score reads per page. One shared public nflSchedule(W=ALL) response and the daily current catalog/bye table supply NFL opponents, explicitly disclosed as the current team's schedule, not historical player-team affiliation. Earlier pages are explicit; no raw NFL statistics or opponent-points-allowed read is needed for the default card. Main-section pull-to-refresh no longer invokes refreshAll; ordinary watchlist/roster review loads use caches, while mutation preflight and readback remain forced. Requests remain globally spaced, now at least 1.25 seconds in the live repository. HTTP 429 records Retry-After by request/response host, matching MFL's documented per-server limits; another host's cached/allowed data can still load. Requests never switch host to evade a cooldown and failed imports never retry. A public-feed cooldown does not automatically block a different league server.

IR controls use the current action week's matching injury snapshot, not the browsed historical week. Out/IR qualify for the conservative native scope verified for Champion Hall; Questionable, Doubtful, unknown/missing, loading, failed and stale data keep Move to IR unavailable. Player Detail hides it and the direct Injured Reserve list includes only qualifying players; review retains its disabled gates, followed by a fresh injury read before import. Broader league-specific IR formats still require certification; this is not a claim that the league export provides all IR eligibility rules.

| Data/action | Request | Cache / verification |
| --- | --- | --- |
| Injury report | export `injuries&W` | 1-hour memory; public/cookieless; source described as daily |
| NFL opponent/kickoff | export `nflSchedule&W` | 6-hour memory; public/cookieless; not a live NFL score feed |
| Bye table | export `nflByeWeeks` | 24-hour memory, season checked; public/cookieless |
| Player history | export `playerScores&PLAYERS&W` | 1-hour memory; targeted IDs, initially four completed weeks; earlier pages explicit |
| Season fantasy metrics | `playerScores&W=YTD` / `AVG` | Independent optional reads; missing is not zero |
| Game-log NFL opponents | export `nflSchedule&W=ALL` plus current catalog and bye table | Shared 6-hour public/cookieless schedule; current-team approximation disclosed in info popover. Missing/ambiguous data stays blank. |
| Optional position context (not on default card) | export `pointsAllowed` | Decoder/client retained; default Player Detail no longer fetches this feed |
| Watchlist | export/import `myWatchList` | 60-second memory; incremental ADD/REMOVE, forced readback |
| Owner permissions | `abilities&DETAILS=1` | 30-second client cache reused for browsing/review, bypassed for mutation preflight |
| Immediate add/drop | import `fcfsWaiver` | One ADD and optional DROP, or deliberate drop-only |
| IR | import `ir` | DEACTIVATE or ACTIVATE; optional explicitly reviewed DROP on activation |

Abilities use the owner-verified `abilities.franchise.id` and unique ability IDs WAIVERS, DROP, INJURED_RESERVE with value 1. Descriptions do not grant permissions. The supported initial write path requires one roster per player, league-wide ownership, no salaries/contracts, known positive roster limits and explicit current active/IR statuses. Unknown formats/capabilities stay non-actionable.

FCFS adds additionally require FCFS/BBID_FCFS configuration, fresh free-agent membership, explicit is_fa=true and no existing ownership. MFL documents cant_add/locked as optional restrictions on free agents: omitted or false flags pass this part of preflight; present null, unknown, true or conflicting aliases block it. Omission alone never proves free agency or a lineup unlock. The owner's supplied player 9431 response is rostered to franchise 0008 with status S and correctly cannot pass an add preflight. IR deactivation requires an Out/IR report; MFL enforces final league-specific eligibility, positional limits and deadlines. No reserve move is inferred from the displayed FLEX/starting slot.

The 0.5.2 detail follow-up preserves the decoder's `canAddImmediately` result through `PlayerOwnership` instead of reconstructing permission from nullable display flags. The visible Add control gates on that decision and the acquisition franchise, with no extra per-render requests. Generic `locked`/`cant_add` flags do not supply a cause or unlock time: newly dropped-player waivers, game locks and other restrictions must not all be labeled “On waivers.” Mixed BBID/FCFS support remains enabled; a player-specific restriction does not close first-come adds for every free agent. Fresh mutation preflight/readback and no-retry protections are unchanged.

Roster reviews load roster, limits and abilities through their normal caches; submission compares that complete reviewed membership/limits against forced-fresh preflight. A device-only scoped marker is saved before the only POST. Exact full membership/status and any explicit drop are read back uncached. A timeout does not cause retry; unresolved changes remain discoverable in My Team with Check status/MFL/acknowledgement. Roster-affecting imports share a repository gate. Acknowledgement clears only the marker, not an MFL move. Successful changes invalidate roster/pool/status/activity caches and refresh existing draft-safe mergers.

Watchlist markers contain only player ID, desired state and time. Roster markers contain the requested move, scope and expected membership. Both survive relaunch; neither is stored in the public player cache. Explicit disconnect removes them. No private history/watchlist response disk cache was added.

Wire evidence and remaining owner verification: [player-tools plan](player-tools-plan.md). Current 2026 completed-game history and season-summary coverage still need actual Week 1 observation; fixtures do not close that gate.
