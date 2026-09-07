# My Team — direct tools

Approved September 6, 2026 for **0.5.3 (22)**. [Current status](current-status.md) records verification and delivery; [roadmap](roadmap.md) keeps the remaining release and feature gates.

## Navigation contract

My Team remains one scrolling page: franchise identity, official standing, six shortcuts, then the roster grouped by position and sorted by actual season-to-date fantasy points. The shortcuts read left-to-right, top-to-bottom:

1. Schedule
2. Adds / Drops
3. Trades
4. Watchlist
5. Injured Reserve
6. League Activity

Use two columns at ordinary text sizes and one column at accessibility sizes. Each shortcut is an independent, labeled native control, with at least a 44-point touch target. Injured Reserve uses a neutral medical bag. Trade attention appears only on Trades and the My Team tab. Schedule is not placed between transaction actions.

There is no Transactions umbrella page or Manage roster destination. The five bottom tabs stay Scores / Lineup / My Team / Standings / Board. Other-team pages keep their Roster / Schedule picker and never expose the owner's tools.

## Adds / Drops

- **Available / My roster** switches between acquiring players and standalone drops. Each side retains its own search query while switching; search sits below the picker and switching dismisses the keyboard.
- Available reuses the existing cached free-agent pool, waiver filters, projections, saved bid queue and review. No second player directory or duplicate free-agent endpoint is added.
- The person-plus control opens **Add now / Place waiver bid** when both methods are supported. With only one method, it opens that method directly. Existing saved claims remain editable when bidding closes, but submission still checks the window and rules.
- My roster uses a red person-minus control. It opens the existing reviewed Drop flow; it never drops on first tap.
- Immediate-add and waiver availability are independent. A closed or unsupported blind-bid queue must not imply that every FCFS add is unavailable. The list uses scoped owner/rule capabilities; Player Detail and final fresh preflight enforce player-specific acquisition restrictions.
- Required paired drops, final confirmation, uncertain-outcome recovery and exact membership readback are unchanged.

## Injured Reserve

Show IR capacity and active-roster count, then current IR players with Activate, followed by eligible active-roster players with a neutral medical bag. A full IR slot disables further reserve moves. Activation can open review even when the active roster is full so the owner can select an explicit paired drop.

Only a current matching Out/IR report qualifies in the supported native scope. Missing, stale, failed, other-week or nonqualifying reports cannot enable a move. Review repeats the eligibility guard and the repository performs fresh preflight; MFL makes the final decision. Unsupported league formats keep the MFL fallback.

## Existing workflows and safety

Trades keeps its pinned Create / Resume action, exact offer reviews, isolated drafts and recovery controls. Watchlist retains synced stars and player research. League Activity retains readable moves/amounts, its trade filter and independent refresh. Schedule retains destination-local scoring and concise freshness.

Every tool route carries season/league/owner scope. A route from a different scope cannot show owner tools. Shared roster-tool state rejects late owner reads and mismatched payloads; failed refresh leaves known membership readable but disables mutations until a successful check. Browsing reuses caches and never changes selected scoring week, lineup edits or trade terms. No new persistent private data, background polling, backend, automatic imports or automatic write retries are introduced.

## Verification boundary

Native tests exercise all six destinations, two-column geometry, maximum Dynamic Type, retained search, player research, eligible-only IR, reviewed Drop/Add cancellation and synthetic IR readback. Model tests cover route order and scoped roster availability, failed refresh and late results. The existing two-week synthetic journeys remain part of the regression suite. Actual results are recorded only after each run finishes in [current status](current-status.md).

All automated writes occur only in explicit Preview. Passing tests are not a completed live game week, human usability study or permission to mutate a league roster. Owner checks and distribution gates remain open.
