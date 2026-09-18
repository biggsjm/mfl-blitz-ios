# Scoring visual system

## Compact matchup summary — September 17, unreleased

Josh selected option B from the matchup-card comparison. The shared summary on Scores and matchup detail now uses two stacked team rows with aligned Points and Proj. columns. Each team keeps its logo, full name, owner, record and known playing/to-play counts. Omit zero playing counts. A shared footer shows the earliest known future starter kickoff when neither team has an active player, or the matchup state otherwise. Unknown, incomplete or stale progress must not produce a kickoff claim.

During play, the projection column is labeled Live est.; final matchups omit it. Official points and live-activity receipt reconciliation retain their existing source/precision rules. Recent change indicators remain attached to actual points. Larger accessibility text moves labeled metrics below each team identity; full names and score digits remain readable. Team links remain available in matchup detail. This is a presentation change with no additional requests or refresh subscriptions.


September 9, 2026. **Approved, implemented and installed as private build 40; delivery evidence is in [current status](current-status.md).** The owner approved the visual reference and its native San Francisco typography, then requested a Week / Player segmented destination for active and finished players. This replaces density alone as the scoring milestone.

## One meaning per treatment

September 13 source update: the shared featured/detail matchup card shows each team's current season record beneath its owner, aligned with that team's identity. Reuse the latest loaded standings by franchise ID: W–L, or W–L–T when ties exist; omit records when unknown. This is the current standings record even when browsing a different scoring week. VoiceOver reads wins, losses and ties explicitly. Records follow existing standings loading and refresh behavior, without additional scoring-poll requests.

| Meaning | Treatment | Rule |
| --- | --- | --- |
| Actual points | Largest, high-contrast, tabular number; consistent column | Never replace actual points with a projection. Zero is a real reported zero, not a fallback |
| Projection / live estimate | Smaller blue-gray number, prefixed Proj. / Pregame proj. before play, Live est. for team estimates during play | Actual team points plus the remaining-time fraction of starter pregame projections; not a provider live forecast or win probability |
| Player identity | Semibold name on its own line; position/team/opponent secondary | Name and points must not compete for the same narrow line |
| Playing now | Small dot plus Live beside game context | Green indicates active state, not a winning team |
| Points changed | Signed ↑ +2.4 or ↓ −0.2 beside actual points; brief subtle tint | Difference between fresh snapshots, not an invented play description |
| Data trouble | One orange warning with last successful check age | Retain scores and their meaning; don't turn every number orange |
| Final | Quiet Final text | Finals may still receive scoring adjustments |

Reuse these treatments across league list, matchup hero, player rows and Live Activity. Keep the featured matchup. Remove decoration and repeated captions before shrinking text. Some scrolling is better than ambiguous figures. Preserve 44-point targets and expanded Dynamic Type layouts.

## Game state and feed state are independent

An NFL game can be live while the feed is delayed. A successful refresh can return unchanged points. A fantasy matchup can include live, finished and yet-to-play players simultaneously.

### Player/game states

- **Before kickoff:** player actual-points slot is — with kickoff context; projection stays labeled. A fantasy-team total can show a reported 0.0 Points, but never a fabricated total. First loaded zero isn't a scoring event.
- **Live:** actual points prominent, including a reported 0.0; dot + Live, opponent and available source clock. Team score blocks show Live est.; player rows retain their smaller labeled pregame projection. The team estimate uses the official total plus each unplayed starter projection multiplied by reported seconds remaining / 3,600. Finished players add zero; bench players never contribute. Estimates assume an even scoring rate and do not model injuries, possession or overtime. No extra requests or paid provider are used.
- **Between games:** no active-player dot when no known starters are active. Show Next game… or N yet to play only when schedule/clock completeness supports it. Don't call the fantasy matchup Final when this afternoon's games end but other starters haven't played.
- **Final:** actual points plus Final. Keep the labeled forecast secondary initially; completed-week forecast collapsing is an optional later review choice.
- **Bye:** only from explicit matching-week bye data. Missing score or zero clock is not proof of a bye.
- **Unknown / delayed / postponed:** show only supported source state; unknown stays unknown. Don't invent quarter/halftime or a kickoff delay from wall time.
- **Partial data:** missing points are —, not 0.0. Missing projection is Proj. —, not another week's estimate. A live team estimate is unavailable when scores, remaining-player counts, starter identity/clocks/projections are incomplete or inconsistent, or the snapshot is stale. Official team totals are never replaced by an incomplete sum of players. Final matchups hide projections.

### Freshness states

- **Never loaded:** known identities plus independent placeholders; one unobtrusive loading indicator, no blocking spinner or false Updated label.
- **Fresh:** one quiet Checked just now / Checked 1 min ago. Whole minutes, not ticking seconds. An anchored information popover explains source cadence and projections.
- **Refreshing:** retain content with small inline feedback. Starting a request cannot advance the last-success timestamp.
- **Stale:** Scores may be delayed · Checked N min ago. Existing foreground polling is approximately 90–100 seconds; the threshold is 210 seconds without a successful live-score check, with an immediate warning on a known failed refresh.
- **Offline:** retain saved scores with Offline · Checked N min ago. Qualify cached game state as Last known instead of unqualified green Live.
- **Recovered:** clear warning after successful source refresh; reestablish the change baseline rather than presenting an accumulated offline gap as a just-happened play.

The core client now returns a scoring receipt with the exact response's fetchedAt, including memory-cache and coalesced-read paths. The repository carries it as checkedAt/lastUpdated; unrelated catalog/projection work cannot advance it. Legacy caches without this receipt say Saved scores / Check needed. MFL's upstream publication time may be unknown: Checked plus an information explanation must not imply a broadcast-time feed.

