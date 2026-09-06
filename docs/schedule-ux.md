# Season schedule UX proposal

Status: **NOT IMPLEMENTED — design proposal**, September 6, 2026. Coordinated with the player/roster and native-app/Transactions workstreams. The shipped 0.3.7 (16) navigation is unchanged; no Swift implementation is included here.

## Recommendation

Use **Scores · Lineup · My Team · Standings · Board**. Lineup remains a dedicated tab because setting starters is a priority. My Team replaces Transactions in the third, center position. Reuse the existing player search within Transactions; moving that hub carries its search with it. Add neither a Players tab nor another global search destination for this design.

My Team is the team hub: a compact identity header, a prominent Transactions destination, and **Roster / Schedule** sections. Its roster is for browsing and player details; the dedicated Lineup tab owns starter editing and submission. Other-team destinations reuse **Roster / Schedule**, titled with the franchise name and with a read-only roster. Add a league schedule destination from Scores. Both schedules use the same season data and week sections.

| User need | Entry | Destination |
| --- | --- | --- |
| My remaining opponents | **My Team** bottom tab, then **Schedule** | My team → Schedule |
| Crouton Bug Eaters, Route Runners, or any other team | Tap a team in Standings, then Schedule | Selected team → Schedule |
| Every matchup in the coming weeks | **Season schedule** beside Around the league on Scores | League schedule, all teams |

Keep the Season schedule link separate from the existing whole-card matchup links. The My Team tab makes an additional My schedule shortcut on Scores unnecessary in the first version. Keep the Scores toolbar’s existing Settings and week picker; reuse Transactions search instead of adding another search entry.

## Shared team destination

`TeamDetailView(franchiseID:, initialSection:)` has a compact team identity header (artwork, full name, owner and current record when available), followed by Roster / Schedule. For the signed-in team, put Transactions between the header and those sections, keeping it accessible whichever section is selected.

- Standings team rows and explicit team identity links inside Matchup Detail open Roster by default.
- The My Team tab defaults to Roster on first opening and preserves the section during the current session. Explicit schedule routes and opponent-team links from schedule contexts open Schedule directly.
- Roster rows open the shared `PlayerDetailView` with the canonical MFL player ID.
- The dedicated Lineup tab retains Starting and Bench groups and explicit Start/Replace/Submit actions. Keep player identity taps independent from those actions. My Team → Roster and other-team rosters are browsing surfaces; do not create a second lineup editor.
- Do not change the selected team when switching Roster / Schedule.
- Keep an explicit League schedule link in the Schedule section. The league schedule has one team selector: All teams, My team, then the named franchises. Selecting a franchise navigates to the same team destination on Schedule. Changing teams within that destination preserves the selected section.

The player workstream owns shared player detail, its integration with existing search, and the shared team/roster shell. The schedule work owns the schedule data, timeline content, and its explicit deep links. The native-app workstream owns the current transaction hub and mutation behavior. Agree on typed routes before concurrent implementation touches AppTabView, Scores, Standings, or Matchup Detail. All three workstreams have been notified of the final tab order; the current proposal does not authorize a navigation implementation or change the ongoing build/install work.

## Transactions inside My Team

Push the existing Transactions hub from a labeled row visible above Roster / Schedule. Retain its Waivers / Trades / Activity structure. This adds one tap to inbox access, so preserve its attention badge both on the My Team tab and on the Transactions entry. The current needsAttentionCount is trade-specific (incoming, unresolved, and unconfirmed actions); do not label it as an aggregate lineup/waiver count.

Existing Transactions player search and player details can open the appropriate existing waiver or trade editor directly, using shared drafts and review flows. Preserve search/scroll state on return. Trade team identities can open the shared team destination. In trade asset selection, keep selection as the row’s main action and provide a separate player-info affordance. Preserve the current trade editor/review view identities that prevent stale sheet state, as confirmed by the 0.3.7 release workstream.

Current search scope is available players in Transactions → Waivers, not the entire player pool. Reuse it as such. Rostered players reach shared Player Detail through Lineup, team rosters, matchup player cells, and player-kind trade assets. If all-player lookup is requested later, consider extending this existing search with an explicit scope rather than adding another search entry.

Do not place the signed-in team’s transaction inbox on another franchise’s page as if it belonged to that franchise. A context-appropriate Propose trade action can open the existing composer instead.

## Center logo and Liquid Glass feasibility

Recommended: use the native TabView, with My Team third among five ordinary tabs. Put a compact version of the signed-in franchise’s logo in its icon slot and keep the **My Team** text label. Center placement and a recognizable logo provide emphasis without changing the tab’s navigation behavior.

