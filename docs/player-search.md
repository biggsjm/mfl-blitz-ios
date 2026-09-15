# Global player search

Approved September 9, 2026; team-name and league-position correction in **0.6.3 (40)**; inline search in **0.6.3 (60)**. Installation and verification evidence are recorded in [current status](current-status.md), separately from this behavior contract.

Build 62 makes **Search players** explicit, sizes the results panel to its content within the keyboard/viewport bounds, and hides the covered page from accessibility traversal and touch while search is open. Player details use the common weekly scoring resolver, retaining query and route on Back. All six existing search UI journeys pass, including largest text and delayed/failed ownership. Manual VoiceOver traversal remains a device check.

Build 63 makes ownership prominent in results and in the scored player’s Week tab. Both player tabs start the existing cached MFL detail read; search membership supplies an immediate scoped fallback. Team and human owner remain visible after navigation, with unknown/free-agent/last-known distinctions preserved. The empty panel now uses direct content measurement and concise search guidance.

## Interaction

- A magnifying glass at the far right of Scores, Lineup, My Team, Standings and Board expands an inline field beneath the toolbar, following FeedCast's view-scoped search interaction. Matchup detail has the same entry point. Existing Week, compose, information and Settings controls remain available.
- The field focuses the keyboard when opened, with a bounded, scrollable results panel below it. The underlying page remains mounted and visible; no search sheet or separate search navigation stack is created. Close clears the query and collapses the field. It does not change the originating tab, route, scoring week or any lineup/trade draft. Reduce Motion suppresses the opening/closing animation.
- Search includes rostered and unrostered players in the league's configured positions. Full NFL names, cities, common/MFL abbreviations, player names and positions can be combined (e.g. **Patriots**, **New England**, **NE**, **NEP**, **Patriots WR**). Matching ignores case, diacritics and apostrophes. Recognized codes/positions match their fields, not substrings inside names or team-unit position codes. Results are bounded at 60 with a refine-search hint and the full match count.
- Champion Hall's explicit QB/RB/WR/TE rules exclude MFL's team-unit records (TMWR, TMRB, etc.), defense, kickers and other unused positions. Team units remain searchable in leagues explicitly using them. Zero-minimum positions with a positive maximum remain eligible; DL/DB families and K/DEF aliases are supported. Unknown/compound/missing rules preserve the broader catalog rather than guessing restrictions. Unknown player positions are not discarded. This is search presentation, not transaction eligibility.
- Individual players precede team units; within each tier exact names rank first, then name prefixes and other matches. Team aliases add search vocabulary only: the displayed NFL affiliation still comes from the cached MFL catalog.
- Rows show player name, position/NFL team and fantasy team/owner/status. Tapping opens the existing canonical player card in the originating tab's navigation stack, with its identity immediately supplied. Back preserves the query/results without reopening the keyboard. No destructive or transaction action is added to a result row.
- Recent players are shared between entry points, de-duplicated and capped at eight. They are session-memory-only, with Clear, and reset on account/league changes or sign-out. Query text is never sent to MFL or analytics.

## Data, performance and safety

- Catalog and ownership have independent loading tasks. Names remain usable during a slow or failed ownership request.
- The index reuses the decoded, disk-backed 24-hour player catalog and authenticated league rules; filtering runs off the main actor and rejects obsolete query/session results. NFL aliases are local vocabulary. Typing never performs a network request. The index is reused across entry points/tabs for the session and renewed after a day.
- Ownership is a single complete current-roster export, with cached league/owner metadata. It never uses a historical roster week or the user's unsaved lineup. Duplicate or incomplete roster feeds fail explicitly instead of implying free agency. Multi-owner leagues keep every owner.
- Current-week Starting/Bench can supplement confirmed current ownership only from recent, matching-player/team scoring data. Otherwise the row says Rostered. IR/taxi membership takes precedence.
- Free agent requires an explicit free-agent pool entry in a confirmed single-roster, league-wide pool. Merely absent from rosters means **Not on a roster**; complex league-unit pools do not imply availability. Neither label grants permission to add. Existing player-action preflights and reviews remain mandatory.
- Automatic opening reuses short-lived MFL caches; manual refresh and confirmed roster-revision changes refresh membership. Failed ownership refreshes retain prior display with **Last known** and an inline stale/Retry message. Unknown ownership never becomes Free agent.
- Optional search adds no startup fetch, polling loop, or new API import endpoint. Opening a result uses the existing cached player-detail ownership read from either Week or Player, rather than only Player. Data and late responses are scoped to the authenticated season/league/franchise.

## Verification and remaining checks

Synthetic tests cover all 32 NFL team names/code aliases, league position scope and unknown-rule fallback, optional FLEX positions, team-unit exclusion/explicit inclusion, a 20,000-player catalog, bounded results, complete/duplicate/multi-owner rosters, explicit free agency, assignment freshness, cache/request counts, session replacement, recents and failure recovery. Native journeys reproduce the Patriots team-unit regression and cover all five entry points, matchup return, player Back, held ownership, offline ownership and largest text. Exact outcomes and inspected screenshots belong in Current status.

Owner check: during Week 1, search a player seen on TV, verify their owner/status, open the player and close back to the same matchup. Manual VoiceOver and iPad-specific search layouts remain release checks. TestFlight remains on hold; no league mutation is needed to validate search.

Design reference: [Apple search fields guidance](https://developer.apple.com/design/human-interface-guidelines/search-fields).
