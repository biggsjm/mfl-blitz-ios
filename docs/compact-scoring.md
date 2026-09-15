# Compact scoring

Implemented for **0.6.3 (40)**, September 9, 2026. The owner approved tightening the screens, then approved the [scoring visual system](scoring-visual-system.md) to make points, forecasts and recent changes easier to distinguish. This document covers layout; the visual-system document defines scoring semantics. Exact verification and installation evidence belong in [current status](current-status.md).

## Scores

- Keep the navy **Your matchup** hero, smaller artwork beside team names, secondary owner names and prominent actual scores. The build-41 refinement uses equal-width, outward-mirrored halves: left team/score left-aligned, right team/score right-aligned, with shared identity and metric rows so wrapped names cannot offset score baselines. Label the smaller pregame projections and the actual leading/trailing margin separately.
- Use an inline league title and compact two-team cards around the league. Align actual scores and forecasts consistently, retain the entire matchup as a generous tap target and keep search/week/schedule reachable.
- Show game state independently of the last successful score check. A bounded recent-changes disclosure lives below the league list, so its arrival does not move scores the user is reading. Compact league rows center the actual/projection block beside the identity and use symmetric padding for temporary change badges; an invisible third metric line no longer pulls the visible score above the team. Accessibility layouts retain an in-flow badge line.

## Matchup detail

- Keep a smaller navy team summary with owner names secondary to team names and official scores prominent.
- Replace separate padded position cards with one comparison table: dedicated player-name lines, aligned actual points with smaller labeled projections, center slot/FLEX markers and secondary NFL context. Missing players remain a dash, not a fabricated zero. Bench stays collapsed and separate from starter totals.
- Keep NFL team/opponent on one caption line and day/time together on the next, e.g. `ATL @ DAL` / `Thu 12:00 PM`, formatted in the user's locale/time zone. There is no dot between NFL teams. Regular player rows share a minimum numeric-column width so differing point/projection lengths do not stagger game captions. When horizontal space is insufficient, stack the score and game context instead of breaking the day from the time.
- Preserve full names, at least 44-point player targets and one-Back return. Active/finished players open Week N / Player segments, defaulting to their points and supplied scoring stats; pregame players open the card directly. NFL opponent/time comes from the shared weekly schedule, with live/final state from MFL player clocks; optional availability does not gate score rendering.
- Collapsed Bench shows each team's name and bench-point subtotal below its disclosure, replacing the explanation about whether bench points count. Expand to inspect individual bench players. The subtotal sums only reported finite bench scores from the current snapshot, including real zero and negative points; incomplete/ambiguous data shows a dash. It does not change official team totals, represent an optimal lineup, or trigger another API request.
- At accessibility sizes, expand rather than shrink text: stack teams and player name/score, retain meaningful team/slot labels, and allow scrolling. Fitting the league or all starters on one screen is a density goal at normal phone text sizes, not a promise across devices or accessibility settings.

The accompanying core scoring receipt preserves response timestamps across caching/coalescing; it does not add requests or change the polling cadence. No transaction permissions or live league writes are part of this increment. Manual VoiceOver/iPad, Reduce Motion behavior on device, and owner game-week validation remain open.
