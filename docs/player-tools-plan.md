# Player tools and roster actions

Approved by Josh September 6, 2026, after **0.4.1 (18)**. Implemented in 0.5.0 (19), with owner-feedback fixes in 0.5.1 (20) and 0.5.2 (21), followed by **0.5.3 (22–26)** direct-tool navigation and the [shared standings pattern](standings-pattern.md). Build 21 adds compact player actions, strict visible Add gating and the My Team season-roster refinement. Implementation and automated verification are separate from live-owner certification. [Current status](current-status.md) records exact device/test evidence; [roadmap](roadmap.md) retains release gates and remaining work.

## Scope and sequence

Keep Scores / Lineup / My Team / Standings / Board. No new main tab or global player directory. Preserve the existing selected week, lineup edits, trade drafts, waiver queue, and navigation state while browsing.

| Order | Approved feature | Surfaces | Documented MFL requests |
| --- | --- | --- | --- |
| 1 | Injury, kickoff, opponent and bye information | Player rows, Lineup/replacements, Player Detail | `injuries`, `nflSchedule`, `nflByeWeeks` |
| 2 | Better player research | Player Detail and contextual player links | `playerScores` by week / `YTD` / `AVG`, `pointsAllowed`; existing projections |
| 3 | Synced watchlist | Star on Player Detail; My Team Watchlist and waiver filtering | export/import `myWatchList` |
| 4 | First-come add/drop | My Team → Adds / Drops, with explicit add/drop review | import `fcfsWaiver`; fresh `abilities`, `league`, `rosters`, `freeAgents`, `playerRosterStatus` |
| 5 | IR management | My Team → Injured Reserve and contextual player actions | import `ir`; fresh capabilities, rules and roster/status readback |

Champion Hall's September 6 public configuration reports `BBID_FCFS`, conditional bidding, three IR spots, no taxi squad, and up to five keepers. Read rules/capabilities dynamically; never generalize this profile to other leagues or bypass MFL eligibility/deadline enforcement.

## 1 — Player availability

- [x] Decode official injury reports, NFL schedule/kickoffs, and bye weeks with singleton/array and missing-value handling.
- [x] Share season/week caches; load secondary information independently so it never blocks sign-in, lineup or scores.
- [x] Show compact injury/bye badges and opponent/kickoff context. Use local time and explicit source freshness in detail.
- [x] An absent injury record is not proof of health. A missing game is not proof of a bye. MFL injury data is documented as daily, not instant breaking news.
- [x] Do not treat acquisition locks as lineup locks or the schedule export as live NFL scoring. MFL remains authoritative for write eligibility.

## 2 — Player research

- [x] Add league-scored fantasy totals/average and completed-week game history, with a simple recent-form view.
- [x] Load targeted player scores only after View scoring history, initially four recent completed weeks, then explicit Load earlier weeks. Identity browsing makes no history requests. Never fan out 18 forced week requests or request future results.
- [x] Distinguish missing data from a real zero, partial history from complete history, and projections from results. Preserve exact season/week/player/league identity.
- [x] Add opponent fantasy points allowed by position when the feed has verified data (position totals; not per-game averages); avoid suggesting small-sample matchup figures are predictions.
- [x] Extend identity links into waiver/trade surfaces without stealing add/bid/asset-selection taps or losing search, scroll or drafts.
- [x] Do not reuse legacy placeholder season totals, trends, opponent or kickoff fields as research facts. No raw NFL stat/news provider is introduced.

## 3 — Watchlist

- [x] Read the owner's MFL watchlist and expose a clear empty/error/stale state.
- [x] Add/remove using the documented incremental import, then confirm fresh readback. No full-list overwrite or automatic mutation retry.
- [x] Make saved players discoverable from My Team and available-player filtering in Waivers.
- [x] Scope all data/actions to season/league/franchise/session; reject old-session completions. Keep an unconfirmed action visible until reconciled so a timeout cannot silently invert/repeat a toggle.

## 4 — First-come add/drop

- [x] Show native add/drop only for a supported league and current owner capability/window. Unknown/closed capabilities remain non-actionable with MFL fallback.
- [x] Present the selected addition, optional necessary drop and resulting roster impact before any request. Support a deliberate drop-only action where valid.
- [x] Preflight fresh pool, owner roster, league limits, abilities and player acquisition status; reject stale user-reviewed baselines or unsupported duplicate/complex formats.
- [x] Save a durable pending-action marker before sending. Submit once, read back exact membership changes and reconcile uncertain results without retrying the import.
- [x] Refresh affected My Team, lineup, pool, watchlist availability and transaction views without overwriting active drafts. Explain conflicts that now need review.

## 5 — IR management

Follow-up 0.5.2 (21): symbol-only Add/Drop, eligible-only Player Detail IR, strict player-specific Add gating, and My Team's standing/navigation cards/position roster with season-to-date ordering are implemented; [current status](current-status.md) tracks tests/device delivery. This does not add automatic bids or bypass a locked player's next waiver run.

Follow-up 0.5.3 (22): replace the Transactions/Manage roster umbrellas with six [direct My Team tools](my-team-shortcuts.md), Schedule first. Adds / Drops unifies acquisition and owned-player drops; Injured Reserve gets capacity and eligible moves. Existing drafts, scopes, caches, fresh preflight and exact readback remain mandatory. Features 6–9 below and live-owner checks remain unfinished.

