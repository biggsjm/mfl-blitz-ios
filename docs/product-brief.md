# Product brief

Reconciled September 7, 2026 against private build **0.5.3 (28)**. [Current status](current-status.md) distinguishes implemented behavior from product targets and remaining validation.

## Promise

**The MFL app you can trust under deadline.**

MFL is unusually powerful because a commissioner can shape nearly every rule. That flexibility also makes a generic fantasy-football UI brittle. MFL Blitz pairs a calm native interface with explicit freshness, validation derived from league settings, and proof that critical actions reached MFL.

## Jobs to be done

1. **Know what is happening now.** Open directly to the current matchup, then scan every league score without navigating a report tree.
2. **Set a legal lineup before lock.** See league-derived slots, eligible bench/starter replacements and available projections, including a signed [same-week opponent comparison](lineup-projections.md); review the full lineup and retain edits if submission fails. Official opponent/kickoff/injury enrichment is implemented; complete live-week and manual accessibility verification remain open.
3. **Build conditional bids confidently.** Search and sort free agents, see remaining budget, pair every add with its drop, reorder rounds, and replace the saved queue only after a clear review.
4. **Stay connected where the league already talks.** Read, compose, and reply on MFL's message board rather than forcing the league into a second chat network.
5. **Understand the race.** See division/overall places, owners, record and points without a horizontally scrolling report. Places follow supported configured tiebreakers; unknown places stay blank and MFL remains authoritative for custom orders. Team and league schedules use published opponents; undecided playoffs stay explicitly unset.
6. **Make and manage trades.** Find Create/Resume immediately, compare exact assets on both sides, cancel draft edits safely, and review the intended response before committing.

## Shipped navigation

Five stable, labeled tabs keep Scores and Lineup one tap away; team tools are one level inside My Team:

| Tab | First screen | Primary action |
|---|---|---|
| Scores | User matchup, then league scoreboard | Refresh / change week |
| Lineup | Submitted starters and bench | Review and submit |
| My Team | Identity/standing, six direct tools, roster by position and season points | Schedule, Adds / Drops, Trades, Watchlist, Injured Reserve, League Activity |
| Standings | Divisions using supported league-configured tiebreakers | Switch overall/divisions or open a team |
| Board | Existing MFL threads with unread state and visible Drafts | New thread / reply / resume draft; Close offers save/discard |

Settings is upper-left on My Team (moved from Scores in build 34), not a top-level tab. Scores and Lineup share a calendar control labeled Week N. Standings order information stays behind an anchored information popover. Trades put the native Create/Resume action first and move the routine MFL link into secondary options; errors retain visible recovery links. Trading Block follows Lineup's promotion/demotion, pinned review and explicit submit pattern without changing roster membership.

This follows Apple's guidance that tabs represent persistent peer destinations, use familiar symbols plus labels, and avoid behaving like action buttons: [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars).

### My Team navigation

The implemented navigation is **Scores / Lineup / My Team / Standings / Board**. My Team shows a shared [contextual standing](standings-pattern.md), the six [Schedule-first shortcuts](my-team-shortcuts.md), and a position-grouped roster sorted by actual season-to-date points, missing scores last. Transactions and Manage roster no longer compete as umbrella pages. Lineup remains the dedicated editor. Other-team details retain Roster / Schedule. Player identity links open shared detail: the known identity appears before ownership completes, followed by independently loaded season metrics, one Week card, a visible paged game log, and collapsed biography. The identity preview carries no roster-action authority. Historical NFL opponents use the current-team schedule with an information caveat. Own-team status is static; Drop is a clearly labeled secondary action, never a bench control. Acquisition and trade asset-selection actions remain separate from research.

Reuse existing My Team → Adds / Drops available-player search. There is no extra Players tab or new global search destination. Browsing a team/player/schedule must not change the active lineup week or drafts. My Team uses a 26-point original-rendered logo/initials inside the native tab bar. The system owns tab layout and selection; no raised custom tab bar is introduced. See the [schedule](schedule-ux.md) and [player-detail](player-detail-ux.md) plans.

## Design principles

