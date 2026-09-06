# Player and team detail proposal

Status: **NOT IMPLEMENTED — coordinated design**, September 6, 2026. Based on the player, schedule and native-app task handoffs, reconciled against 0.3.7 (16). No Player Detail repository operation, team detail view, or navigation migration is included in that build.

## Final navigation direction

**Scores / Lineup / My Team / Standings / Board.** Lineup stays one tap away. My Team replaces only Transactions in the center, using a native-size franchise logo plus visible label/fallback, subject to device validation. A separate five-tab prototype typechecked; it did not verify native visual rendering. See [schedule/team design](schedule-ux.md).

My Team has a compact identity header, a prominent pushed **Transactions** entry, then read-only **Roster / Schedule** sections. Transactions retains Waivers / Trades / Activity and its existing available-player search. No Players tab, extra global search button or standalone directory is planned. All-player search is not a committed requirement.

Other-team detail reuses Roster / Schedule. Standings rows and explicit team identities inside matchup detail open Roster; schedule-context team links open Schedule. Team rosters browse players, while dedicated Lineup remains the only lineup editor. The signed-in owner's inbox must not appear to belong to another team. A contextual Propose trade action can enter the existing composer without overwriting an existing draft.

## Player entry points and action separation

| Surface | Player-detail entry | Existing primary action to preserve |
| --- | --- | --- |
| Lineup starters/bench | Player name/identity | Start/Replace arrows and swipe actions |
| Team roster | Compact player row | Read-only browsing, no second lineup editor |
| Matchup detail | Populated starter/bench/unclassified player cell | Score-first layout and explicit team links |
| Waiver search/candidates | Player identity; optionally claim-editor header | Plus/check adds or edits claim; queued-claim row remains Edit claim |
| Trade terms/detail | Player-kind asset identity | Offer review and response controls |
| Trade asset picker | Separate player-info affordance | Row tap remains asset selection |

Picks, FAAB and unknown assets are not player links. Activity and recent waiver results can gain links later, after their models preserve structured IDs instead of combined prose. Never infer player IDs by parsing display names or auto-link board messages.

## Proposed page

1. Identity header: name, NFL position/team and optional verified headshot with position/monogram fallback.
2. Current league ownership/availability and authoritative roster status, including multiple ownership assignments where applicable.
3. Applicable league projection and current fantasy points, labeled with their week and freshness. Missing is not zero; pregame, bye, absent data and a genuine zero are different states.
4. Season-selectable weekly fantasy-scoring rows. Prefer a vertically readable list with optional disclosure over a wide horizontal statistics table.
5. Secondary bio and salary/contracts only when supplied and meaningful in this league.

Manage lineup, Add claim and Propose trade route into existing reviewed workflows; detail adds no new mutation path. Keep copy short and let symbols/labels explain actions. Choosing a historical season/week does not imply historical ownership is current or change the action week silently.

## Existing data versus missing work

The following is code evidence, not a promise that all optional fields are populated by MFL:

- `MFLPlayer` already has ID/name/position/team/status, jersey, birth date, height/weight and draft year/round. `MFLClient.players(ids:details:)` supports targeted `DETAILS=1`; production currently uses the basic shared catalog. Validate optional live bio population before relying on it.
- `rosters(franchiseID:week:)` and `MFLPlayerRosterStatus` expose ownership, potentially multiple assignments, starter/nonstarter/IR/taxi states, and roster salary/contract fields. Generic roster membership alone does not prove bench status. Preserve unknown states.
- Projection and live/final-scoring infrastructure exists; `MatchupPlayer` has optional points and a formatted stat line. `weeklyResults` currently force-refreshes a whole week. It does not establish complete player season history, including unrostered weeks.
- Player identity is duplicated across `MatchupPlayer`, `LineupPlayer`, `WaiverCandidate` and `TradeAsset`. Add shared identity/row primitives without conflating context-specific metrics or actions.
- There is no shared Player Detail or team-detail model/repository operation yet. Validate a suitable official scoring-history read and cache by league/season/player. Do not fan out 18 forced `weeklyResults` requests on first open.

### Do not present placeholders as player research

Live lineup currently sets opponent to a dash and game time to `Date()`. Its `seasonPoints` field comes from a weekly live score, not a season sum. Waiver season points/rostered percentage/trend are zero or empty placeholders; current waiver UI avoids presenting those as genuine metrics. A new page must not reuse them as facts.

No headshot provider, licensed raw NFL statistics/news, ADP, college, full draft history, opponent ranks, or reliable injury/schedule enrichment is integrated. Verify official exports and image/content rights before adding providers. Optional enrichment is not required to ship a truthful initial page; see [API constraints](api-integration.md).

## Routes, state and implementation boundaries

- Use canonical-ID typed routes: `TeamRoute(franchiseID:, initialSection:)`, `ScheduleRoute(season:, leagueID:)`, `MatchupRoute(season:, leagueID:, week:, matchupID:)`, and `PlayerRoute(playerID:, entryContext:)` with the caller's league/session and optional inspected week/season.
- Browsing state stays independent of `AppModel.selectedWeek` and all active lineup drafts. Resolve ownership/actions against the applicable current league/action context, not inferred historical ownership.
- Register player destinations in modal navigation stacks that expose them. Preserve the unique trade composer/review identities introduced in `e779e4b`; use existing draft-conflict/review flows instead of silently replacing a draft from Player Detail.
- Preserve the current trade-specific attention count on My Team and its Transactions entry. It is not an aggregate lineup/waiver warning badge.
- Coordinate shared AppTabView, Scores, Standings, Matchup Detail and team shell edits before implementation. Player/team work owns shared identity and roster/detail surfaces; schedule work owns timelines/data; transaction work retains mutation safety.

## Delivery sequence and acceptance

1. [ ] Shared routes/team shell coordinated with schedule work, preserving dedicated Lineup and existing search scope.
2. [ ] Player-detail domain/repository and truthful initial sections, with progressive loading and explicit missing/unsupported data.
3. [ ] Contextual links from existing surfaces; independent selection/action targets and draft-safe return navigation.
4. [ ] Reliable cached history enrichment after endpoint/schema validation; optional licensed images/news/stats later.
5. [ ] Tests for back/scroll/search preservation, missing fields, multiple ownership, action separation, Dynamic Type/VoiceOver, and no mutation or lineup-week changes from browsing.

The [roadmap](roadmap.md) places this work after the current release baseline. These designs do not mark Week 1 live validation or Week 2 distribution gates complete.
