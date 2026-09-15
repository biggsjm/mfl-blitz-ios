# Game-day enhancements — build 57 installed and launched

## Build 64 refinements

Lineups and Live players use compact mirrored cells following the owner’s reference, with actual points nearest the center and concise name, game and stat context. Every player has the same area height, accommodating the longest current content and text size. Stat labels shorten without dropping any value or scoring event. Live team headings align independently of wrapped names. The entire player area opens details, including reserved space beneath a short stat line. Compact team totals fit without clipping at accessibility text sizes.

## Build 63 refinements

The owner's phone review simplifies Matchup mode to **Live players**: only active-game starters, already expanded, with official totals always pinned. Completed/upcoming/bench players stay in Lineups. Scoring rows retain stats (including touchdowns) while the calculation lives in player details; pregame projections appear only before kickoff. The toolbar clock opens history. Search and both player tabs show ownership. League abbreviations are preserved exactly, including numeric values. Existing paid NFL polling and cache policies are unchanged. See [Live players](matchup-mode-plan.md) and [delivery status](current-status.md).

## Build 62 refinements

The approved design review adds Matchup mode with Completed / In progress / Yet to play starter sections, exception states, per-team actual subtotals, and pinned official scores. All player entry points resolve the same available Week detail. Compact rows expose supported league point contributions; final rows omit pregame predictions. Readiness summarizes missing slots, known availability and unsaved changes, separately from server-acknowledged weekly alert coverage. Search explicitly finds players, sizes its results to content, and preserves the original screen. My Team initially offers Schedule and Adds / Drops, with the other four tools expandable and pending trades prominent.

Live Activity labels include per-team remaining counts; redundant aggregate counts are omitted when those counts are known. Cumulative stat context is labeled **Game totals**. Timeline updates group a team delta with contributing players, keep signed negative changes literal, and suppress gap rows only for compatible confirmed-final or verified pre-kickoff quiet intervals. The background service is deployed with these timeline rules; upstream polling and paid-provider budgets remain unchanged. League rules are coalesced per scope and cached for an hour in the app, above the existing repository cache. See [Current status](current-status.md) for validation and delivery.

## Original build 57 scope

Josh authorized the Live Activity improvements, league-specific points breakdown, opt-in lineup alerts, persistent matchup timeline, and D/ST enrichment on September 14. Install on the existing development phone when verified. No external release is requested.

- [x] Live Activity: counts per team, next relevant kickoff, verified stat context, and an explicit continuation flow before the eight-hour lifetime.
- [x] Read and cache MFL league scoring rules; explain supported calculations and expose unavailable rules/differences without fabricating stats.
- [x] Opt-in lineup notifications using saved starters and verified injury/kickoff information; preserve draft isolation, cancel obsolete reminders, and route to Lineup.
- [x] Persistent scoped matchup timeline, including observations received by the existing private background worker while the phone is away; bounded retention and clear gaps.
- [x] D/ST source adapter and presentation with fixtures for leagues using team defense. Never substitute total NFL points allowed for an MFL-specific defensive scoring definition.
- [x] Regression tests, normal/large-text UI checks, server deployment, signed phone installation and delivery evidence.

Budget: reuse shared MFL reads and the NFL cache. Every new paid NFL request must pass the existing persistent reservation/backoff/6,000-per-UTC-day ceiling. Never create a provider poller per user or per player. Final-correction and archive rules from build 56 remain.

Primary contracts inspected: MFL `api_info?STATE=details`, public league `rules`, and `allRules`; Apple ActivityKit lifetime and scheduling documentation. The actual league uses completions, discrete yardage thresholds, and position-specific rules; generic PPR assumptions are unsuitable.

## Implementation and practical limits

The Live Activity keeps its team colors/logos and live estimates, adds independently verified playing/yet-to-play counts, shows the next relevant NFL kickoff while waiting, and adds a current verified player stat line when one starter explains the latest MFL point change. It does not claim that a stat line is the last play. Near the existing 7h50m subscription expiry, the card invites the user to open Blitz; the matchup and Settings offer Continue Live Activity. Continuation is explicit, including between games, and does not silently undo a user dismissal. Apple's eight-hour active lifetime still applies.

