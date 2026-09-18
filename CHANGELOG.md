# Changelog

## 0.7.0 (70) — compact matchup summary

- Use compact team rows in the Scores featured matchup and matchup detail header, with shared Points/Projection columns, owner names and records beneath each team, and one shared next kickoff. Live estimates, score-change indicators and stale-data handling remain intact; accessibility text uses stacked metrics.

## 0.7.0 (69) — scannable player rows

- Use name/team/jersey headings and day/time → opponent → status captions across player browsing, lineup editing, waivers and matchup rows. Keep ownership and league stats visible, and adapt lineup actions to large text.
- Load optional jersey metadata in bounded, daily-cached batches shared across screens, with duplicate suppression and failure backoff. Scores and lineup editing do not wait for these reads.
- Sort the Lineup bench by the league's position order, then highest projected points; keep missing projections last within each position and tied players in a stable name order.
- Keep player search at the far right of every toolbar, after each screen's week, compose, standings information or matchup timeline action.

## 0.7.0 (68) — search and startup

- Keep the welcome screen hidden while restoring a saved login on cold launch; open saved Scores directly and show sign-in only when needed.
- Dismiss the player-search keyboard with Done, a tap in the results panel, or scrolling while retaining the query; tap the page outside the panel to close search.
- Rank exact first and last names equally in player search, then prioritize your roster, league-rostered players and cached fantasy relevance. Keep result order stable while ownership updates and place conservative typo matches after direct matches.

## 0.7.0 (67) — league beta follow-up

- Replace the large lineup readiness/notification card with a toolbar bell and an attention badge; keep lineup checks and alert preferences one tap away.
- Offer the notification permission prompt when permission has not been requested; link directly to notification settings after denial, and refresh authorization on return.
- Treat canceled Board, Lineup and Standings refreshes as navigation, retaining data without an error alert on another tab.
- Connect shared NFL stats and background notifications automatically after verified MFL team sign-in, including independent access for co-owners. No code entry or Tailscale app is needed. Keep provider request budgets and opt-in alert preferences unchanged; deployment and TestFlight delivery are recorded separately.

## 0.7.0 (66) — TestFlight candidate

- Refresh the visible tab on foreground return, reuse recent reads, and check trade badges without fetching every team's tradable assets. Keep fresh checks before and after league actions.
- Retain observed trade terms and closed offers in secure local history, with an unread badge. Only confirmed outcomes receive specific labels; disappearance alone means Closed. Background trade notifications remain deferred.
- Share paced MFL reads and persistent server cooldowns across existing background scoring and lineup alerts; accept numeric and HTTP-date Retry-After values and retain original score fetch times.
- Prepare Release production push settings, separate server push credentials, accurate privacy declarations and reproducible archive/export checks. Production credentials, Apple signing/upload and TestFlight installation remain pending.
- Includes the build 65 standings and tiebreaker fixes below.

## 0.6.4 (65) — preliminary standings and tiebreakers

- Rank the records already reported by MFL, including preliminary results before its global completed-week marker advances. Reconcile every team’s W/L/T with the matching schedule horizon.
- Keep winners ahead of losers if a head-to-head read is unavailable, while leaving unverified places blank. Preserve the league’s configured tiebreaker priority.
- Limit the head-to-head schedule cache to the same one-minute age as standings, reusing one shared league-wide read. Add a direct MFL tiebreaker-report link.

## 0.6.3 (64) — compact, consistent player areas

- Use compact mirrored rows following the owner’s reference, with points nearest the position gutter and concise name/game/stat context. Shorten stat labels without omitting scoring values or events.
- Give every player area the same height in Lineups and Live players, based on the tallest content for the current layout and text size.
- Align Live players across teams below shared team headings; include injury/status labels in area sizing without clipping scoring stats.

## 0.6.3 (63) — live players and visible ownership

- Replace grouped Matchup mode with **Live players**: active-game starters only, immediately visible under pinned official totals. Keep full rosters in Lineups.
- Show fantasy team and owner in search results and the player Week tab; share the existing cached ownership read across both player tabs.
- Simplify scoring rows by moving points arithmetic into player details and showing pregame projections only before kickoff. Preserve complete scoring stats, including touchdowns.
- Put matchup history in the toolbar and fit inline search to its measured content. Preserve league-provided abbreviations, including numeric values.
- Reuse existing NFL refresh, cache and request-budget policies.

## 0.6.3 (62) — Matchup mode and game-day clarity

- Add Lineups / Matchup mode with expandable Completed, In progress and Yet to play starter groups; preserve section choices and scroll context, with official team scores pinned after the header scrolls away.
- Use consistent weekly player details from search, lineup, roster and scoring; expose supported league point contributions and keep incomplete data explicit.
- Show lineup readiness, existing replacement actions and separate server-acknowledged weekly alert coverage.
- Group timeline team changes with their contributing players; avoid gap noise during verified quiet intervals.
- Improve action contrast, Live Activity accessible labels and remaining-player legibility; label cumulative stat context as Game totals.
- Clarify player-search scope and fit results to content. Compact My Team tools while keeping pending trades prominent.
- Reuse shared scoring reads and provider caches; no new paid NFL polling or request-budget increase.

## 0.6.3 (61) — concise matchup timeline

