# MFL 2026 API integration

Primary sources: [general API guidance](https://api.myfantasyleague.com/2026/api_info), [request reference](https://api.myfantasyleague.com/2026/api_info?STATE=details), and [sample code](https://api.myfantasyleague.com/2026/api_info?STATE=example).

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
| League/capabilities | `export?TYPE=league&JSON=1`; authenticated `TYPE=abilities&DETAILS=1` |
| Live scores | `export?TYPE=liveScoring&W={week}&DETAILS=1&JSON=1` |
| Final results | `export?TYPE=weeklyResults&W={week}&JSON=1` |
| Roster | `export?TYPE=rosters&FRANCHISE={id}&W={week}&JSON=1` |
| Player lineup state | `export?TYPE=playerRosterStatus&P={ids}&W={week}&F={franchise}&JSON=1` |
| Submit lineup | `import?TYPE=lineup&W={week}&STARTERS={ids}&TIEBREAKERS={ids}` |
| Free agents | `export?TYPE=freeAgents&POSITION={position}&JSON=1` |
| Saved waiver requests | `export?TYPE=pendingWaivers&JSON=1` |
| Submit conditional BBID round | `import?TYPE=blindBidWaiverRequest&ROUND={n}&PICKS={add_bid_drop,...}&REPLACE=1` |
| Standings | `export?TYPE=leagueStandings&COLUMN_NAMES=1&ALL=1&JSON=1` |
| Board summaries | `export?TYPE=messageBoard&COUNT={count}&JSON=1` |
| Board thread | `export?TYPE=messageBoardThread&THREAD={id}&JSON=1` |
| New board post | `import?TYPE=messageBoard&SUBJECT={subject}&BODY={body}` |
| Board reply | `import?TYPE=messageBoard&THREAD={id}&BODY={body}` |

`playerRosterStatus` is the authoritative readback for saved starter assignments (`S` and `NS`). MFL documents `locked` only for free-agent acquisition state, not rostered-player lineup deadlines, and does not expose a saved lineup tiebreaker. The app therefore uses NFL game progress only to disable obviously started players, lets MFL enforce the league's final lock rules, and describes tiebreaker submission as sent rather than readback-confirmed.

For a blind bid, `0000` is the no-drop sentinel. Conditional leagues require `ROUND`; `REPLACE=1` means the app must send the complete desired state for that round. MFL offers no idempotency key or dry-run mode.

The private Week 1 build persists the cookie and scoped drafts in device-only Keychain items using [Apple’s When Unlocked accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly). Restored cookies undergo fresh membership/franchise verification. The public `mfl_status` request carries no cookie; its `CurrentWeek`, `LineupWeek`, and `CompletedWeek` are distinct. Completed weeks use fresh `weeklyResults` reads.

Blind-bid writes compare fresh pending requests with the user-reviewed baseline, then verify the entire intermediate queue after each changed round. Empty `PICKS` explicitly clears a round. A failed request stops the sequence and triggers readback, not resubmission. Unknown queue structures fail closed. Calendar dates use explicit future `WAIVER_BBID` events when available; recurrence is not guessed. Recent processed acquisitions use `transactions` filtered to `BBID_WAIVER,WAIVER,FREE_AGENT`; the MFL website remains the full processing report.

Before a board import, a durable marker records the intended body, subject/thread, and existing IDs. Readback must find a new post with the same owner and full body; new threads require a thread-detail fetch, not just a matching summary subject. An ambiguous send remains blocked across relaunch until readback confirms it or the user explicitly verifies MFL and resolves the warning.

## League 41333 profile

The supplied [Champion Hall league metadata](https://www45.myfantasyleague.com/2026/export?TYPE=league&L=41333&JSON=1) reports:

- 12 franchises in Faulk, Warner, and Bruce divisions;
- 18-player rosters plus three IR positions;
- nine starters: QB 1, RB 2–4, WR 3–5, TE 1–3;
- partial lineups disallowed and one nonstarter tiebreaker;
- conditional `BBID_FCFS`, up to eight rounds, $100 season limit, $1 increment;
- standings order `PCT,H2H,PTS,DIVPCT`.

These values explain the app's conditional queue and flexible position-count validator. They must remain dynamic in production.

## Defensive client rules

1. Keep player and franchise IDs as strings, including leading zeroes.
2. Decode numbers and booleans from MFL's string-valued JSON fields.
3. Support both singleton objects and arrays where MFL varies container shape.
4. Inspect the body for JSON `error.$t` or XML `<error>` even when HTTP status is 200.
5. Space API requests by at least one second. Poll live scoring at roughly 90 seconds or slower, with jitter.
6. Cache the player directory for a day and use `SINCE`; cache rules and league configuration aggressively.
7. Honor 429 without an immediate retry. Show cached data and a clear stale state.
8. Never blindly retry a write. Refetch submitted state first after an ambiguous outcome.
9. Authenticate priority workflows even when an individual league exposes some score/roster endpoints publicly.
10. Reject or replace arbitrary non-HTTPS franchise artwork; never add a global ATS exception.
11. Redact passwords, cookies, bid amounts, and message bodies from logs and diagnostics.
12. Keep unsupported league configurations read-only with an explicit handoff to the MFL web report.

## Platform constraints

MFL expressly forbids browser JavaScript from outside its domains and does not provide permissive CORS. Native `URLSession` is unaffected, which is another reason to remain a genuine native client.

The API does not include raw NFL player statistics or third-party news because of licensing. It also has no documented webhook and no reliable third-party APNs contract. Rich news/play-by-play requires a separate licensed source; push scoring likely requires written MFL coordination plus a minimal backend.