## Recent scoring changes

1. Compare actual points only between fresh, same-season/league/week/matchup/player snapshots, matching canonical IDs.
2. Establish a baseline on first load, account/week switch, entry to an unobserved game, and recovery from a stale gap. Never manufacture new events from restored data.
3. Ignore missing/invalid values and differences below displayed score precision. Actual-minus-projection is not a recent scoring change.
4. Briefly highlight the score without moving/reordering rows or scrolling. Tint: 2 seconds around the changed value; signed badge: 60 seconds. Compact rows reserve space in their symmetric padding, outside the actual/projection block's alignment bounds; accessibility layouts reserve an in-flow line. Respect Reduce Motion; text must work without color or motion. Scores do not animate on initial appearance.
5. A Recent scoring changes disclosure appears below the scoring list only after an observed change, so its arrival does not move visible scores. Keep at most 20 entries from the current viewing session and roughly five minutes, scoped to league/week. Show player, previous → new points and coarse age. This is separate from transaction Activity.
6. Green positive / orange negative describe points direction, including opponent changes. The hero omits the redundant leading/trailing margin line. Owner and record labels occupy shared rows beneath both team names, so wrapped names do not shift their baselines.
7. A decrease can be a turnover, negative yardage or correction. Without an event type, say points decreased, not stat correction. A later final-score revision can say Score adjusted without inventing its cause.

This is snapshot-based scoring at the current request cadence: no per-player polling, play-by-play claims, new backend or background-push guarantee.

## Implementation

- Typed presentation separates actual points, forecast, game state, freshness and observed delta.
- Shared ScoreValue / ProjectionCaption / GameStateLabel / FreshnessLabel / ScoreChangeBadge components serve compact and expanded views.
- A bounded in-memory change tracker observes successful existing refreshes; it triggers no extra API requests.
- Preserve league-slot/FLEX ordering, canonical Player Detail navigation and the lineup editor's separately labeled pregame comparison.
- Keep team/opponent separate from the unbroken weekday/time caption. Fall back to stacked score/context at narrow widths instead of wrapping between the day and time.
- The build-41 symmetry refinement mirrors the hero's equal-width halves and uses shared identity/metric rows for aligned scores. League rows center the visible score/projection block beside each team. NFL context reads `ATL @ DAL` / `ATL vs DAL`, without a dot between teams.
- Collapsed Bench previews each team's actual bench subtotal, not a projected/optimal-lineup difference. Missing, duplicate or unclassified scoring data cannot be promoted to a complete total; show a dash. Official team points remain untouched.
- The visual reference is a component/state study, not a decision to remove two-team comparison or switch navigation to one-team views.
- September 13 Live Activity redesign: centered `MFL Blitz - Week N`, large actual scores, team logos at the outer edges, current records, centered Live/active-starter count and a logo-derived color blend with softly faded artwork. Projections are removed from activity presentations. A bottom line shows the latest observed score-change batch with separate change/check timestamps. Single-player attribution requires a complete, unchanged starter set whose deltas explain the official team delta; multi-player and two-team batches never invent an order. Team totals are the fallback for incomplete or unreconciled player data. Stale content hides the change line and asks the user to open Blitz. The 210-second freshness threshold, foreground update path and native deep link remain. Dynamic Island keeps the system background with logo/score/status presentations. No APNs/background service was added.
- Player taps from the matchup carry same-week, display-only scoring context. Live/finished players open Week N / Player, defaulting to Week N; pregame/unknown/explicit-bye players keep the existing player card. Week N shows points, pregame projection, opponent/state and supplied MFL scoring text. Missing raw stats get an honest fallback, not inferred yardage/TDs. Existing scoreboard refreshes update matching-week data without an additional player poller; the full profile loads when its segment is selected. Back remains one step to the matchup.

## Remaining plan

- [x] Owner approval of the visual reference and semantics.
- [x] Source/cache timestamp provenance and independent state model.
- [x] Shared components and scoped change tracker.
- [x] Apply to Scores, matchup detail and Live Activity.
- [x] Contextual Week / Player detail segments for active/finished games.
- [x] Automated state tests: pregame, mixed states, between-games, true zero, negative points, final revisions, bye, partial data, refresh-without-change, stale/offline/recovery and scope changes.
- [x] Native phone-size light/dark, long-name, largest Dynamic Type, 44-point target and Player Detail/Back checks; exact run evidence is in Current status.
- [ ] Manual VoiceOver, Reduce Motion behavior and iPad-specific review. Automated state/layout checks are not accessibility certification.
- [ ] Owner dev-device acceptance, then existing Week 1/distribution gates.

References: Apple's [color guidance](https://developer.apple.com/design/human-interface-guidelines/color) supports semantic color plus non-color cues; [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility) informs contrast, alternate indicators and Reduce Motion. These inform the proposal, not completed accessibility certification.

September 13 follow-up: the private background scoring service is activated for the owner’s development phone; see [delivery status](current-status.md) and the [service contract](background-scoring.md). Live estimates apply to the in-app team scoreboard; the Live Activity retains actual scores and observed changes.

## September 14 follow-up

Live Activity totals may temporarily lead the cached lineup. The detail hero uses only the newer matched activity receipt; the player rows and their freshness label keep the last app receipt until refreshed. Activity links now navigate inside Scores and automatically read fresh data on entry, including after an in-flight startup read.

NFL game scores, approximate regulation quarter/clock and optional possession use a separate 90-second weekly MFL read with its own receipt. Stale scores remain qualified. Available player stat lines render at regular sizes. The current actual MFL feed returns empty player stat lines, so full box-score enrichment remains a separate source decision; preview stat lines are synthetic.