- Collapse tracking starts and gaps under Recording details, with one coverage note and a short empty state when no score changes are recorded.
- Move explanation and retention details behind an information button; preserve stored observations and refresh behavior.
- Record three independent AI app reviews and their agreed prioritized backlog, separately from implemented changes.

## 0.6.3 (60) — inline global search

- Expand a search bar and bounded results panel on the current page, following FeedCast's interaction, across all five tabs and matchup detail.
- Open player details in the current navigation stack; Back retains the query and Close restores the underlying page. Keep local matching and existing cache/request behavior.
- Retain build 59's lineup-alert registration crash fix; verify tab navigation, matchup return, ownership recovery and accessibility text layouts.

## 0.6.3 (59) — fix lineup-alert registration crash

- Compute the alert revision before modifying saved state, fixing the memory-access trap when enabling alerts and reopening with alerts enabled.
- Exercise permission, device-token arrival, registration, relaunch, retry and opt-out with isolated controller tests.

## 0.6.3 (58) — player stat identity translations

- One reviewed server translation table fixes 14 observed name mismatches, including Cam/Cameron Skattebo, with IDs, expected names, season, team and position checks.
- The app and background Live Activity consume the same translations; future entries require only a service update.
- Offline coverage audit flags unresolved scored players for review without extra paid NFL requests. All 172 nonzero scorers in the saved league Week 1 data now match.

## 0.6.3 (57) — game-day enhancements

- Live Activity per-team playing/remaining counts, next kickoff, verified player stat context and explicit continuation for long game days.
- League-specific points breakdown with visible missing contributions and differences from official MFL points.
- Separately opt-in pre-kickoff, unavailable-starter and incomplete-lineup alerts, using saved lineups and the private background service.
- Persistent, bounded matchup timeline with corrections and observation gaps.
- D/ST team-stat adapter and separate receipts, inside the existing NFL request budget.


Implemented private-build history through September 14, 2026. The [roadmap](docs/roadmap.md) contains future work; design proposals are not releases. Some adjacent private builds were committed together.

## 0.6.3 (56) — September 14, 2026 — complete scoring summaries and bounded final checks

- Include receiving/rushing TDs, interceptions thrown, lost fumbles, conversions and other available scoring events in matchup rows. Remove group/line truncation and preserve the existing full player box.
- Keep fast NFL player polling limited to live states, retain slower final-correction reads for a week, then archive one last snapshot. Repeated historical views and restarts reuse the saved box and known player identity. Unrelated live weeks do not accelerate historical scoreboard checks.
- Deploy the tested cache policy and install signed build 56 on the owner’s iPhone; readback confirms the version. Automatic launch was blocked by the phone lock. See [current status](docs/current-status.md) for verification and limits.

## 0.6.3 (55) — September 14, 2026 — live NFL box scores and shared refresh

- Add NFL player summaries and grouped box scores, actual game score/quarter/clock and independent freshness. Match players by unique name, NFL team and position while preserving MFL fantasy scores.
- Deploy one private shared cache with request coalescing, persistent 6,000/day ceiling, gradual slowdown, rate-limit backoff, completed-game correction checks and expiring viewing demand.
- Refresh live MFL scoring and background activities approximately every minute, join concurrent refreshes, and refresh promptly on entry while keeping existing data visible.
- Install and launch signed build 55 on the owner’s phone. See [current status](docs/current-status.md) for test evidence and remaining live-game validation.

## 0.6.3 (54) — September 14, 2026 — cleaner player game card

- Remove the inline approximate-quarter/clock explanation from the player Week card. Clock notation and scoring behavior are unchanged.
- Signed build installed and launched on the owner’s iPhone; readback confirms version 54. Live-stat provider options were researched without a subscription or service change.

## 0.6.3 (53) — September 14, 2026 — direct scoring links and NFL game context

- Live Activity taps open the normal Scores navigation stack. Newer delivered totals/estimates render immediately while an automatic MFL refresh updates player scores, with separate truthful receipts.
- Matchup rows and player Week pages add NFL game scores and approximate regulation quarter/clock from a shared, independently refreshed MFL schedule read. Available stat lines now appear at regular text sizes.
- Full live player box scores still require a suitable current-season feed; the actual MFL response contains no stat breakdowns and the historical API-NFL test is unchanged. See [current status](docs/current-status.md) for tests and phone delivery.

## 0.6.3 (52) — September 13, 2026 — fix artwork publication to background scoring

- Send the prepared artwork state to both destinations instead of re-reading a lagging ActivityKit snapshot. Keep art when a newer score arrives, and publish artwork queued during another refresh.
- Prevent old submissions crossing activity replacement and reset lifecycle state at end.
- Pass all 35 focused native checks, including the actual streamed registration JSON, and install/launch the signed build on Josh’s iPhone. The private server now receives both real logos and retains them with the same red/orange palettes through two subsequent scheduled background updates. See [current status](docs/current-status.md) for verification limits.

## 0.6.3 (51) — September 13, 2026 — persistent activity artwork and live estimates

