# Player and team detail

Status: **Initial implementation — 0.4.0 (17)**, September 6, 2026. See [current status](current-status.md) for final build/test evidence and [roadmap](roadmap.md) for remaining work.

## Navigation and action boundaries

Tabs are **Scores / Lineup / My Team / Standings / Board**. My Team replaces only Transactions. Its native tab icon is a 26-point franchise thumbnail, with initials fallback and a visible label. Lineup remains the dedicated editor.

My Team places a labeled **Transactions** entry above read-only **Roster / Schedule** sections. Waivers / Trades / Activity, existing available-player search, saved drafts and reviewed writes stay in Transactions. The trade-specific attention badge appears on the tab and entry. Other teams never display the owner's transaction inbox.

| Surface | Implemented player/team entry | Action preserved |
| --- | --- | --- |
| My Team / other team roster | Canonical player row → Player Detail | Read-only; no second lineup editor |
| Lineup starters/bench | Identity → Player Detail | Separate Start/Replace arrows and swipe actions |
| Matchup detail | Populated player cell → Player Detail; team identity → team roster | Scoring stays primary |
| Standings | Team row → team roster | Official order and owner names |
| Schedule matchup | Team identity → that team's Schedule | Route-local week, not lineup selection |

Player links from waiver candidates, trade terms and asset pickers remain follow-up work. In those pickers, selecting assets must stay the primary action; picks, FAAB and unknown tokens must never become player links. Activity and board prose are not parsed to guess IDs. A contextual Propose trade shortcut must not overwrite an existing draft.

## Read-only team roster

Current membership comes from `rosters(FRANCHISE)` **without a week**. A separate batched `playerRosterStatus(P,W,F)` read supplies assignments for the explicitly labeled action week. This does not claim historical roster membership.

- Known starters and nonstarters appear in Starting and Bench groups.
- Generic R/ROSTER membership stays neutral Roster, never inferred Bench.
- IR and taxi membership remain authoritative over week-specific assignments.
- Unknown states, incomplete assignments and missing identity data remain explicit.
- Salary/contract fields appear only when supplied. Reading them does not implement roster management.
- An empty successful roster differs from an unavailable/failed response.
- Refresh failure retains prior content with an error; another account/team's data cannot replace it.

## Initial Player Detail

The page includes canonical identity, current league ownership/status, exact-matching-week available projection/points/stat line, and supplied biography. It is read-only and creates no new write path.

Ownership can contain multiple franchise assignments and acquisition availability for the signed-in franchise simultaneously. Acquisition locks are not lineup locks. Missing ownership is not a free agent. Team names link back to the shared team destination.

Projection/points reuse existing snapshots only when their week matches the entry context. Missing, conflicting or nonfinite values stay absent. No hardcoded zero, guessed opponent/kickoff, placeholder season total or historical ownership is shown as fact. A player reached from another week's schedule may have no metrics until a suitable source is available.

Targeted `players(PLAYERS,DETAILS=1)` enriches basic identity with optional jersey, valid birth date, height/weight and draft year/round. No external headshot/news/raw-stat provider is integrated. Empty biography is omitted; source failures are disclosed.

## Caching, privacy and state

- The public basic catalog remains shared with its existing 24-hour disk cache.
- Targeted detailed-player reads use a separate 24-hour memory cache.
- Roster/status data use the existing short-lived private caches. Pull-to-refresh reloads those volatile reads, not unchanged league metadata/catalog/bio.
- Explicit team-metadata refresh remains available; private payloads are never persisted as public catalog data.
- Typed routes carry season, league, owner and canonical IDs. App/session generation guards reject both late successes and late failures after account replacement.
- Destination-local reads never change `AppModel.selectedWeek`, its scoreboard, lineup membership/placements, or saved trade draft.
- Team/player model revisions reject older selections. Freshness wording distinguishes assembly time from an explicitly refreshed source.

## Verification and remaining acceptance

Implemented regressions cover canonical routes, current-roster requests, generic/unknown assignment states, multiple ownership, missing optional fields, invalid dates, matching-week metrics, cache request counts, refresh errors and stale-session completion. Native journeys cover team/roster/player navigation, action separation and draft-safe return; final evidence lives in [current status](current-status.md).

Still remaining:

1. Validate a suitable official scoring-history endpoint and cache progressive player/week results. Do not fetch 18 forced full-week results on first open.
2. Add player links in waiver/trade surfaces, register destinations inside their modal navigation stacks, and test search/selection/scroll restoration.
3. Add contextual reviewed actions only through existing mutation workflows and draft-conflict handling.
4. Complete manual accessibility, smaller-screen/iPad and older-supported-OS validation.
5. Verify optional live biography population; any licensed news/images/stats require source/rights review.

No Players tab, new global search destination, full-player directory screen or second lineup editor is introduced. This increment does not close Week 1 live validation or Week 2 distribution gates.
