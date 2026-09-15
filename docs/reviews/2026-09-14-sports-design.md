# Independent review: sports app design

Reviewed September 14, 2026. This is an AI review from a sports product design perspective, not a claim of professional credentials. This first pass was completed without reading the other reviewers’ findings.

## Evidence and limits

I read the current build 60 source for all five tabs, shared navigation, search, player detail, scoring, timeline, alert settings, and the actual shared Live Activity view. I inspected the user’s September 14 timeline photo; build 60 search screenshots on Scores and Board; build 56/57 matchup, scoring-breakdown and alert screenshots; and build 57 Live Activity renderings. The older images establish layout examples, not proof that every pictured defect remains. Source now contains accessibility adaptations missing from some early build 57 screenshots; I have not reported those old clipping defects as current bugs. I did not run the app, change the simulator, send notifications, or request external scoring data. Lineup, My Team, and Standings coverage is source-based. Recommendations below are design judgments, with observed facts and inferred user impact distinguished.

The parent agent is separately simplifying timeline copy and repeated gaps. That small fix should proceed; recommendation 2 describes the remaining product direction rather than claiming the cleanup is finished.

## Prioritized findings

### 1. P1 — Give each player a consistent route to live game detail

**Observed in source:** The matchup supplies `PlayerScoringContext`, but search and roster links do not. `PlayerDetailView` only offers the Week/Player selector when that context exists. A search result can show an ordinary Week section with MFL points, but that section does not use the NFL box-score view, live NFL scoreboard, or league points breakdown. Sources: `PlayerSearchView.swift:26`, `TeamDetailView.swift:259`, `PlayerDetailView.swift:17–40`, `PlayerSummaryCard.swift:69`, `MatchupDetailView.swift:529–562`.

**Impact, inferred:** “How is my player doing?” has a different answer depending on where the player was opened. This makes the richer stats feel missing even after the data integration has succeeded.

**Change:** Resolve the selected player’s available weekly scoring context centrally. Offer the same Week detail from search, Lineup, My Team, and matchup entry, keeping each originating navigation path. Respect an explicitly browsed historical week; do not silently substitute the current week. For free agents or unmatched players, expose available NFL game stats while clearly omitting league-specific points that cannot be determined.

**Acceptance:** Open the same playing player through each of those four paths. The game clock, box score, fantasy score and available breakdown agree. Back preserves the originating page/query; historical weeks remain historical; no new per-player paid-feed polling.

### 2. P1 — Make the timeline tell the matchup story

**Observed:** The user’s photo contains four repeated update-gap rows and a recording-start row, with no score movement. Introductory and storage-policy copy bracket the list. Every event is currently rendered at nearly the same prominence; team/player score changes are separate ungrouped rows. Sources: `MatchupTimelineView.swift:12–46`; `MatchupTimeline.swift:101–121`. Gap generation currently relies on elapsed check time, so the stored event alone does not prove an active NFL game was missed.

**Impact, inferred:** A feature labeled “Matchup timeline” reads like a sync diagnostic and suggests failure even when the user needs only “what changed?”

**Change:** Show genuine score changes first, grouping observations from the same check by team and player. A concise date header and time are sufficient; label corrections as negative changes. When only administrative entries exist, show “No score changes yet” with one compact coverage note. Keep gaps discoverable as a range, not repeated full sentences. Present “observed changes” honestly; do not infer touchdown/play narratives from a points delta.

**Acceptance:** A no-change day has one empty-state message, not five diagnostic rows. A check with two player changes explains the associated team delta without apparent double counting. Reopening after a gap preserves older events and shows the gap once. Storage limits live in help, not the normal timeline.

### 3. P1 — Keep matchup context available while following a long lineup

**Observed:** Team scores and status live inside the scrolling content, while the pinned navigation title only says “Week 1 Matchup.” The inspected compact matchup screenshot has scrolled to WR/TE/FLEX with neither team total visible. The hero lacks the per-team playing/yet-to-play counts already displayed in the Live Activity. Sources: `MatchupDetailView.swift:20–99`; `ScoringViews.swift:227–241`; `Shared/MatchupActivityScoreboard.swift:22–25,50`.

**Impact, inferred:** Users must remember both totals and scroll back repeatedly to understand how a player update changes their matchup. Late in MNF, finding the few players still active requires scanning completed players.