- [x] Offer Move to IR / Activate only on the signed-in owner's applicable players, using current roster membership rather than displayed starter slot.
- [x] Show available IR/active-roster capacity and review the move. Check current capabilities, limits and baseline; MFL enforces league-specific injury eligibility.
- [x] Keep Move to IR unavailable without a current matching Out/IR report; loading, missing, stale and failed reports do not qualify. Player Detail omits ineligible IR; build 22's dedicated IR list includes only qualifying players, and review keeps its disabled gates.
- [x] Support explicit activation with a required reviewed drop when necessary; never silently drop a player to make space.
- [x] Reuse the durable roster-action and verification machinery. Confirm the target player's new roster status and any intended drop before declaring success.
- [x] Keep taxi, salary and commissioner-on-behalf writes outside this increment.

## Cache, security and correctness

- Retain the once-daily public player catalog and stable league metadata cache, shared in-flight reads and foreground-only score polling. Default spacing is now 1.25 seconds. Cooldowns apply to the rejecting server; no request changes host to bypass one.
- Pull-to-refresh targets the visible main section. Roster review/ordinary watchlist reads reuse caches; only confirmed mutation preflight/readback forces fresh data.
- Cache public availability separately from private league research/watchlists. Targeted history uses bounded memory entries and completed-week-aware freshness; no new private offline response store.
- Optional data failures must not hide working scores/lineups. Loading and failed reads cannot masquerade as confirmed empty results.
- Use native accessible controls, concise copy, 44-point minimum targets, Dynamic Type and Light/Dark appearances. Confirmation is a centered modal/alert, not a detached popover.
- Never log cookies, private queues, watchlist contents or raw authenticated payloads. Never automatically retry imports after a timeout or cancellation.

## Verification and delivery

- [x] Core request/decoding/cache tests for new endpoints, malformed/duplicate identifiers, absent vs zero, and season/week boundaries.
- [x] Model tests for stale sessions, partial data, progressive request budgets, watchlist persistence/readback and roster-action preflight/recovery.
- [x] Synthetic two-week journeys cover injuries/byes, unavailable history, watch/unwatch, FCFS open/closed, $0 blind-bid regression, IR full/activation/drop, timeout/relaunch reconciliation and preservation of existing drafts.
- [x] Native UI journeys cover discovery, review/cancel, empty/error/loading, separate identity/action controls, large text, and Light/Dark appearances.
- [x] Run full core/app/UI suites and GitHub CI on the supported older toolchain; build signed candidate and install/launch on Josh's phone when available. Final GitHub source `679afeb` passed 75 core tests, 145 app unit functions and all 29 native UI journeys; build 20 installed and launched.
- [x] Update current status, API/cache notes, feature contracts, privacy/security implications, owner checklist and changelog with actual evidence before handoff.
- [x] Push and merge after checks pass, honoring Josh's standing delivery request. [PR #3](https://github.com/biggsjm/mfl-blitz-ios/pull/3) merged September 6 as `b4c9cf9`. Actual intended live writes and Week 1/Week 2 invitation gates remain separate from synthetic QA.

## Queued after 1–5 — do not lose these

6. [ ] Trading block: publish available assets and what the owner wants; browse league listings and start an offer (`tradeBait` export/import).
7. [ ] League calendar: deadlines and upcoming events, calendar export and opt-in local reminders (`calendar`, `ics`).
8. [ ] League polls: view and vote from Board (`polls`, `pollVote`).
9. [ ] Playoff brackets: add configured postseason brackets beside schedules (`playoffBrackets`, `playoffBracket`).

Later candidates, not authorized as part of 1–5: keeper selection, draft tools, multi-league switching, commissioner/accounting tools, broader waiver/taxi/salary formats, widgets and Live Activities. Investigate MFL's `device_tokens` / `add_device_token` before promising push delivery; registration endpoints alone do not establish an APNs delivery contract for Blitz. Raw NFL statistics and third-party news require a separate source and rights review.

## Verified wire evidence — September 6

Josh supplied owner-scoped `abilities.franchise(id).ability(id,value,desc)`: WAIVERS, DROP and INJURED_RESERVE are explicit permissions. Unknown/duplicate IDs, another franchise and non-1 values cannot grant a write. Josh also verified empty `myWatchList: {}` and singleton `player: {id}` responses, plus watched player 9431's `roster_franchise(franchise_id: 0008, status: S)`. Watching another team's player is valid, but never authorizes acquiring them. No credential was requested or retained.

Public injury/schedule/bye feeds were checked against 2026. The nonempty 2025 pointsAllowed export uses `team(id).position(name,points)`; 2026 is currently empty. The implementation labels position totals correctly and does not reuse 2025 figures in 2026. MFL’s league rules page currently requires Out/IR for this league, and none of the owner’s current players was eligible when checked. Synthetic writes are not proof of a real successful FCFS/IR move.

## References

- [MFL 2026 API request reference](https://api.myfantasyleague.com/2026/api_info?STATE=details)
- [MFL general API guidance and data restrictions](https://api.myfantasyleague.com/2026/api_info)
- [Champion Hall league configuration](https://www45.myfantasyleague.com/2026/export?TYPE=league&L=41333&JSON=1)
