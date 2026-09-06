# Product brief

## Promise

**The MFL app you can trust under deadline.**

MFL is unusually powerful because a commissioner can shape nearly every rule. That flexibility also makes a generic fantasy-football UI brittle. MFL Blitz pairs a calm native interface with explicit freshness, validation derived from league settings, and proof that critical actions reached MFL.

## Jobs to be done

1. **Know what is happening now.** Open directly to the current matchup, then scan every league score without navigating a report tree.
2. **Set a legal lineup before lock.** See slots, eligibility, kickoff, injuries, and projections together; make changes accessibly; review the full lineup; retain edits if submission fails.
3. **Build conditional bids confidently.** Search and sort free agents, see remaining budget, pair every add with its drop, reorder rounds, and replace the saved queue only after a clear review.
4. **Stay connected where the league already talks.** Read, compose, and reply on MFL's message board rather than forcing the league into a second chat network.
5. **Understand the race.** See official standings order, divisions, record, points, and playoff context without a horizontally scrolling report.

## Navigation

Five stable, labeled tabs make every priority one tap away:

| Tab | First screen | Primary action |
|---|---|---|
| Scores | User matchup, then league scoreboard | Refresh / change week |
| Lineup | Submitted starters and bench | Review and submit |
| Waivers | FAAB status and pending conditional queue | Build / review requests |
| Standings | Divisions using official MFL sort | Switch overall/divisions |
| Board | Existing MFL threads with unread state | New thread / reply |

Settings is a toolbar destination, not a top-level tab.

This follows Apple's guidance that tabs represent persistent peer destinations, use familiar symbols plus labels, and avoid behaving like action buttons: [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars).

## Design principles

- **Freshness is content.** Every read shows a human-readable update state. Live scoring should poll no faster than the underlying data changes.
- **Proof beats optimism.** A successful write ends with an MFL-confirmed receipt. An ambiguous response triggers a refetch before the user is offered another submission.
- **One obvious action.** Each screen keeps its critical action persistent and moves secondary detail behind disclosure.
- **The league's rules win.** Slot limits, ties, doubleheaders, best ball, IR/taxi, salary/contracts, duplicate players, and commissioner abilities come from capabilities and configuration—not assumptions.
- **No color-only state.** Live, leading, locked, injured, unread, and invalid states always include text or symbols.
- **Native before novel.** System navigation, lists, sheets, menus, search, controls, typography, materials, haptics, and semantic colors come before custom chrome.
- **Fast cold open.** Cached data paints immediately with a stale label while a conservative refresh begins.
- **Respect the league.** Use the existing MFL board. Do not harvest leagues, build a shadow social graph, or expose bids in notifications.

Apple references: [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Modality](https://developer.apple.com/design/human-interface-guidelines/modality), and [Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities).

## Indie-iOS inspiration

The closest product ideal is Flighty: time-sensitive information made calm, prominent, and trustworthy across the Apple ecosystem. Apple's [Behind the Design: Flighty](https://developer.apple.com/news/?id=970ncww4) emphasizes focused hierarchy, useful Live Activities, and treating small status details as the product.

MFL Blitz borrows that sensibility—not Flighty's visual identity. Personality comes from an original midnight-and-field-lime palette, rounded SF typography, restrained football language, and team-driven accents. Betting-dashboard density, casino effects, feed bloat, and NFL/team branding are intentionally absent.

## Accessibility acceptance criteria

- All controls are at least 44 × 44 points.
- Scores and records use monospaced digits without fixed font sizes for body content.
- VoiceOver scorecards announce both teams, scores, and status as one useful summary.
- Player rows announce position, opponent, projection, injury, and lock state.
- Start/bench and queue-reorder actions have non-gesture alternatives.
- Dynamic Type layouts remain usable through accessibility sizes.
- Reduce Motion suppresses ornamental repeating effects.
- Differentiate Without Color remains fully understandable.
- iPad receives a readable maximum width and adaptive score grid.

## Privacy posture

The app talks directly from the user's device to MFL. It does not operate an analytics, advertising, credential, or proprietary-message backend. The password is used only for the HTTPS login request and is never persisted. Version 0.1 keeps the returned session value in memory only and discards it on disconnect or app termination. Logs must redact credentials, cookies, bid values, and message bodies.