- Preserve delivered logos/colors when Blitz reopens or an image fetch fails, including background re-registration.
- Replace activity records with live estimates; calculate the same remaining-clock estimate in foreground and background. Keep the in-app standings records.
- Retain the same-team activity across provider ID changes, require two complete final reads before automatic end, and save bounded phone/server lifecycle diagnostics. The repeated disappearance's exact cause remains unknown.
- Pass 33 server and 44 native tests and deploy the verified service. Install and launch the signed build on Josh’s reconnected iPhone; device readback confirms version 51 and the service receives projection inputs. See [current status](docs/current-status.md).

## 0.6.3 (50) — September 13, 2026 — Live Activity retention and recovery

- Separate initial activity eligibility from retention: preserve existing content through missing totals/clocks and retain the activity between early and late games. End only on positively confirmed completion, leaving the final score for 15 minutes.
- Show observed activity status and add Settings → Game day → Restart Live Activity, using fresh current-week scores and explicit dismissal reset.
- Pass 27 lifecycle, token-cleanup and existing league-extra checks. The server did not send an end for the reported disappearance; normal app reopening created a new registration. The precise original removal cause remains unconfirmed. Install and launch signed build 50 on the development iPhone; version readback and app/widget signatures verify. Exact evidence is in [current status](docs/current-status.md).

## September 13, 2026 — background push punctuation hotfix (server only)

- Fix records such as `0–0` appearing as `0u20130`: preserve UTF-8 through curl’s configuration parser before APNs delivery. The same fix preserves Unicode score signs and player-name punctuation.
- Reproduce the bug with an actual loopback HTTP transport test, then pass all 25 server tests locally and on Hephaestus. Deploy the server patch while preserving the key/subscription; the installed phone build remains 49.

## 0.6.3 (49) — September 13, 2026 — dynamic team estimates and aligned records

- Remove the redundant leading/trailing margin from the matchup hero. Keep team names, owners, records and scores in shared rows, including wrapped names.
- Add labeled Live est. team totals from official points plus each starter’s pregame projection scaled by remaining game time. Exclude bench players; suppress incomplete, inconsistent or stale estimates; hide projections at final. Player rows keep their pregame projections.
- Pass 13 scoring-presentation checks and a native alignment/estimate UI check; inspect the rendered screen and verify the signed push-enabled build. Install the verified push-enabled build 49 on the development iPhone; device readback confirms it. Automatic launch was blocked by the phone lock. See [current status](docs/current-status.md).

## 0.6.3 (48) — September 13, 2026 — Apple background scoring activated

- Complete the explicitly approved Apple App ID/Push Notifications registration, iPhone development profile and sandbox APNs key restricted to MFL Blitz. Store the key securely on Hephaestus; remove the temporary local key after validation.
- Install and launch the signed push-enabled app. The owner reports Connected; the service records a real subscription and accepted Apple updates with no reported issue. Locked-phone visible-delivery observation remains distinct from APNs acceptance.
- Keep the widget on its existing signing profile and enable manual app-profile selection in the development build script.

## 0.6.3 (47) — September 13, 2026 — private background scoring setup

- Add the native ActivityKit token lifecycle, private server connection/status and durable cleanup, preserving foreground-only builds until Apple push provisioning is available.
- Deploy a separate private Hephaestus MFL worker with 90-second shared polling, score-change attribution, APNs updates/end payloads, failure backoff and bounded token/state retention. MFL credentials stay on the device; the historical NFL service remains separate.
- Pass 24 server and 36 native checks; install signed build 47 on the development iPhone.
- **Apple delivery is pending:** approval of the Apple account changes, push-enabled provisioning and an APNs key are required before installing a push-enabled build and verifying the locked phone. See the [activation runbook](docs/background-scoring.md).

## 0.6.3 (46) — September 13, 2026 — Live Activity alignment and color

- Center each score over its team name and move logos into the header corners so logo width cannot offset the numbers.
- Select a saturated dominant hue from each logo, remove the faded photo layer and use a softer transition between team colors.
- Preserve sharper logos within the existing 900-byte limit using indexed PNGs and compact encoding; keep legacy artwork decoding and use team-name initials for numeric fallback IDs.
- Pass 13 focused model/layout checks, including full payload image decoding and visible centering of zero, short and uneven scores. Install and launch signed build 46 on the development iPhone; device readback confirms version 46.

## 0.6.3 (45) — September 13, 2026 — live matchup presentation

- Show each team's current standings record beneath its owner in the featured Scores card and matchup detail. Include ties when present and omit unknown records; reuse the existing standings data.
- Redesign the Live Activity around larger mirrored scores, outer team logos, a blend of logo-derived colors, centered MFL Blitz / week and live status, and current records. Remove activity projections.
- Add the latest observed score-change batch. Name a starter only when complete starter deltas explain the official team delta; otherwise summarize team points. Include separate change/check times and retain stale-feed handling.
- Send bounded logo thumbnails through ActivityKit using the existing cookie-free image loader. No app-group entitlement, extra polling or new backend.
- Pass focused model/artwork and native compact-layout checks, including full three-decimal score rendering; install and launch signed build 45 on the development iPhone. Background server/push updates remain next; see [current status](docs/current-status.md).

## 0.6.3 (44) — September 10, 2026 — lineup Start/Bench recovery

