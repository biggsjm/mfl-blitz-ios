# Season schedule and My Team

Status: **Initial implementation — 0.4.0 (17)**, September 6, 2026. [Current status](current-status.md) records verification; [roadmap](roadmap.md) records remaining work.

## Information architecture

Use **Scores / Lineup / My Team / Standings / Board**. My Team replaces Transactions in the center, retaining the native tab bar, franchise-logo/initials icon, visible label and trade attention badge. Lineup stays one tap away.

In the 0.5.2 follow-up, My Team contains artwork/name/owner/current record and official league standing, matching **Transactions / Schedule / Watchlist** navigation cards, and a roster grouped by position and sorted by season points. Schedule and Watchlist open separate native destinations. Other-team pages retain **Roster / Schedule**. The roster opens Player Detail; all lineup editing remains in Lineup.

| Need | Entry | Destination |
| --- | --- | --- |
| My opponents | My Team → Schedule | One team's season timeline |
| Another team's opponents | Standings → team → Schedule | Same shell for that franchise |
| Every league matchup | Scores → Season schedule | All-team timeline |
| Switch teams | League schedule → All teams | Chosen team's Schedule |
| Inspect a matchup | Tap a known scheduled pair | That exact week's route-local detail |

Transactions remains a pushed destination with Waivers / Trades / Activity and the existing available-player search. No new Players tab, global search, custom raised tab bar or calendar grid is added. Other teams do not expose the owner's inbox as theirs.

## Native layout

My Team's header and cards scroll with its roster, keeping content reachable at large text sizes. Its Schedule destination owns a separate scroll container, not a nested scroll view. Other-team pages retain their compact header and segmented control. The tab uses a 26-point original-rendered UIImage with bounded, cookieless artwork loading outside the tab label. The system owns material, selection, safe areas and platform-specific placement.

This builds on Apple's [Tab API](https://developer.apple.com/documentation/swiftui/tab), [tab-bar guidance](https://developer.apple.com/design/human-interface-guidelines/tab-bars) and [native material guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass). iOS 18 remains the deployment target; the iPhone center-tab arrangement is not an iPad layout guarantee.

## Timeline behavior

- Current and future weeks appear chronologically; earlier weeks live under one disclosure.
- Freshness uses a quiet, whole-unit label ("Updated just now" / "Updated 2 min ago"), never a ticking seconds counter.
- A finished season shows its results rather than an empty upcoming list.
- Team rows show full opponent identity, its current record when available, and status.
- All-team rows show both participants and mark the owner's matchup using text and an outline.
- Future games say Upcoming, without invented scores, projections or win probabilities.
- A verified current week says This week, not automatically Live.
- Final results require the confirmed completed-week clock; a real zero differs from a missing score.
- Configured start/end/regular-season bounds drive the timeline, including shortened seasons.
- Multiple games stay separate under the week. Only an explicit textual BYE is classified as a bye; missing opponents or an unknown ID are not.
- Unscheduled playoff rounds use one unset-matchups note and do not imply qualification.
- No published head-to-head schedule has its own empty state; errors never become a confirmed empty league.

The separate existing Scores/Lineup Week N menu still uses 1…18. This release changes schedule bounds, not that editor's range.

## Verified API and caching

The official [schedule request](https://api.myfantasyleague.com/2026/api_info?STATE=details&TYPE=schedule) is:

```text
GET https://{resolved-league-host}/{season}/export?TYPE=schedule&L={leagueID}&JSON=1
```

Omit `W` and `F` for the whole season; do not send `W=YTD`. The wire root is `schedule.weeklySchedule`, containing `week` and zero or more `matchup.franchise` entries. Singleton/array shapes are supported. Participant fields include `id`, optional `score`, `isHome`, `result` and `spread`; matchup IDs may be absent.

September 6 read-only verification found future games with `result=T` but **no score**, plus week entries without published matchups. That T is not proof of a final tie. Champion Hall's private schedule correctly requires authentication; public sample schema checks and committed synthetic fixtures are not claims about its actual opponents.

One session-scoped model shares the whole-season snapshot and in-flight read for 15 minutes. Switching teams filters the same data. Pull-to-refresh reloads schedule metadata and season clock; stable league settings remain cacheable. A failed entry has a short cooldown, Retry-After is honored, stale content remains visible, and account invalidation rejects late results. No 18-week player-scoring fan-out, private disk cache or per-week poller is introduced.

## Exact, draft-safe matchup routes

Typed routes include season/league/owner, week and a normalized matchup identity. IDs retain participants, home/away evidence and repeated-pair occurrence. A scoring response is accepted only for the requested week, using a proven source ID or an unambiguous pair. Doubleheaders with ambiguous pair matching fall back to schedule totals rather than opening the wrong game.

Known current/completed games can reuse positional scoring with a destination-local snapshot. Future games show the published teams and team links only. While a current schedule matchup is visible, one foreground poller replaces the scoreboard poller; it never changes the shared Scores/Lineup week. Future weeks do not poll.

Browsing does not modify active lineup edits, placements, saved trade drafts or the scoreboard selection. Back preserves the team/section and the timeline's scrolling context. Session replacement invalidates routes and cached snapshots. Player Detail uses canonical IDs and current ownership, not guessed historical membership.

## Evidence and remaining checks

Core fixtures cover omitted/zero scores, singleton shapes, unscheduled weeks, malformed IDs/weeks, auth errors, whole-season request shape and cache reuse. Presentation tests cover bounds, completion, byes, duplicates, cooldowns, shared reads, stale sessions and preview matchup consistency. Native journeys exercise My Team, other-team and league schedules and draft-safe return. See [current status](current-status.md) for the exact final runs.

Remaining work includes actual Champion Hall schedule comparison, real week rollover/corrections, complete supported-device/accessibility checks and broad unusual-format certification. Optional season player history, strength-of-schedule, calendar export, notifications, licensed enrichment and contextual waiver/trade player links are not part of this initial slice.
