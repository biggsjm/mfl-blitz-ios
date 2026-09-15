# Live players

September 14, 2026. Build 63 simplifies build 62’s Matchup mode following the owner’s phone review. [Current status](current-status.md) records delivery evidence.

## Interaction

**Lineups | Live players** is a persistent choice on the matchup page. Lineups contains the complete position comparison, including finished/upcoming starters and a separate bench disclosure. Live players contains only starters whose NFL games are in progress, already expanded. It has no completed/remaining summaries, bench section or second disclosure to operate.

Live players always pins official team totals above the segment control. Lineups shows the full matchup card and pins totals after that card scrolls away. Use the league’s abbreviation verbatim, including numeric values such as **0005**. Team sides remain consistent. A toolbar clock opens the persistent matchup timeline.

Each team keeps its own ordered live-player column; these are not positional pairings. Build 64 gives all player areas a shared height based on the tallest intrinsic content, including status labels. Separate team headings align both columns even when a team name wraps. Lineups uses the same uniform player sizing. At accessibility text sizes the teams stack with explicit team headings. A team with no active-game starters says so. If neither team has one, show a concise empty state, the next known kickoff when available, and **Show lineups**. Unavailable game states remain qualified and direct people to the full lineup.

Player rows follow the owner’s compact comparison reference: points nearest the center gutter, mirrored name/NFL team and game/stat context. Names abbreviate when necessary, with the full name retained for accessibility and details. Stat labels shorten (for example PYD/RYD/REC/TD) without dropping any summary values or events. NFL context keeps the player’s team score first on either side. All rows share the same tappable height, and larger text stacks the content without clipping. Pregame projections appear only before kickoff. Tapping a player opens the common Week detail with ownership, full stats and the league points breakdown. Repeated arithmetic paragraphs and Points detail links are removed from the matchup rows.

## State and refresh

Use the existing game classification: verified NFL state takes precedence over conflicting MFL player clocks, halftime/overtime remain in progress, and unsupported/unknown/tied regulation completion is not guessed as final. In progress describes the game, not the player being on the field; known Out/Inactive status stays visible. Retain stale data with its freshness qualification.

The selected mode persists across launches; each mode retains its scroll context while navigating. A score change does not reset selection or the open player route. Newer Live Activity receipts supply official team totals and explicitly qualify older player rows. Do not derive a final-player subtotal by subtraction.

This is a local filter of shared MFL and NFL snapshots. Switching modes does not change teams requested, provider endpoints, timers, budget ceilings, final corrections or archive caching. Ownership uses the existing cached MFL player-detail read from either player tab, with search ownership available immediately while that read completes. No new paid NFL polling is introduced.

## Verification

Check normal/largest text in dark mode, active starters visible immediately, completed starters absent, full Lineups accessible, persistent totals and Back navigation. Verify ownership from search, matchup, lineup and roster, plus receiving-TD visibility and timeline access. Existing game-state classification tests cover halftime/overtime, conflicting clocks, missing data and bench exclusion. See Current status for executed checks and physical delivery limits.