- Start on a full lineup now stages a legal replacement instead of adding an extra starter and blocking FLEX swaps.
- Add Move to bench to the Replace picker so existing overfilled drafts can recover even without eligible replacements. Open spots must be filled before submission.
- Stack player identity above projection/action at accessibility text sizes in replacement pickers.
- Add model and native UI regressions for cancellation, FLEX swaps, recovery, locks, stale selection and persisted drafts. See [current status](docs/current-status.md) for verification and device delivery.
- Install signed build 44 over build 43 on the development iPhone; device readback confirms version 44. No live lineup submission or TestFlight distribution.

## 0.6.3 (43) — September 9, 2026 — reviewed NFL player identities

- Add a historical player → Review MFL player match flow using a cached provider profile and the existing daily MFL catalog. Names suggest; explicit selection, compatible position and an identity-verification note are required to confirm.
- Keep reviewed pairs local and DEBUG-only, with evidence/seasons/timestamps, service isolation, collision guards and removal from the player review or Reviewed player matches list. Preview cannot persist real IDs. No automatic production crosswalk or current-season stats integration.
- Restrict profile requests to known historical-game participants; reuse the service’s 24-hour cache, persistent quota and cooldowns. Verify one real ID-only profile; never label it as a historical roster snapshot.
- Pass 20 service, 9 client, 7 mapping and one expanded native UI test. Install and launch signed build 43 on the development iPhone. Real-pair owner acceptance remains pending; exact evidence is in [Current status](docs/current-status.md).
- Update runbook, remaining plan and privacy locally. No subscription, push/merge or TestFlight distribution.

## 0.6.3 (42) — September 9, 2026 — private historical NFL test

- Add DEBUG-only My Team → Settings → NFL stats test with explicit historical seasons, game/player browsing, source timestamps and distinct missing/zero values. Synthetic Preview makes no network calls.
- Deploy the approved private Hephaestus service with owner-only credentials, Tailscale HTTPS, shared 24-hour cache, persistent 20-attempt daily cap and cooldowns; no polling or public endpoint.
- Verify one real 2024 box score and cached rereads with no additional provider calls. The free account excludes 2026/live stats; existing MFL scores, writes and player cards remain unchanged.
- Install and launch signed build 42 on the owner's dev iPhone with the private address prefilled. Seventeen service, seven initial client, one native UI and 27 retained probe tests pass. Josh subsequently confirmed the normal game list and player-stat breakdown both load, then confirmed his sample accuracy check. Broader accuracy/correction coverage remains open.
- Phone follow-up: separate safe HTTP/decoding/transport errors instead of blaming every failure on connectivity; eight client tests now pass. The isolated on-device connection check returned 335 games, then the normal app was restored. The originally reported failure was not reproduced; its cause is not claimed fixed.
- Exact tests, phone delivery and remaining gates are in [Current status](docs/current-status.md) and the [service contract](docs/nfl-stats-service.md). No paid plan, push/merge or TestFlight distribution is claimed.

## 0.6.3 (41) — September 9, 2026 — private development build

- Mirror equal-width matchup hero halves and align score baselines even when names/owners wrap.
- Center league actual/projection blocks beside their team identities; keep change-badge space outside their alignment bounds without layout jumps.
- Use consistent player score-column widths and simplify NFL captions to `ATL @ DAL` / `ATL vs DAL`, preserving the unbroken day/time below.
- Replace the bench disclaimer with both teams' bench totals while collapsed, retaining missing-data safeguards and unchanged official matchup totals.
- Install and launch signed build 41 on the owner's dev iPhone. Exact verification and installation status are recorded in Current status; no push, merge or TestFlight distribution is claimed.

## 0.6.3 (40) — September 9, 2026 — private development build

- Correct team-name search with NFL names/nicknames/code aliases and explicit league-position filtering; retain supported team units and a broad unknown-rule fallback.
- Implement the approved [scoring visual system](docs/scoring-visual-system.md): native San Francisco, primary actual points, labeled pregame projections, independent game/feed states and bounded scoring-change feedback.
- Preserve real response timestamps across caches, classify offline errors without diagnostics, retain partial/missing points as dashes, and carry the hierarchy into Live Activity.
- Open active/finished matchup players in Week N / Player segments; current-week points and supplied MFL scoring text render first, pregame players retain the existing card.
- Keep matchup day/time together below NFL team/opponent; adapt narrow rows by stacking rather than splitting the kickoff caption. Reserve scoring-change badge space and keep recent changes below the scoring lists to prevent layout jumps.
- Install and launch the signed build on the owner's iPhone. Exact test/phone evidence is recorded in Current status. No push, merge or TestFlight distribution is claimed for this increment.

## 0.6.2 (39) — September 9, 2026 — global player search

- Add a shared player-search sheet from all five primary tabs and matchup detail, preserving existing Week, Settings, compose and information controls.
- Search the cached full player catalog locally by name, NFL abbreviation or position; show fantasy team, owner and known Starting/Bench/IR status directly in results.
- Open the existing player card with immediate identity, preserve the query on Back, and return to the original tab/matchup on Close. Keep Close visible while typing and share eight session-only recent players.
- Load ownership independently, reject incomplete/duplicate roster feeds, retain multiple owners, and require an explicit supported pool entry for Free agent. Search introduces no league writes, per-keystroke network calls or startup fetches.
- Verify all 235 app unit tests and five native search journeys on iOS 18.4; repeat the search suite on iOS 27. Install and launch signed build 39 on the owner’s iPhone. See [current status](docs/current-status.md) and the [search contract](docs/player-search.md) for remaining validation and source-delivery status.

