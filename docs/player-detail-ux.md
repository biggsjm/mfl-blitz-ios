# Player and team detail

Status: **Extended player tools and My Team refinement — private build 0.5.2 (21)**, September 6, 2026. See [current status](current-status.md) for exact installation/test evidence and [roadmap](roadmap.md) for remaining work.

## Navigation and action boundaries

Tabs are **Scores / Lineup / My Team / Standings / Board**. My Team replaces only Transactions. Its native tab icon is a 26-point franchise thumbnail, with initials fallback and a visible label. Lineup remains the dedicated editor.

My Team's 0.5.2 follow-up is one scrolling page: team identity, current official league standing, matching **Transactions / Schedule / Watchlist** navigation cards, and a position-grouped roster. Schedule and Watchlist are pushed destinations, not segmented tabs. **Manage roster** opens separate reviewed add/drop/IR workflows. Waivers / Trades / Activity, existing available-player search, saved drafts and reviewed writes stay in Transactions. The trade-specific attention badge appears on the tab and Transactions entry. Other teams never display the owner's transaction inbox.

| Surface | Implemented player/team entry | Action preserved |
| --- | --- | --- |
| My Team / other team roster | Canonical player row → Player Detail | Read-only; no second lineup editor |
| Lineup starters/bench | Identity → Player Detail | Separate Start/Replace arrows and swipe actions |
| Matchup detail | Populated player cell → Player Detail; team identity → team roster | Scoring stays primary |
| Standings | Team row → team roster | Official order and owner names |
| Schedule matchup | Team identity → that team's Schedule | Route-local week, not lineup selection |

Waiver candidates link by canonical identity; trade terms and asset pickers provide separate information controls. Their modal navigation stacks register the same scoped destinations. In those pickers, selecting assets must stay the primary action; picks, FAAB and unknown tokens must never become player links. Activity and board prose are not parsed to guess IDs. A contextual Propose trade shortcut must not overwrite an existing draft.

## Team roster

Current membership comes from `rosters(FRANCHISE)` **without a week**. My Team requests no lineup-assignment week; it replaces that status read with one batched `playerScores(PLAYERS,W=YTD)` request for its roster. Normal reads use the existing one-hour score cache; explicit roster refresh reloads volatile membership and totals, retaining daily league/catalog caches. Rows are grouped QB/RB/WR/TE/etc., then sorted descending by finite season-to-date points. A real zero sorts above negatives; unknown values appear last as “—”, with name/ID tie-breaking. Projections, weekly scores and old placeholder `seasonPoints` fields are never substituted. IR/taxi membership remains a small row label. The old assignment callout and Starting/Bench groups are absent on My Team.

Other-team rosters retain their existing assignment-based view: a separate batched `playerRosterStatus(P,W,F)` read supplies assignments for the explicitly selected context. This does not claim historical roster membership.

- Known starters and nonstarters appear in Starting and Bench groups.
- Generic R/ROSTER membership stays neutral Roster, never inferred Bench.
- IR and taxi membership remain authoritative over week-specific assignments.
- Unknown states, incomplete assignments and missing identity data remain explicit.
- Salary/contract fields appear only when supplied. Reading them does not implement roster management.
- An empty successful roster differs from an unavailable/failed response.
- Refresh failure retains prior content with an error; another account/team's data cannot replace it.

## Initial Player Detail

The page includes canonical identity, current league ownership/status, exact-matching-week available projection/points/stat line, and supplied biography. It also includes official availability, progressive history and a watch star. Applicable owner/free-agent actions open a separate roster review; they never submit from an identity tap.

Ownership can contain multiple franchise assignments and acquisition availability for the signed-in franchise simultaneously. Acquisition locks are not lineup locks. Missing ownership is not a free agent. Team names link back to the shared team destination.

### Compact roster actions — 0.5.2 (21) follow-up

Player Detail places compact native bordered controls **inside the ownership card**, separate from its team navigation link. The owner's final symbol choices are **person.badge.plus** for Add, **person.badge.minus in red** for Drop, and a **neutral cross.case (medical bag)** for Move to IR. All three are symbol-only controls with at least 44-point touch targets and spoken action/player labels. Move to IR appears only for the signed-in owner's active-roster player with a current qualifying designation; ineligible/loading/unknown states omit the button and explanation. Existing IR players retain labeled **Activate**, which can stack at large text sizes. There is no extra full-width action card or hidden overflow menu. Existing review, Cancel/Close and final confirmation remain mandatory; a detail button never submits a roster change. Manage roster's separate menu still dims ineligible IR; this follow-up changes the detail screen.

Two independent AI design reviews (native iOS layout and accessibility/usability, not a human study) favored visible compact controls over hiding just two actions in a menu. Apple's [short-menu guidance](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons) and [button hierarchy and touch targets](https://developer.apple.com/design/human-interface-guidelines/buttons) informed this layout. NN/g's [icon-label research](https://www.nngroup.com/articles/icon-usability/) informed the initial labeled proposal; the owner's explicit preference superseded it with the Add/Drop/IR symbols above. Accessible action names remain.

**Add player** uses the same strict decoded acquisition decision as submission preflight, scoped to the signed-in franchise. Explicitly unlocked free agents remain actionable, including supported FCFS periods in mixed BBID/FCFS leagues. Known locks/denials and malformed, contradictory or unconfirmed acquisition data cannot open immediate-add review. Generic flags receive **Locked for adds**, **Adding unavailable**, or **Add availability unconfirmed**, not a guessed waiver reason or unlock date. A player may be a free agent but individually locked after a drop. Review still freshly checks owner abilities, league format, roster capacity and player availability; browse data is not permission to submit.

The action controls add no network requests or new caches. A deterministic locked preview free agent exercises the disabled state. See [current status](current-status.md) for verification and installation status.

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

Player history, waiver/trade links and reviewed roster actions are implemented in [player tools 1–5](player-tools-plan.md). Still remaining:

1. Complete manual accessibility, smaller-screen/iPad and older-supported-OS validation.
2. Verify optional live biography population; any licensed news/images/stats require source/rights review.

No Players tab, new global search destination, full-player directory screen or second lineup editor is introduced. This increment does not close Week 1 live validation or Week 2 distribution gates.
