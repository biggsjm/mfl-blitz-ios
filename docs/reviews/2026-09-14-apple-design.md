# Independent review: Apple design quality

Reviewed September 14, 2026, against build 60 source and the available captures. This is an AI review applying Apple’s published design criteria; it is not a review by an Apple employee, award judge, or award recipient. Findings below were formed before reading the other two reviews.

## Standard and coverage

Apple’s current awards emphasize intuitive platform interactions, inclusion, and a cohesive visual theme. These are review lenses, not a certification checklist. [Apple Design Awards](https://developer.apple.com/design/awards/)

Read the five tab roots, team roster/tools, player scoring and points breakdown, inline search/navigation, lineup-alert UI/controller, shared Live Activity and its Dynamic Island extension, and the timeline. Visually inspected the user’s timeline photo; build 60 Scores/Board search captures; build 56–57 matchup, player, alert, timeline, and large-text captures; and build 57 shared Live Activity renders. Older captures were cross-checked against current source. My Team, Lineup, and Standings have source coverage but no new full-screen capture in this pass.

No fresh simulator run, physical-phone inspection, actual notification delivery, VoiceOver session, Switch Control test, Always On test, or iPad/Watch/CarPlay runtime review was performed. Code-supported issues are distinguished from hypotheses below. The root agent is concurrently simplifying the timeline; that work is not counted as already verified here.

## Prioritized findings

### AD-1 — P1: Make action colors readable in light appearance

**Observed:** `BlitzTheme.swift:5` defines `blitzGreen` as RGB 0.50/0.84/0.05 and `MFLBlitzApp.swift:37` applies it as the global tint. It appears as search/close controls, “Season schedule,” and “Points breakdown” text in the inspected captures. Its nominal contrast against white is **1.82:1**, calculated from the source sRGB values; this is not a measurement of every rendered material. The green is effective as a fill behind dark type, but too light for text on white.

**Consequence:** Important actions become harder to identify outdoors or with low vision. This affects ordinary tasks across the app.

**Proposal:** Separate brand-fill green from a darker semantic action color in light appearance. Preserve the bright green on navy and in position badges. Measure the complete team-color gradient separately; do not darken everything indiscriminately.

**Accept:** Text controls meet 4.5:1 against their rendered backgrounds in light and dark appearance, including Increase Contrast. Check search, links, selected tabs, disclosure labels, and alert state. Apple’s sufficient-contrast criteria call for common-task controls to meet general contrast guidance by default. [Apple contrast criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria/)

### AD-2 — P1: Put the matchup story ahead of recording details

**Observed:** The supplied photo contains four repeated “Updates were unavailable between saved checks” rows, a recording-start row, and explanatory paragraphs above and below. `MatchupTimelineView.swift:14–46` renders that hierarchy. It offers little information about what happened in the matchup. Similar permanent explanation appears in lineup-alert footers (`LineupAlerts.swift:233,240`) and the board footer (`BoardView.swift:84–85`).

**Consequence:** A user must read service mechanics to discover whether there is useful football information. Repeated gaps look like repeated failures rather than one limitation of the available history.

**Proposal:** Lead with named player/team changes, point deltas, and short times grouped by day. Use one compact “History incomplete” disclosure for coverage details. When no score changes are available, say “No score changes recorded yet”; keep the saved starting score and coverage information available without treating them as plays. Collapse gaps only across genuinely adjacent missing coverage, never across actual changes. Move storage limits and provider mechanics to help.

**Accept:** The user’s five-row example becomes a short, honest empty/history state; a busy game shows scoring changes first; negative corrections and multiple changes in one pull remain understandable. Do not invent play descriptions or imply continuous play-by-play. Apple’s writing guidance favors the screen’s purpose, concise copy, and important information first. [Apple writing guidance](https://developer.apple.com/design/human-interface-guidelines/writing)

### AD-3 — P1: Show whether lineup alerts are ready where the lineup is managed

**Observed:** Alert settings provide useful state messages, including connected week, denied permission, server trouble, and incomplete removal (`LineupAlerts.swift:129–147,190–197,224–250`). They sit under My Team → Settings. `LineupView.swift` does not present those states or link to alert controls. The footer tells users to open the current lineup each week to renew alerts; readiness is therefore a recurring task, not just initial setup.

**Consequence:** A selected toggle can be mistaken for a working reminder. A user returning on Sunday cannot easily verify that the correct week is covered. This is particularly important after the reported crash; the crash itself has a fix and is not asserted to remain open.

**Proposal:** Add a compact, tappable Lineup status such as “Alerts ready · Week 2” or “Alerts need attention.” In settings show a short state plus its actual next action: Open iPhone Settings, open current lineup, or retry connection. Display “Turning off…” until revocation is confirmed; retain the existing honest pending-removal behavior. Keep all alerts opt-in.

**Accept:** Permission denied, token pending, offline server, week rollover, successful registration, and pending removal each yield a distinct state and relevant action. “Ready” requires server acknowledgment for that week; do not claim guaranteed delivery. No added paid stat requests.

### AD-4 — P1 for semantic parity; P2 for visual trimming: Simplify Live Activity detail without losing useful context

**Observed:** The Lock Screen rendering includes scores, names, estimates, per-team remaining counts, combined playing count, latest change, stat context, and checked time. `Shared/MatchupActivityScoreboard.swift:40–47` uses 8-point type for remaining players, with further shrinking permitted. Expanded Dynamic Island renders the remaining count (`MatchupLiveActivity.swift:66–68`) but replaces its children with an accessibility label that omits it (`:71–72`). Lock Screen’s corresponding label correctly includes that information.

**Consequence:** A useful late-game comparison is easy to miss visually and is absent from the expanded Island’s supplied accessible description. This is a source-confirmed omission, not a runtime VoiceOver test result.

**Proposal:** Preserve centered scores, team identity, estimates, and latest meaningful change. Remove the redundant aggregate playing count when per-team counts are shown. Use room gained to make remaining counts legible. Give each presentation equivalent accessible meaning; keep stale status attached to the numbers. Retain the user-requested compact “MFL Blitz · Week 1” identity.

**Accept:** Both teams’ score, estimate, playing/yet-to-play status, and delayed state are available to VoiceOver in the expanded and Lock Screen layouts. Visually verify 343-point width, long names, large/negative scores, no change, delayed data, and Always On. Apple recommends concise, glanceable information, sparing small type, and related deep links. [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)

### AD-5 — P2: Keep inline search, clarify its scope, and check focus boundaries

**Observed:** The final build 60 captures show the requested inline field with ownership directly in results and the original page behind it. The Board title remains “Board” while results are players. `PlayerSearchView.swift:85–86` uses “Name, NFL team, or position”; the scope is implied rather than explicit. Its custom overlay leaves the underlying page mounted, with no explicit accessibility boundary on that background.

**Consequence:** People can initially interpret Board search as message search. Whether VoiceOver wanders into covered content is an unverified risk requiring runtime testing, not an established failure.

**Proposal:** Use “Search players” as an explicit field label/placeholder; present detailed query guidance only before typing if useful. Keep the existing in-place results and Back preservation. Verify and, if necessary, constrain focus to the visible search region while retaining a clear Close action. Do not add a new page or tab simply to mimic another app.

**Accept:** Searching from all five tabs is unambiguously a player lookup; opening a result and Back preserves query/page; closing returns focus sensibly; background items obscured by results are not confusingly traversed. The largest text size remains usable with keyboard present. Apple calls for clear search scope and consistent locations. [Searching HIG](https://developer.apple.com/design/human-interface-guidelines/searching)

### AD-6 — P2: Let My Team prioritize the roster and actions that currently matter

**Observed in source:** `TeamDetailView.swift:120–158,167–175` places all six tool destinations in an equally weighted grid above the roster. It expands to six full-width rows at accessibility sizes. Transactions already expose attention counts; Lineup already distinguishes drafts, validation, and saved state. No runtime task timing was performed.

**Consequence — hypothesis:** My Team may feel like a tools menu before it feels like the user’s roster, especially at large text sizes. This should be tested rather than treated as a confirmed usability failure.

**Proposal:** Compare the current view with a compact actions row/menu plus a prominent contextual item only when action is needed, such as a trade awaiting response. Keep the roster, record, schedule, and transactional safeguards easy to reach. Preserve the five stable tabs until task-based evidence supports changing them.

**Accept:** In a small usability pass, people can find a rostered player, inspect a trade needing attention, and find Adds / Drops with fewer unnecessary scrolls, including at accessibility text sizes. Avoid hiding familiar actions without testing discoverability.

## Strengths to preserve

- Stable native tabs and typed navigation; Live Activity now routes to the actual Scores matchup.
- Team identity and symmetrical score layout; meaning is generally expressed in text as well as color.
- League-specific points arithmetic, explicit unexplained difference, and missing-data distinctions rather than manufactured precision.
- Inline search shows ownership without another tap; cached catalog and ownership load separately.
- Dynamic Type adaptations in standings, team headers, search, and points breakdown; Reduce Motion handling in score changes and search.
- Lineup draft/review/submit separation, non-retrying uncertain writes, opt-in alerts, and explicit connection states.

The greatest opportunity is reducing the effort needed to understand trustworthy information, rather than adding visual effects or more destinations.

## Discussion and consensus

After completing the independent pass, I read the football and sports-design reports and discussed priorities directly with both reviewers. All three explicitly accepted this order:

1. Accessible action colors and the confirmed expanded-Island description omission.
2. Consistent weekly player detail from every entry, league-aware scoring completeness, and phase-aware stat hierarchy.
3. Lineup readiness and acknowledged alert coverage for the current week.
4. Persistent matchup totals and per-team players remaining.
5. Grouped timeline observations and game-aware coverage gaps.
6. A leaner Live Activity that distinguishes latest score changes from cumulative game totals.
7. Validation-led search polish and, only if task checks support it, My Team hierarchy refinement.

The first package is a small accessibility baseline, not a claim that color is the largest product opportunity. The sports reviewer’s source-confirmed route-dependent weekly stats and the football reviewer’s distinction between legal and ready lineups justify the next two investments. My Team hierarchy and search focus remain validation hypotheses, not established runtime failures.

The root’s immediate timeline cleanup is separate from the later observation-grouping work. Preserve actual coverage gaps, use a literal negative delta or “Score decreased” unless a correction is established, and never invent a play narrative. We agreed to retain MFL’s scoring authority, shared request-budgeted refreshes, opt-in alerts, draft/submission safeguards, the five tabs, and inline search. No new poller, tab, or broad information-architecture redesign is recommended from this review alone.
