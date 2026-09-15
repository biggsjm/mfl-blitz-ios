# Interface craft refinements

September 9, 2026. Local implementation for private build **0.6.1 (37)**. [Current status](current-status.md) records actual verification and installation separately from implementation.

The review applied Anthony Hobday’s principles of continuity, truthful presentation, responsive feedback, readable hierarchy and configuration-driven behavior to six existing flows.

## Behavior

- **Board continuity:** loaded thread details live in a session-scoped cache independent of the first summary page. Refreshing the board or dropping a thread from that page cannot remove an open conversation. Thread reads no longer wait for a second summary request. Inline loading and Retry keep previous messages visible on failure; account reset clears details and errors.
- **Truthful scores:** the featured card belongs only to the signed-in franchise. Missing-owner responses show “No matchup listed for your team” while leaving the rest of the league available. “Your projected margin” is the owner’s projected points minus the opponent’s, signed and rounded to one decimal; unavailable projections stay unavailable. It is not a win probability.
- **Independent week reads:** Scores and Lineup publish and stop their loading indicators as each completes. Each result must match the selected week and current session/request generation. A failed section has its own retry guidance and does not withhold a successful section.
- **Readable scores:** primary scores use semantic Dynamic Type fonts. At accessibility sizes, freshness/status headers and team comparisons stack vertically; team names and summary metrics adapt to available width. The complete featured card has a spoken summary including the owner-oriented projected margin. September 9's [compact scoring refinement](compact-scoring.md) preserves these behaviors while tightening regular-size layouts.
- **League weeks:** authenticated league start/end settings govern the shared Scores and Lineup pickers and the model’s week-selection guard. Older cached workspaces decode with optional bounds. If settings are unavailable, use a loaded season-schedule range or only confirmed/previously observed weeks and any published start/end endpoint, with an explanatory caption. Empty schedule snapshots do not invent a Week 1 range. No assumed 18-week season or separate 21-week guard remains.

## Verification

`CraftFlowTests` covers summary refresh/page removal, load/retry/reentry states, account clearing, independent suspended Scores/Lineup responses, stale week rejection, margin orientation/missing values, missing owner matchup and configured/legacy week ranges. `TwoWeekSimulationTests` also covers following current week and returning to historical weeks.

The native `testCraftScoreMarginAtAccessibilityTextSize` journey explicitly enters offline Preview, checks truthful spoken presentation and captures the largest-text card and metrics. Existing week-control, score navigation and Board draft/reply journeys check surrounding navigation. Exact results belong in Current status. Automated tests never post to a real league; live week rollover, manual VoiceOver and broader device accessibility remain owner checks.