## 0.6.1 (38) — September 9, 2026 — adaptive continuity verification

- Preserve the existing craft fixes and exclude three older duplicate source files from Xcode target membership without deleting them.
- Verify the same dirty lineup, week, projected margin and confirmation through short landscape and portrait changes; no live submission occurs in the regression.
- Build and install the signed development version on the owner’s iPhone. Actual Duo runtime qualification remains pending; see [current status](docs/current-status.md).

## 0.6.1 (37) — September 9, 2026 — interface craft

- Preserve open Board messages across summary refreshes and first-page changes, with visible loading and inline Retry.
- Replace the uncalibrated Win outlook percentage with an owner-oriented projected points margin; never label another franchise’s game as Your matchup.
- Publish Scores and Lineup independently when changing week, retaining session/week guards and section-specific recovery.
- Scale featured scores with Dynamic Type and stack comparisons/metrics at accessibility sizes.
- Use authenticated league bounds for both week pickers and validation, with honest known-week fallback for missing settings and safe legacy-cache decoding.
- Add focused model and native Preview regressions. See [current status](docs/current-status.md) for actual validation and phone delivery, and [craft refinements](docs/craft-refinements.md) for the behavior contract.

## 0.6.0 (36) — September 7, 2026 — matchup opponent and kickoff

- Replace the matchup player-state line with NFL opponent and device-local weekday/kickoff, or Live/Final/explicit Bye week. Explain the time zone once beneath Starting lineups; keep names and points primary.
- Share the existing scope/week-checked availability cache across starter, bench and other-player rows, Lineup and Player Detail. Scores and navigation do not wait for optional schedule data; no per-player spinner or request is added.
- Cover missing/wrong-week data, bye/live conflicts, future kickoff with a zero clock, locale/DST formatting, cached reads, delayed schedules, largest text and matchup → player → Back.

## 0.6.0 (35) — September 7, 2026 — last-player block removal

- Allow demoting the last published player, saving/resuming the empty draft, then Review removal → Remove listing. Blank new drafts remain disabled.
- Explicit removal clears the block and Looking for note, never roster membership or starters. Fresh owner/permission/baseline checks, a durable pending marker and absent/empty export confirmation prevent false success or automatic resend.
- Keep provider acceptance separate from synthetic tests; no live listing is removed by automated QA. Settings remains on My Team.

## 0.6.0 (34) — September 7, 2026 — lineup-style block editor

- Replace the block's asset-selection form with On the block / Your roster sections, position badges and green up/orange down actions; draft picks stay secondary.
- Pin Review & submit trading block, add an exact-list review with Cancel and an explicit final send, and retain save/discard/recovery safeguards. Promoting/demoting never changes the roster or lineup.
- Move Settings from Scores to the upper-left of My Team; Scores retains the Week control.
- Bridge older notification SDK concurrency annotations without weakening actor serialization. Update native geometry checks for the new Trades selector and cover block promotion/demotion/review and the relocated Settings.

## 0.6.0 (33) — September 7, 2026 — league tools and matchup activity

- Add Offers / Trading Block inside Trades, own-player/pick publication, separate resumable block drafts, fresh owner/asset/baseline checks and durable ambiguous-publication recovery without replay.
- Add Matchups / Calendar inside Schedule with local-time agenda, explicit MFL recurrence instances and DST validation, event details, relevant destinations and one-time Apple Calendar editor handoff.
- Add contextual opt-in category/event reminders, bounded absolute-date scheduling, offline opt-out and disconnect cleanup. Optional block/calendar feeds use protected cached display and do not block startup.
- Add an ActivityKit extension for the owner's confirmed current-week matchup while a starter is actively playing. Foreground updates, stale presentation, dismissal handling and scoped deep links are included; continuous background updates are not.
- Add synthetic two-week decoder/model safety checks and native draft/calendar/reminder/large-text journeys. Whole-block removal/cash publication stay on MFL. See [current status](docs/current-status.md) for final verification and installation, distinct from implementation.

## 0.5.4 (32) — September 7, 2026 — cancelled score refreshes

- Preserve Swift and URLSession cancellation as cancellation instead of wrapping it in a user-facing transport failure.
- Keep existing Scores data and warnings during cancelled manual/polling/full refreshes, release loading gates, and permit a later foreground refresh without a false successful-refresh cooldown.
- Replace raw network diagnostic dumps with concise transport-error copy; retain only numeric network codes, never URLs or UserInfo. Genuine errors, rate limits, authentication and uncertain-write safeguards remain intact; no automatic retries are added.
- Add typed cancellation, manual/polling refresh, retry, foreground recovery, safe-error and cancelled-import regressions. See [current status](docs/current-status.md) for actual delivery evidence.

## 0.5.4 (31) — September 7, 2026 — immediate player identity

- Show the tapped player's known name, position and NFL team before ownership finishes; season/game-log reads and matching-week metrics no longer wait for that response.
- Carry only display identity in scoped canonical routes; no ownership, eligibility or mutation authority is inferred. Keep actionable errors and existing reconnect boundaries.
- Add player/scope mismatch coverage and a delayed-ownership native Preview journey. Josh confirmed build 30 fixed the spinner; build 31 addresses his remaining card-latency report. Delivery evidence is recorded in [current status](docs/current-status.md).