Apple’s [Tab API](https://developer.apple.com/documentation/swiftui/tab) supports custom images and custom label initializers. A pre-rendered UIImage, passed as an Image with original rendering, is the proposed route for runtime team artwork; keep image loading and caching outside the tab label, reuse the existing artwork loader, and provide a stable initials/symbol fallback. Start with a roughly 24–28 point icon, then visually validate the system’s final layout. This size is a prototype target, not a guaranteed native metric.

Standard navigation components receive the platform’s Liquid Glass appearance when built with the appropriate SDK; let the system draw the bar, selection, and touch feedback ([Apple adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)). The app currently targets iOS 18, so keep native tabs on older supported versions as well. Native layout adapts on iPad and in other size classes; a permanently bottom-centered hero is an iPhone portrait design intent, not a cross-device layout guarantee.

The public APIs reviewed do not expose a per-tab raised, oversized center button. My conclusion is that a large logo protruding above the bar would require a custom navigation treatment. Apple supplies [glassEffect for custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), but that would add responsibility for layout, selected states, safe areas, accessibility, and older-OS behavior. Reserve the large team-logo treatment for the My Team page header; start with a normal-sized logo in the native bar.

Validation: official Apple documentation and the installed Xcode 27 SDK were inspected. A standalone SwiftUI probe with all five tabs, the original-rendered UIImage label, and a badge successfully passed swiftc type checking against the iOS simulator SDK with an iOS 18 deployment target. The probe stays outside the app project. Native visual verification remains a follow-up because the sandboxed simulator service was unavailable during this design task. The HTML concept illustrates information layout and does not prove Liquid Glass rendering.

## Schedule content

Open at the current scoring week, with later weeks expanded in chronological order. When the current week is officially completed, start at the next remaining week. Before the season, start at the configured first week. Keep earlier weeks behind a single **Show earlier weeks** disclosure. In a completed season, show season results rather than an empty upcoming list.

For one team, each week shows opponent artwork and full name. Add the opponent’s **current** record as quiet context when available. Use home/away labels only when supplied and meaningful to the league. For All teams, each week contains compact two-team matchup rows, highlighting the user’s matchup with text as well as color. Do not repeat the large live scoreboard cards for every week.

Week headers show week number and verified date range if available. Separate regular season and playoffs using league configuration. Future games have an Upcoming label and no artificial 0–0 score, projection, or win probability. Current games can show a lightweight live total; completed games use official results.

The list is continuous: scrolling is the primary way to browse. Do not add a calendar grid, an Upcoming / Past / All segment, or a second required week picker. The existing Scores week picker continues to serve detailed single-week viewing.

Known matchups open a route carrying the season, league, week, and exact matchup identity. Future matchup detail shows the scheduled teams and their team links; player scores or projected starting lineups must not be fabricated. Back restores the schedule’s team and scroll position. Keep team links independent of matchup-row navigation.

## Data and state

The code currently loads liveScoring for non-completed weeks and weeklyResults for completed weeks. There is no fantasy season schedule endpoint, decoder, or repository method yet. The existing MFLLeague model already decodes startWeek, endWeek, and lastRegularSeasonWeek; the UI currently uses a hardcoded 1...18 week picker.

Add a league/season-scoped schedule read, validate the exact official MFL request and wire schema during implementation, and decode a week containing zero or more matchups. Prefer a whole-season read if supported; otherwise use bounded, cached week reads. Never build the season list by fetching every week’s full live player scoring. Share one cached dataset between league and team schedules, with cached display, freshness text, pull to refresh, and commissioner-change refresh on re-entry when stale.

Schedule selection must be independent of AppModel.selectedWeek. That value also controls Lineup today. MatchupDetailView currently finds its matchup inside model.scores, so it needs a route-scoped data lookup before it can safely be reused for arbitrary schedule weeks. Proposed routes:

- `TeamRoute(franchiseID:, initialSection: .roster/.schedule)`
- `ScheduleRoute(season:, leagueID:)`
- `MatchupRoute(season:, leagueID:, week:, matchupID:)`
- `PlayerRoute(playerID:, entryContext:)` with optional inspected week and the caller’s league/session context

Team switching and section changes filter cached schedule data. Live score refresh remains bounded and foreground-only; opening a season view should not start a poller per week.

Player history and other-team roster browsing also use local season/week state. Their browsing context does not change AppModel.selectedWeek or an active lineup draft. Ownership and player actions resolve against the active league and the applicable current action week, even when the player card was reached from a historical or future schedule.

## Necessary edge cases

- Multiple opponents in one week remain separate rows under that week. Do not key a matchup by team/week alone. MFL supports multiple games, league-average opponents, and median matchups ([official feature description](https://home.myfantasyleague.com/features)).
- Explicit Byes, unscheduled weeks, fetch failures, and undecided playoff opponents are distinct states. A missing matchup is not evidence of a bye.
- Show **Opponent TBD** for known playoff slots only. Do not imply that a team has qualified for a playoff round before that is established. If the bracket is not yet available, use one **Playoff matchups have not been set** note.
- Use the configured season bounds, including shortened seasons. Do not synthesize 18 fantasy weeks.
- Total-points and other formats without head-to-head opponents explain their format instead of presenting a broken empty matchup list.
- Keep long team names readable, use 44-point controls, support Dynamic Type, and announce week/opponent/status together for VoiceOver.

## First implementation acceptance checks

1. My Team → Schedule and Standings → own team → Schedule show the same opponents for the same franchise.
2. Switching Roster / Schedule preserves the franchise; player identities still open the player card with independent Start/Replace/Add actions.
3. Every remaining scheduled week is reachable by scrolling; the league view includes every matchup once.
4. Browsing any team/week and returning leaves Scores selection, Lineup week, and unsaved lineup edits intact.
5. Explicit byes, doubleheaders, missing schedule data, and undecided playoffs render distinctly.
6. Loading the season schedule does not fetch every week’s player scoring or duplicate requests when changing teams.
7. Back navigation restores selection and scroll position, including after a matchup or player detail visit.

Defer strength-of-schedule rankings, projected season records, calendar export, notifications, a separate schedule or Players tab, and a custom raised tab bar. They are not needed for the requested schedule and team navigation.
