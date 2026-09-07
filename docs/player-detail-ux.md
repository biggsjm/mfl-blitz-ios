# Player and team detail

Status: **Player-card and matchup refinement — candidate 0.5.4 (31), installed baseline 30**, September 7, 2026. See [current status](current-status.md) for exact installation/test evidence and [roadmap](roadmap.md) for remaining work. The owner confirmed corrected matchup Back navigation on build 29 and the spinner fix on build 30. Remaining primary-card latency is addressed in build 31; completed-week scoring still needs owner validation.

## Navigation and action boundaries

Tabs are **Scores / Lineup / My Team / Standings / Board**. My Team replaces only Transactions. Its native tab icon is a 26-point franchise thumbnail, with initials fallback and a visible label. Lineup remains the dedicated editor.

My Team is one scrolling page: team identity, contextual standing, six [Schedule-first shortcuts](my-team-shortcuts.md), then a position-grouped season-points roster. Direct tools are Schedule, Adds / Drops, Trades, Watchlist, Injured Reserve and League Activity. Adds / Drops reuses waiver search and adds owned-player drops; separate IR shows capacity and eligible moves. The trade badge appears on My Team and Trades. Other teams never display owner controls.

Both team headers share the [numeric standings summary](standings-pattern.md): record plus division place/name, or league place/name without divisions. No duplicate division line; no place before results or when unsupported/ambiguous. The summary links to that team's matching standings context. Maximum text sizes use a stacked header.

| Surface | Implemented player/team entry | Action preserved |
| --- | --- | --- |
| My Team / other team roster | Canonical player row → Player Detail | Read-only; no second lineup editor |
| Lineup starters/bench | Identity → Player Detail | Separate Start/Replace arrows and swipe actions |
| Matchup detail | Populated player cell → Player Detail; team identity → team roster | Scoring stays primary |
| Standings | Team row → team roster | Scope-aware rank, owner names and conservative unknown states |
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

## Player Detail — 0.5.4 (29–30)

Two independent AI design-review perspectives (native iOS/indie design and product/messaging/safety, not a human study) reviewed the code and actual native screenshots. The owner requested a calmer hierarchy and explicit separation of Drop from Bench. Apple's [button hierarchy](https://developer.apple.com/design/human-interface-guidelines/buttons), [menus](https://developer.apple.com/design/human-interface-guidelines/menus), and [disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls) informed the review.

1. **Primary card:** name, position/NFL team, supplied current injury designation, season points and weekly average, then franchise logo/name plus Starting/Bench/IR status. Own-team status is noninteractive; other teams can still open their roster. Missing status/ownership is not inferred to mean Healthy or Free agent.
2. **Week N:** one card combines fantasy points, projection, NFL opponent/kickoff and relevant injury detail. Existing snapshots and an exact matching history row supply scores; different-player/account/week data cannot fill it. Historical ownership is not claimed.
3. **Game log:** visible without another discovery tap, newest completed weeks first, with Week / Points / NFL opp columns. Initially four targeted scoring reads; Earlier weeks loads another bounded page. A real zero remains zero; absent scores show a dash and failed reads say Unavailable.
4. **Secondary information:** biography is a collapsed Player bio disclosure and is requested only when expanded; it cannot hold the primary card behind an optional feed. Watch remains a direct toolbar star.

### Historical opponents and data limits

At Josh's explicit request, NFL opponents use the player's **current NFL team's** season schedule, including past weeks. A small anchored information button explains that NFL trades can make historical opponents differ. This is an acknowledged approximation, not verified historical affiliation. Bye appears only when explicitly provided by the bye table without a conflicting game. Unknown/ambiguous schedule data remains blank.

The official [MFL API guidance](https://api.myfantasyleague.com/2026/api_info) states raw NFL statistics and third-party content are unavailable because of licensing. The log therefore contains fantasy points and NFL schedule context, with no empty raw-stat columns, scraped box scores or new external provider. It is not play-by-play. Current-week supplied scoring text can still appear when available.

### Roster action hierarchy

This supersedes the build-21 always-visible symbol-only Drop placement. A neutral toolbar **Player actions** menu contains labeled **Move to IR** or **Activate player** when eligible and **Drop player…** with destructive styling. Drop is no longer adjacent to Starting/Bench. The review and final confirmation explain removal from the roster, not a move to the bench. No identity/status/menu-opening tap submits anything; fresh preflight, durable pending markers, explicit confirmation and exact readback remain mandatory.

The direct symbol-only **person.badge.plus** Add control remains for free agents. Its enabled state uses the same strict owner-scoped decoded acquisition decision as preflight. Known locks/denials and malformed, contradictory or unconfirmed data cannot open immediate-add review. Generic flags say Locked for adds, Adding unavailable, or Add availability unconfirmed, not a guessed waiver/kickoff reason. IR remains eligible-only using a current Out/IR report; Questionable/unknown/stale/failed data cannot enable it.

### Navigation repair

Scores now uses a typed LiveMatchupRoute in the same path as PlayerRoute/TeamRoute. Mixing a destination-view matchup link with the bound typed path reproduced the reported duplicate-matchup/Back-to-player bug on iOS 27 and iOS 18.4. Regression coverage requires one tap to Player Detail and one Back to the original matchup.

The team-tool router is scoped to the NavigationStack rather than only its root view, so pushed own-team pages receive working shortcuts. The shortcut grid retains explicit buttons appending typed routes; embedding several NavigationLinks inside the same List row caused incorrect routing in development and was reverted. Sheet-owned browse stacks remain independent.

## Matchup detail

Owner names appear directly below team names in smaller, secondary text, reusing league metadata with no new request. Position headers retain the slot/FLEX badge but omit acronyms and positional subtotals: overall team totals and individual player points are the useful comparisons. Bench remains collapsed and does not affect team totals; VoiceOver player labels retain team context.

## Loading follow-up — build 30

Josh confirmed matchup → player → Back on build 29, then reported slow player cards and a lingering Updating game info spinner. The primary read waited for an optional biography; returning to the card also forced ownership refreshes. Biography now loads independently on disclosure, ordinary appearance reuses the detail cache, and explicit refresh/roster changes still check ownership.

Availability previously belonged to the first screen's cancellable task. Another screen could skip the in-flight read, then the original cancellation left no result while the 60-second attempt guard suppressed replacement. The league model now owns and shares that read, cancels it on scope reset, clears interrupted attempts, and exposes actual loading state. Idle/failure has a retry state, not a perpetual spinner. Existing source caches, rate-limit handling and fresh mutation preflight are preserved.

## First-frame identity — build 31

A player route carries only the identity already visible in its source row: canonical ID, name and supplied position/NFL team. Matching player and active league/owner scope are required. Scores, Lineup, team rosters, available players, watchlist, roster tools and player-only trade research supply it; no position/team is guessed from trade prose.

Player Detail renders that identity and any already-known matching-week metrics without waiting for ownership. Season scoring and game-log reads start independently. The primary card says Checking league status until that read completes; no Starting/Bench/Free agent claim or roster action comes from the identity preview. Watch remains disabled until detail is loaded. Failed reads retain the identity with actionable error state; the existing reconnect-only boundary is unchanged. This adds no API request, response store, permission or background task. A DEBUG-only offline Preview test deliberately delays ownership for 20 seconds and requires identity/Week content before completion, with actions unavailable.

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