## 0.5.4 (30) — September 7, 2026 — player loading follow-up

- Stop optional biography from blocking the primary player card; fetch it on disclosure using its existing cache.
- Reuse loaded player detail on ordinary reappearance; explicit refresh and roster changes still refresh ownership.
- Share game-info requests across screens, cancel on league reset, and allow immediate retry after interruption. Show a spinner only for an actual running request, with a compact inline presentation.
- Add cancellation, shared-read, cache, lazy-biography and scope-isolation regressions; retain mutation gates and rate-limit enforcement. Build 29's navigation fix was confirmed on Josh's phone; build 30's exact delivery/recheck evidence is in [current status](docs/current-status.md).

## 0.5.4 (29) — September 7, 2026 — player cards and matchup navigation

- Add owner names below matchup team names and remove repetitive acronyms/positional subtotals.
- Fix duplicate matchup navigation when opening a player; retain one-step Back and working team shortcuts from pushed team pages.
- Combine player identity, current status/ownership and independently loaded season points/weekly average. Own-team status no longer links to a redundant My Team page.
- Merge weekly availability and scoring; show a paged Week / Points / NFL opponent log, with the owner-approved current-team schedule caveat behind an information button. Biography becomes a secondary disclosure.
- Move Drop into a labeled secondary action menu; explicitly distinguish releasing a player from benching them. Retain eligible-only IR, free-agent Add gates, review/preflight/readback and no automatic write retries.
- Reuse cached scoring and a shared whole-season NFL schedule; no raw NFL stats provider, new storage or permissions. Actual test/installation/merge evidence is in [current status](docs/current-status.md).

## 0.5.3 (28) — September 7, 2026 — cached startup and performance

- Display saved scores, lineup, standings, Board summaries and own-team roster during reconnection; retain them offline with compact status and Retry/Sign in. A first successful load is required to seed the cache.
- Add protected, backup-excluded, session-bound display and daily league metadata caches. Fresh membership remains mandatory; cached lineups cannot edit/submit, and mutation preflight/readback never uses display data.
- Prioritize scores/lineup ahead of optional initial feeds; defer foreground trades until My Team is selected and priority reads finish. Share season-status reads while forcing the foreground week check.
- Reuse one catalog lookup index across repositories and stop re-encoding/rewriting disk cache hits. Preserve original TTLs, stricter balance freshness, per-host cooldowns, single visible poller and no automatic write retries.
- Add cache isolation, offline/expired-session, refresh-order, mutation-invalidation and native cached-startup regressions. See [review and limitations](docs/performance-startup.md) and [current verification](docs/current-status.md); synthetic timing is not a real-phone performance guarantee.

## 0.5.3 (27) — September 6, 2026 — lineup projection comparison

- Move lineup status below the projection-card divider, beside kickoff locks; adapt the footer and numeric layout for larger text.
- Add a signed green/orange projected margin against the selected week's opponent, recalculated from edited starters. Rounded ties read Even; VoiceOver states the full comparison.
- Reuse existing same-week snapshots with no additional API requests. Incomplete projections, unknown/ambiguous matchups and failed score refreshes never imply a lead. This is not a live-score or win-probability forecast.
- Add model/native regression coverage and the [projection contract](docs/lineup-projections.md). Existing review and submission protections are unchanged; [current status](docs/current-status.md) records delivery separately.

## 0.5.3 (22–26) — September 6, 2026 — direct My Team tools and standings

- Replace Transactions and Manage roster with six direct shortcuts: Schedule, Adds / Drops, Trades, Watchlist, Injured Reserve and League Activity. Two columns become one at accessibility text sizes; every button has its own accessible label and route. Trades alone carries the trade-attention count.
- Build 23 makes every navigation glyph accent green, including Injured Reserve. Contextual medical-bag actions stay neutral; the shortcut is navigation, not a player move.
- Builds 24–25 were interim placement/diagnostic iterations. Build 26 implements the approved [standings pattern](docs/standings-pattern.md): one record/place line, numeric ordinals, division name or actual league-name fallback, and matching-context standings navigation. Preseason does not claim first place; unresolved ranks remain blank.
- Replace the incorrect API-array-index rank with supported league-configured PCT/H2H/PTS/DIVPCT comparisons. Compute division and overall places separately; true exhausted ties use competition ranks. Missing data, unreconciled H2H or cycles fail conservatively. MFL's report remains the authority for custom/manual orders.
- Keep the standings selector visible while scrolling; adapt headers and table rows at accessibility text sizes. Same-name divisions stay distinct by ID. Reuse cached league/standings/schedule reads, with no per-team network fan-out.
- Fix the native IR navigation test to return toward My Team's header after inspecting a player, instead of searching farther down a lazily loaded list. Eligibility and actual-control assertions remain intact; no test is skipped.
- Adds / Drops reuses the available-player browser and saved waiver queue, with a My roster view for standalone drops. Person-plus offers Add now and Place waiver bid when both methods are supported. Search stays below the picker and preserves a separate query for each side.
- Injured Reserve shows capacity, current IR players with activation and eligible active-roster players with neutral medical bags. Drop uses a red person-minus. Existing review, final confirmation, fresh preflight and exact membership readback remain mandatory.
- Scoped roster-tool state rejects mismatched/late results and disables actions after failed refresh without discarding known roster display data. No new backend, private response persistence, automatic writes or polling is introduced.
- Updated native/model regressions and the [direct-tool contract](docs/my-team-shortcuts.md). [Current status](docs/current-status.md) records actual test and phone delivery evidence separately from live-owner acceptance.