**Change:** Once the hero leaves view, use a compact pinned matchup strip with team marks, totals, and honest live/delayed state. Add the existing per-team remaining counts to the expanded hero. After that, consider an explicit “Playing” view or jump shortcut; retain the stable position comparison as the default instead of automatically moving players during updates.

**Acceptance:** Scroll to the final starter and still identify the two totals. Counts match Live Activity, with unavailable counts omitted rather than treated as zero. No duplicate full-size hero, jumping scroll position, or forced shrinking at accessibility text sizes.

### 4. P2 — Let actual game production outrank pregame projections

**Observed in source and screenshot:** Player rows show blue `Proj.` values even for Final games; the actual stat line sits below in smaller `.caption2` secondary text. The generic score component defaults to showing projections. Sources: `MatchupDetailView.swift:481–510`; `ScoringViews.swift:75–99`; `Shared/ScoringStyle.swift:34–47`. The team-level live estimate already has a distinct label and should retain it.

**Impact, inferred:** Yesterday’s estimate receives more visual emphasis than the receptions, yards and TDs that explain today’s score. “Proj.” during a live game can also be mistaken for an updating final estimate.

**Change:** Hide routine pregame projection in final player rows, retaining it in player research for comparison. During play, label the retained value clearly as pregame and give the complete scoring stat summary at least the same hierarchy. Preserve every scoring contributor and the full breakdown, including negative stats and unsupported-rule differences.

**Acceptance:** A final TE row leads with fantasy points plus receptions, yards and TDs. Users can distinguish a fixed player projection from the team live estimate without opening help. Labels and stat lines remain readable at large text sizes.

### 5. P2 — Bring lineup readiness and alert status into the lineup journey

**Observed:** The Lineup summary emphasizes projection/margin, with deadline and submission status below. Alert controls and their status are reached through My Team → Settings → Lineup alerts. Alert settings contain two long paragraphs, including server implementation and paid request details. Sources: `LineupView.swift:535–647`; `SettingsView.swift:23–50`; `LineupAlerts.swift:224–244`. The inspected alert image is a demo screen, so it does not establish real permission or delivery state.

**Impact, inferred:** A user deciding whether their lineup is ready cannot easily see whether reminders are operational. Backend setup language competes with the actual choices.

**Change:** Add a compact readiness summary near the Lineup header: saved starter completeness, known unavailable starters, next lock, and alert status/link. Prioritize actionable issues over projected margin. Keep opt-ins separate and initially off; use one short description per option. Show operational failures as actionable status, with technical detail behind help.

**Acceptance:** A user can identify an empty slot, unavailable starter, unsaved draft, or disconnected alert setup without navigating to Settings. “On” preferences and “Connected” delivery are distinct. No notification permission prompt occurs before choosing an alert.

### 6. P3 — Refine inline search density without changing its navigation model

**Observed:** Build 60 screenshots correctly preserve Scores/Board under the search overlay and show owner plus starting status. A single result occupies a panel substantially taller than its three text lines. Panel sizing uses fixed per-row estimates plus a fixed allowance. Sources: `PlayerSearchView.swift:24–41,113–119,216+`; `/tmp/mfl60-title-final-shots/89E7542E-2FDC-4DFB-90C5-F03F8E5B0A76.png` and `0F386CC2-6824-4A71-9625-578242ADF056.png`.

**Impact, inferred:** The new interaction is materially better than a separate page, but oversized result padding hides more game context than necessary.

**Change:** Size a small result set to its actual content, preserving comfortable tap targets and full ownership information. Use scrolling only when needed. Do not revert to a full-screen search or squeeze accessibility text to recover space.

**Acceptance:** One normal-size result shows name, NFL metadata and ownership without unnecessary blank space or clipping. Five results scroll. Largest text and keyboard coexist; Back keeps the query and selected tab.

### 7. P3 — Tune My Team around the next task before adding another destination

**Observed in source:** Six equal shortcut tiles precede the roster: Schedule, Adds/Drops, Trades, Watchlist, Injured Reserve and League Activity. They become six single-column tiles at accessibility sizes. Only Trades has an attention badge. Sources: `LeagueBrowseNavigation.swift:80–102`; `TeamDetailView.swift:118–174`.

**Impact, inferred and requiring device validation:** The roster can begin well below a large tools menu, especially at larger text sizes. Equal prominence does not help users see whether there is an urgent transaction or ordinary reference material.