Tapping a player's points or expanding Points breakdown explains available contributions using cached MFL `rules` plus the `allRules` descriptions. Calculations support position scopes, multipliers, whole-group yardage awards, bounded fixed awards, completions/attempts, offensive touchdowns/conversions/turnovers, available return and kicking counts, and explicitly supplied D/ST totals. Missing source fields, distance events not available individually, and unverified threshold-base formulas stay unavailable. Shown stats total, official MFL points, and any unexplained difference remain separate; MFL is the score authority.

Lineup alerts have three independent options, all off by default: pre-kickoff reminder, unavailable starter, and incomplete lineup. Enabling requests iOS notification permission and registers the normal app APNs token with the existing private service, independently of Live Activity tokens. The worker checks current saved MFL starters in the 30-minute window before a roster kickoff. Incomplete means fewer saved starters than the league's required count. Only explicit, matching-week, recent Out/IR/Inactive reports generate unavailable warnings; Questionable/Doubtful and unreported healthy scratches are not treated as inactive. Fresh complete player-status data is required; draft selection never enters the registration. A warning replaces a generic reminder in the same batch. Persisted deduplication survives restarts; late registration cannot resurrect an opted-out ID, and deliveries expire at kickoff. The server registration expires after eight days; opening the current lineup renews the week. Changes to the NFL schedule are checked hourly away from kickoff and every five minutes within 90 minutes. MFL score reads are at most once per minute per league/week in an alert window; injury reads once per five minutes. These alerts use no paid NFL requests. Apple delivery and source completeness cannot be guaranteed.

Timeline history stores observed team and player point changes separately, including negative changes, final confirmation, first observation and interrupted-check gaps. It does not reconstruct plays between checks. The phone keeps at most 12 matchups and 2,000 entries per matchup in a protected, backup-excluded Application Support file. The private worker keeps at most 64 matchups and 2,000 entries each in SQLite; both prune after 21 days. The worker records while a subscribed Live Activity is being checked, including when Blitz is closed; it cannot fill periods with no active subscription. Reading the timeline never starts another upstream poller. Phone/server observations are merged without presenting matching changes twice. Disconnect removes the local timeline, while the shared private server history ages out after 21 days.

D/ST requests are only made for explicitly requested defense teams. The existing NFL cache fetches `games/statistics/teams` no more than once per 120 seconds per live game, uses the same slower final/archive policy, and obeys the same persistent 6,000/day ceiling, provider headers and backoff. Native matching uses the explicit team-defense entry rather than summing individual defenders. Sacks, interceptions, recovered fumbles, safeties, interception-return TDs and verified total scoreboard points allowed can be shown. MFL TPA is distinct from OPA/STPA and missing fumble-return TDs/blocked kicks/return totals are not invented. The current league has no D/ST; validation uses source-shaped fixtures.


## Timeline presentation — build 61

Score changes are the primary timeline rows. Recording starts and gaps are collapsed under **Recording details**; one coverage note appears if gaps exist. With no recorded scoring changes, the page shows a short empty state. The explanation and retention period are available from the information button. This changes presentation only: stored events, gap detection, merging and polling are unchanged. Grouped observations and game-aware gap handling are future items in the [agreed review priorities](reviews/2026-09-14-priorities.md).

## Delivery

Build 0.6.3 (57) is signed, installed and launched on Josh's iPhone. The final installation recovered from a transient wireless disconnect. Both private services are deployed; 19 core client checks, 43 native checks, three distinct UI journeys and 71 service checks pass. The initial large-text timeout and crowded horizontal layout were superseded by the passing final accessibility walkthrough with stacked labels/values. See [current status](current-status.md) for evidence paths. Alerts remain opt-in, with no real lineup notification registration created by testing. Actual pre-kickoff delivery and a league using D/ST remain device/source validation beyond the fixtures.