## 0.5.2 (21) — September 6, 2026 — My Team and compact player actions

- Player Detail uses compact person-plus Add, red person-minus Drop and neutral medical-bag IR buttons inside its ownership card. IR appears only for an eligible player on the owner's active roster; existing IR players retain Activate. Spoken action/player labels and explicit review/confirmation remain.
- Add now preserves MFL's strict player-specific acquisition decision, including malformed/conflicting flags. Individually locked free agents cannot open immediate-add review. Supported first-come adds remain available in mixed blind-bid/FCFS leagues; the UI does not invent a lock reason or unlock date.
- My Team shows official league standing and matching Transactions, Schedule and Watchlist navigation cards. Its header scrolls with the roster; other-team pages retain their Roster/Schedule picker.
- The own-team roster groups players by position and sorts by actual season-to-date fantasy points. One batched, cached YTD read replaces lineup-assignment fetching. Missing values show “—” and sort last; no projections or placeholder totals are substituted.
- Regression coverage includes strict Add gates, finite/missing/negative season totals, cache/request counts, independent native navigation, symbol accessibility, eligible-only IR and confirmation cancellation. [Current status](docs/current-status.md) records final verification and device delivery separately from live-owner acceptance.

## 0.5.1 (20) — September 6, 2026 — owner-feedback fixes

- Move to IR is disabled in Player Detail, Manage roster and review unless the current scoped injury report lists Out/IR. Loading, failed, stale, other-week and unknown designations cannot enable it. Fresh preflight and MFL's final rules still apply.
- Visible-section refreshes no longer fan out to every main feed. Ordinary watchlist and roster-review reads reuse caches; actual mutation preflight/readback stays fresh. Scoring history loads only after View scoring history is tapped. Default request spacing increases to 1.25 seconds.
- Cooldowns are scoped to the rejecting server as MFL documents, so a public availability-feed 429 does not automatically block a different league server. Same-host requests stop until Retry-After expires; no host switching or automatic import retries.
- Trade composer and team-tool destinations now share typed navigation so player research returns to the asset picker or roster moves with selections intact.
- Compatibility follow-up gives roster menus explicit independent touch targets and stable accessibility identifiers; native tests handle iOS 18 menu/Back-button differences, scroll large-text targets clear of bars and tap the tiebreaker picker's actual value control. Full Xcode 16.4 / iOS 18.5 CI passed before merge; [current status](docs/current-status.md) records exact evidence.
- Signed build installed and launched on Josh's iPhone. See [current status](docs/current-status.md) for regression evidence and remaining live-owner checks; reducing request pressure does not eliminate MFL's variable rate limits.

## 0.5.0 (19) — September 6, 2026 — player tools

- Shared official injury, opponent/kickoff and bye context in player details, roster, lineup/replacements and available-player rows. Missing reports are not proof of health; acquisition locks remain separate from lineup locks.
- League-scored player history, season total/average and recent-form chart. Initially reads four completed weeks, with explicit earlier-page loading; missing scores remain distinct from zero. Opponent points allowed are position totals, not invented per-game averages.
- MFL watch/unwatch with fresh readback, My Team → Watchlist, waiver filtering and durable uncertain-toggle recovery. Owner-supplied empty/singleton watchlist and abilities responses verified the private formats.
- Reviewed first-come add/drop and IR/activation through My Team → Manage roster and Transactions → Waivers. Exact owner permissions, supported formats, fresh roster/limits and acquisition eligibility gate writes. Activation may include an explicitly reviewed drop.
- Roster changes persist a marker before their only import and require exact current-membership readback. A pending move blocks other roster-affecting writes until checked. Refresh preserves lineup, waiver and trade drafts.
- Contextual player research links in waiver/trade surfaces preserve asset-selection controls. New core/model/native safety and two-week synthetic journeys; [current status](docs/current-status.md) records final test, CI and device evidence.
- The [approved plan](docs/player-tools-plan.md) retains trading block, calendar/reminders, polls and playoff brackets as the next four features, not part of this increment.

## 0.4.1 (18) — September 6, 2026

- Board composers use Close. Empty composers close immediately; meaningful content offers Save draft, Discard draft or Keep editing in a centered alert.
- A visible Drafts section on Board opens saved new threads and replies. Threads with an unfinished reply offer Resume reply.
- Removed the storage-specific composer callout. Empty drafts are omitted; confirmed save/discard failures keep the composer open, and discarded/posted drafts cannot be recreated by late field callbacks.
- Added focused model/native draft regression tests and updated the [Board contract](docs/board-drafts.md), owner checklist, privacy notes and remaining plan. Trade composer controls are unchanged by this Board-specific update.
- Pre-merge compatibility fixes: roster requests use a bounded task group to avoid Swift 6.1 async-let cleanup crashes; player ownership headings/rows have stable accessibility identifiers across iOS versions. No tests were removed or skipped.