**Change:** Validate with a normal and largest-text My Team walkthrough, then prioritize pending actions and group reference tools more compactly. Retain all destinations and the existing tab structure; avoid another top-level feature tab until usage warrants it.

**Acceptance:** My Team exposes an urgent trade/roster action immediately and reaches the roster with less scrolling at large text. Every existing tool remains discoverable with explicit labels. No essential action depends on icon recognition alone.

## Strengths to retain

- Scores has a clear featured matchup followed by the league; side-by-side player comparisons remain stable during scoring.
- Real stat lines, explicit missing data, score precision, and league-rule differences build trust. The UI should simplify explanation without inventing certainty.
- Build 60 inline search keeps the current page, ownership and query continuity; this is the right foundation.
- Per-team Live Activity colors, centered scores, live estimates and players remaining convey identity and game-day context well. Further density increases would hurt glanceability.
- Lineup review/readback and saved drafts are valuable protections. Keep intentional submission and distinguish draft changes from the saved lineup.
- Standings offers labeled table columns, team drill-down and an explanation of order on demand. Board retains existing league conversations and drafts. I found no source-backed reason to reorganize either tab ahead of scoring consistency and timeline clarity.

## First-pass recommendation

Ship the timeline wording cleanup now. Next fix cross-entry player scoring consistency, then the scrolling matchup context. Follow with phase-aware stat hierarchy and visible lineup readiness/alert status. Search-density and My Team tool refinements are polish after those game-day needs, not blockers for another live-game test.

## Discussion and agreed priorities

After the independent pass, I read the football and Apple-design reviews and discussed the findings directly with both reviewers. All three explicitly accepted this shared sequence:

1. **P1 — Accessibility baseline:** separate readable action tint from bright brand fills; include remaining-player meaning in the expanded Dynamic Island accessibility label. These are small confirmed fixes and a release prerequisite, not a claim that they are the largest feature opportunity.
2. **P1 — Consistent, explainable weekly scoring:** provide weekly NFL detail from every player entry; prioritize league-relevant scoring stats, expose incomplete reconciliation, and make projection hierarchy phase-aware. Keep MFL totals authoritative.
3. **P1 — Lineup readiness and alert coverage:** distinguish saved/legal lineups from known unavailable/bye starters; put acknowledged, week-specific alert state and its next action in Lineup. Questionable and unknown are not Out or healthy. Never silently change or forbid an intentional legal lineup.
4. **P1/P2 — Persistent matchup context:** reuse per-team playing/yet-to-play/next-kickoff context and keep compact totals visible while scrolling. Preserve the stable position comparison as the default; any live-only view is explicit and reversible.
5. **P2 — Meaningful timeline observations:** group team deltas with contributing player changes; distinguish proven inactive intervals from real unknown coverage. Root's compact copy/details fix ships separately now. Retain raw observations and never infer exact plays or continuous coverage from deltas.
6. **P2 — Lean, honest Live Activity detail:** reduce duplicate counts; make per-side remaining text usable; distinguish cumulative game totals from the latest observed points delta. Keep the user-requested brand/week heading and centered scores.
7. **P3 — Validate navigation polish:** clarify player-search scope and verify focus/content sizing. Test My Team roster/tool discoverability before changing its hierarchy. Retain five tabs and existing navigation.

**My vote: accept.** Football accepted this sequence explicitly; Apple accepted the same sequence after discussing whether contrast belonged ahead of feature work. We resolved that disagreement by treating confirmed accessibility fixes as a small baseline package, while weekly scoring and lineup readiness remain the central product improvements.

The football reviewer correctly narrowed negative-change wording: a negative delta can be a lost fumble, interception or ordinary yardage change, not necessarily a correction. Use neutral observed-change wording unless correction evidence exists. This qualification applies to the earlier timeline recommendation.

Validation should combine the focused fixtures in each report with one end-to-end live-game journey on a phone: alert setup/actual delivery, player entry from each tab, scrolling matchup context, Live Activity handoff and timeline continuity. Contrast needs rendered checks; accessible semantics need a real VoiceOver pass. Search background focus and My Team task efficiency remain hypotheses to test, not established failures. No package authorizes additional paid-feed polling, predictive metrics, automatic lineup choices, a tab redesign, or broad implementation beyond the user's requested review.
