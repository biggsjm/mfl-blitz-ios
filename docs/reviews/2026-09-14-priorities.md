# MFL Blitz — agreed design priorities

September 14, 2026 · reviewed against build 60 source and available app captures.

The three independent AI reviewers—football/fantasy football, sports app design, and Apple design quality—read one another’s findings, discussed tradeoffs directly, and **all accepted this order**. The Apple review applies published Design Award/HIG criteria; none of the reviewers claims real-world award credentials.

The app’s next step is making its existing information easier to trust and use during games. More features or another navigation tab are lower priorities.

## Immediate timeline cleanup

The current update removes the permanent explanation and storage-limit footer. Score changes remain prominent; tracking starts and gaps move into collapsed **Recording details**, with a single coverage note when needed. An info button explains the limits. A history with no score changes gets a clear empty state.

This is a presentation change. It does not reconstruct missing plays, change collection frequency, or implement the deeper timeline work below. Build and phone-delivery evidence belongs in [Current status](../current-status.md).

## Agreed order

| Order | Change | What the user should experience | Priority |
| --- | --- | --- | --- |
| 1 | Readable actions and complete accessible labels | Search, links and selected controls stay readable in light appearance. Live Activity descriptions include the remaining-player information visible on screen. | P1 · small baseline fix |
| 2 | The same weekly player detail everywhere | Open a player from Search, My Team, Lineup or a matchup and get the same available NFL game context, box score and league points explanation. Actual production outranks pregame projections. | P1 |
| 3 | Lineup readiness and alert coverage | See empty slots, known unavailable starters, unsaved changes and whether this week’s alerts are connected where the lineup is managed. | P1 |
| 4 | Matchup context that stays visible | Keep compact team totals available while scrolling; show each side’s playing/yet-to-play counts and next kickoff when known. | P1 |
| 5 | A useful matchup history | Group one observed update into its team change and contributing players; distinguish real coverage gaps from verified quiet periods. | P2 |
| 6 | A clearer Live Activity | Preserve scores, identity and useful remaining-player context; remove redundant detail and distinguish cumulative game totals from the latest point change. | P2 |
| 7 | Focused search and My Team polish | Clarify that global search finds players, tune results density, and test whether tools delay access to the roster before reorganizing them. | P3 · validate first |

## Scope and acceptance

1. **Accessibility baseline.** Keep bright lime as a brand fill and against navy; introduce an appropriate action tint for light backgrounds. The current source color has nominal **1.82:1 contrast against white**, not a measurement of every rendered control. Verify text controls against their actual light/dark backgrounds and Increase Contrast, following [Apple’s contrast criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria/). Fix the source-confirmed omission of playing/remaining counts from the expanded Dynamic Island’s combined accessible label; verify it with VoiceOver.

2. **Player detail and points.** Centralize weekly context resolution, preserving an explicitly selected historical week and the originating navigation path. Reuse shared data; do not add per-player paid polling. Prioritize league-scoring contributors in the compact stat line and keep the existing full breakdown accessible. Show missing/unsupported contributions honestly; never replace MFL’s total with a local calculation. Final rows should emphasize actual points/stats, with pregame comparison available in research. Test the same player from all four entry points, supported/partial scoring, free agents, old weeks and Back navigation.

3. **Readiness.** Keep three distinct facts: a legal/saved lineup, current player availability, and acknowledged alert coverage. A compact “Starters need attention” row should lead to existing eligible replacements; known Out/IR/bye information must not be confused with Questionable or missing data. “Alerts ready · Week N” requires the correct server acknowledgment, not just enabled preferences. Test permission denial, token pending, offline connection, rollover, expired coverage and pending opt-out. Actual phone delivery must be verified before claiming it reliable. No automatic lineup edits or new consent prompts on mere page entry.

4. **Matchup context.** Use the existing validated remaining-player model; exclude the bench and omit unknown counts instead of treating them as zero. Collapse the hero into a compact persistent score strip as it scrolls away. Preserve position comparison and scroll stability. The owner's subsequent **Matchup mode** idea extends this package: offer Completed / In progress / Yet to play sections, with live starters expanded and other sections summarized per team. Use Completed rather than Locked because scores remain subject to corrections. The [detailed proposal](../matchup-mode-plan.md) specifies grouping, totals, exceptions, interaction and acceptance checks. This follow-up is a proposed extension, not an additional vote by the reviewers. Verify long team names, large text, pregame/live/between-games/final and stale states.

5. **Timeline semantics.** Preserve raw observations but group related team/player deltas in presentation so they do not look like separate scores to add together. Keep gap ranges discoverable and suppress off-hours noise only where game-state evidence supports it. Do not merge gaps across actual changes. A negative delta is **not automatically a correction**: an interception or lost fumble can reduce points. Use a literal signed change unless the source establishes more. Test simultaneous changes, reopen overlap, no changes, overnight pauses, actual live interruptions and negative scoring. Never infer a touchdown or exact play sequence from fantasy points alone.

6. **Live Activity hierarchy.** Prefer legible per-team remaining counts over a redundant aggregate count. Label cumulative stat context as game totals, or show a stat delta only when compatible observations support one. Preserve centered scores, team artwork, honest estimates and stale state. Verify compact widths, long names, large/negative scores, delayed data, VoiceOver and Always On. Follow [Apple’s Live Activities guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities).

7. **Validate before reshaping.** Keep inline search and query preservation. Make player scope explicit, test focus return and covered-background traversal, and size small result sets without clipping ownership or large text. Compare the current My Team tools grid with a more compact arrangement through roster lookup, Adds / Drops and pending-trade tasks. Search focus and My Team scrolling burden are hypotheses requiring runtime evaluation, not confirmed failures.

## Discussion decisions

- The first-pass rankings differed: football favored lineup readiness, sports design favored player-entry consistency, and Apple design favored contrast/accessibility. All three accepted a small accessibility baseline first, followed by the two largest product improvements.
- League points explanation and phase-aware stat hierarchy belong with consistent player detail, rather than becoming separate destinations.
- The timeline’s copy cleanup ships independently of event grouping and game-aware gap handling. Grouped observed history must not pretend to be play-by-play.
- Keep the native five tabs, stable comparisons, saved drafts, deliberate review/submit, confirmed MFL writes, opt-in alerts, explicit missing data and shared bounded refresh. No new paid-source poller is needed for these proposals.
- Defer win probabilities, automatic lineup optimization, a new social feed, broad navigation redesign and unverified playoff claims.

## Evidence and limits

The independent passes inspected current source across all five tabs and shared player/scoring/alert/Live Activity flows, the supplied timeline photo, final build-60 search captures, and earlier scoring/alert/Live Activity captures checked against current source. They did not each perform a complete new device walkthrough. No award certification, full manual accessibility audit, all-league validation or notification-delivery verification is claimed. The parent’s focused timeline simulator and phone checks are recorded separately.

Independent findings and discussion records: [Football/fantasy](2026-09-14-football.md), [Sports app design](2026-09-14-sports-design.md), [Apple design quality](2026-09-14-apple-design.md).

The owner subsequently approved all seven packages and Matchup mode. They are implemented for build 62; see [Current status](../current-status.md) for test results, phone delivery and remaining manual checks. The independent review evidence above remains the original assessment rather than a retroactive review of build 62.