## 0.4.0 (17) — September 6, 2026

- My Team replaces only the center Transactions tab, with a native team-logo/initials icon, visible Transactions entry and preserved trade badge. Dedicated Lineup stays one tap away.
- Shared read-only team rosters and Player Detail: canonical identity, current ownership/status, available matching-week metrics and optional MFL biography. Lineup arrows remain independent actions.
- Team and league season schedules use one shared cached export, configured season bounds, explicit future/unset states and route-local matchup scoring. Browsing does not change lineup drafts or the Scores/Lineup week.
- Concise schedule freshness ("Updated just now" / "Updated 2 min ago") without seconds.
- Contextual links from Standings, lineup identity, matchup players/teams and schedule participants; no new global search or second lineup editor.
- Regression coverage for caches, old-session results, draft isolation, duplicate matchups and native navigation. Corrected propagated accessibility identifiers, standings column spacing and synthetic player detail coverage.
- Updated status, remaining plan, API/cache/privacy notes, feature contracts and owner checklist. Full history and additional waiver/trade player links remain planned; see [current verification](docs/current-status.md).

## 0.3.7 (16) — September 6, 2026

[`e779e4b`](https://github.com/biggsjm/mfl-blitz-ios/commit/e779e4b)

- Prominent, persistent Create trade / Resume trade; one confirmed-empty state; secondary refresh/MFL/discard options and visible error recovery.
- Cancel and rollback in trade editing; Save & close disabled for blank drafts; no empty draft just from opening; fresh editor identity and late-autosave protection.
- Fixed first-tap Decline/Withdraw presenting default Accept review by passing one identifiable action payload into a fresh review.
- Full app unit suite plus five trade UI journeys passed: 96 functions / 121 executions. Built, installed and launched on the owner's phone. No real trade action performed by QA.

## 0.3.6 (14) — September 6, 2026

[`9465ce6`](https://github.com/biggsjm/mfl-blitz-ios/commit/9465ce6): shared explicit Week N calendar controls on Scores/Lineup, Settings upper-left on Scores, more legible crossing-route icon, and concise lineup replacement copy without storage-specific footers.

## 0.3.5 (13) — September 6, 2026

[`2a99834`](https://github.com/biggsjm/mfl-blitz-ios/commit/2a99834): eligible starters as well as bench candidates, FLEX swaps and atomic multi-step rotations, scoped slot persistence and concise arrow-based move previews. MFL starter membership remains distinct from local slot placement. See [lineup behavior](docs/lineup-starter-swaps.md).

## 0.3.4 (12) — September 6, 2026

[`e8bff54`](https://github.com/biggsjm/mfl-blitz-ios/commit/e8bff54): original crossing football-play routes for the Lineup tab, native template tinting and accessibility/asset tests.

## 0.3.3 (11) — September 6, 2026

[`d06f25b`](https://github.com/biggsjm/mfl-blitz-ios/commit/d06f25b): decoded catalog reuse, shared-read cancellation fixes, malformed date/Retry-After and duplicate-ID defenses, fewer trade readback downloads, live clock fallback and four synthetic managers across two accelerated weeks. See [audit report](docs/two-week-synthetic-testing.md).

## 0.3.0–0.3.2 (8–10) — September 6, 2026

[`688fcfb`](https://github.com/biggsjm/mfl-blitz-ios/commit/688fcfb) consolidates these private builds:

- **0.3.0:** Transactions hub and native trade proposals/responses, durable verification markers, independent refresh/search improvements and league-aware FLEX replacement.
- **0.3.1:** correct transaction-type/amount parsing, owner names in standings, lineup modal review, clearer waiver wording and confirmed $0 minimum fallback for league 41333/2026.
- **0.3.2:** daily persistent public player catalog, stable league memory caching with fresh balance/preflight exceptions, and shared FLEX allocation for live scores.

## Earlier private milestones — September 5–6, 2026

- **0.2.5:** safe league icons/logos in scores, matchup headers and standings; cookieless bounded image loading and initials fallback.
- **0.2.3–0.2.4:** required-position replacement sheet and starter projection comparison, later expanded by 0.3.0/0.3.5.
- **0.2.2 (4):** projection decoder tolerates anonymous empty rows without dropping the entire valid feed; authenticated read-only device verification.
- **0.2.1:** league-scored MFL/Fantasy Sharks projections and nonblocking section loading after bounded account reconnection.
- **0.2 / initial builds:** foreground scores/final reconciliation, secure session and scoped draft restoration, conditional-waiver and board verification, anchored standings info, direct lineup controls, matchup drill-down and verified lineup submission.
- Initial foundation: SwiftUI five-tab app, original branding, Champion Hall preview, MFLCore, login/host redirect handling and year formatting. Preseason scoring unavailability no longer prevents account entry; connected writes are not mislabeled as safety preview.

## September 6 documentation baseline — before 0.4.0

Updated release status, remaining plan, API/cache/storage descriptions, privacy/security and contributor guidance; consolidated the agreed but unimplemented My Team/schedule/player-detail directions. That earlier documentation-only update did not increment the app version; 0.4.0 subsequently implements the initial My Team slice.