The build-33 [league extras](league-extras-implementation.md) extend existing destinations: Trades → Offers / Trading Block, Schedule → Matchups / Calendar. Trading Block makes owner intent and Make offer easy to find while preserving existing drafts. Calendar is an agenda, not another full-screen grid; deadlines link to the relevant task and reminders require a contextual opt-in. The current-matchup Live Activity is a glanceable score surface with explicit staleness, not a promise of continuously updating background data. No new main tab is added.

- **Freshness is content.** Expose meaningful update/loading/error states. Foreground scoring is conservatively polled; background real-time delivery is not implemented.
- **Proof beats optimism.** Reviewed writes use server readback. Ambiguous outcomes trigger reconciliation, not blind resubmission. Do not claim tiebreaker readback or completed trade approval when MFL cannot prove it.
- **One obvious action.** Each screen keeps its critical action persistent and moves secondary detail behind disclosure.
- **The league's rules win.** Derive supported behavior from capabilities/configuration and fail safely when unknown. Broader formats, taxi management and commissioner tools remain targets; basic capability-gated add/drop and IR are implemented, not universally supported features today.
- **No color-only state.** Live, leading, locked, injured, unread, and invalid states always include text or symbols.
- **Native before novel.** System navigation, lists, sheets, menus, search, controls, typography, materials, haptics, and semantic colors come before custom chrome.
- **Fast cold open.** Show last-known content while reconnecting when a protected display cache exists; load fresh scores/lineup before optional initial feeds. Keep offline/update status compact and never authorize changes from cached data. A first successful download is still required; full offline browsing is not implemented. See [startup design](performance-startup.md).
- **Explain the action, not the plumbing.** Short labels and move arrows do the work. Keep local storage/API mechanics out of lineup picker copy; keep exact terms and consequential limitations at final review. Cancel must actually restore prior draft state.
- **Respect the league.** Use the existing MFL board. Do not harvest leagues, build a shadow social graph, or expose bids in notifications.

Apple references: [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Modality](https://developer.apple.com/design/human-interface-guidelines/modality), and [Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities).

## Indie-iOS inspiration

The closest product ideal is Flighty: time-sensitive information made calm, prominent, and trustworthy across the Apple ecosystem. Apple's [Behind the Design: Flighty](https://developer.apple.com/news/?id=970ncww4) emphasizes focused hierarchy, useful Live Activities, and treating small status details as the product.

MFL Blitz borrows that sensibility—not Flighty's visual identity. Personality comes from an original midnight-and-field-lime palette, rounded SF typography, restrained football language and team-driven accents. League-supplied franchise artwork appears as content through a safe image loader; the original app and Lineup icons contain no MFL/NFL/team marks. Avoid betting-dashboard density, casino effects and feed bloat. The linked design research is a dated reference, not a claim that every Apple ecosystem feature is implemented.

## Accessibility acceptance criteria

- Custom action hit targets should be at least 44 × 44 points; native toolbar/tab controls use system sizing and require usability validation. Do not claim every control's measured frame meets 44 points.
- Scores and records use monospaced digits without fixed font sizes for body content.
- VoiceOver scorecards announce both teams, scores, and status as one useful summary.
- Player rows announce position and available projection/status/lock information; never announce placeholder opponent/injury data as verified facts.
- Start/bench and queue-reorder actions have non-gesture alternatives.
- Dynamic Type layouts remain usable through accessibility sizes.
- Reduce Motion suppresses ornamental repeating effects.
- Differentiate Without Color remains fully understandable.
- iPad receives a readable maximum width and adaptive score grid.

These are acceptance criteria, not a completed certification. Selected native tests cover labels, action separation, tab targets and accessibility-size trade layouts. Full manual VoiceOver/Voice Control/Switch Control, contrast and supported-device testing remain in the [release gates](roadmap.md).

## Privacy posture

The app talks directly from the user's device to MFL without an analytics, advertising, credential or proprietary-message backend. The password is used only for HTTPS login and never persisted. Sessions, scoped drafts and unconfirmed-action markers survive relaunch in device-only Keychain storage; identity is freshly verified on restore. Protected, backup-excluded display/league metadata caches are separate from the daily public catalog. Other private responses and artwork are memory-only. Logs must omit credentials, cookies, private trade terms, bids and message bodies. See [privacy](../PRIVACY.md) for retention/deletion and external artwork requests.
