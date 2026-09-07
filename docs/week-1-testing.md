# Week 1 owner test and Week 2 go/no-go

Updated September 6, 2026 for **0.5.3 (26)**. It includes six direct My Team destinations and the shared numeric standings pattern. See [current status](current-status.md) for actual delivery/test evidence and [roadmap](roadmap.md) for remaining work. Use a validated, installed build for owner testing.

These checks remain open unless explicitly marked with an observation. They are **real actions only when the owner intends and confirms them**. Automated tests use preview/in-memory data and have not changed a real roster, bid, trade or message. Use a disposable league for destructive, invalid or interruption tests; never submit an unwanted live action just to complete this list.

## Already observed

- Josh reported successfully submitting a lineup and seeing Week 1 projections.
- Builds 0.5.0 (19) and 0.5.1 (20) installed and launched on Josh's phone September 6; the latter contains the IR and request-pressure fixes. Delivery/launch is not a complete live workflow audit. Josh previously reported the My Team screen looked good; its detailed update timer was then simplified. Earlier read-only device checks verified owner names, franchise artwork, authenticated projections and daily catalog reuse. Full schedule comparison remains unchecked below.
- Core, app-model and native UI checks passed as described in [current status](current-status.md). Four synthetic managers completed two accelerated weeks; those are not actual Week 1 results.

## Before kickoff

- [ ] Confirm version/build, league, franchise, season and Week N after sign-in/restore. Reconnect must finish or offer cancellation, not block indefinitely; each section loads independently.
- [ ] Make a lineup edit, switch tabs, refresh, close/reopen and confirm the draft survives without submission. On an intended submission, compare saved starters on MFL. Verify the tiebreaker on MFL separately: the API cannot read its saved state back.
- [ ] Check a starter's projection beside candidates, including a genuinely missing value. Missing values remain a dash, not zero; projections are pregame, not a live forecast.
- [ ] Check Week N controls on Scores/Lineup and Settings upper-left on Scores. Avoid changing an active draft's week unintentionally.
- [ ] Check the Lineup projection card against both teams' Week 1 projected starters: positive margin green, negative orange, rounded tie Even. A substitution changes the projected margin without submitting. Status sits beside kickoff locks (stacked at larger text); incomplete or wrong-week opponent data never implies an advantage. See [comparison rules](lineup-projections.md).
- [ ] Confirm owner names and the [standings pattern](standings-pattern.md): before results, `0–0 · Warner` without a made-up first place. Later, compare division rank in Divisions and league-wide rank in Overall against MFL. Matching records alone do not mean a tie. Unknown/custom/cyclic cases must not invent rank. Info opens an anchored popover; missing owners are not guessed. Check artwork fallback and long names.

### Starter and FLEX replacement

MFL stores starter IDs, not named FLEX slots. The app allocates league-required minimums first, then qualifying extras as FLEX. Champion Hall's reviewed rules are nine starters: QB 1, RB 2–4, WR 3–5, TE 1–3, yielding two RB/WR/TE FLEX positions. Other leagues must use their own rules.

- [ ] Required-position replacement includes eligible bench players and compatible starters in FLEX, not just the bench. FLEX offers every qualifying position permitted by league limits, not only the occupant's NFL position.
- [ ] Swap RB/WR/TE with FLEX and reverse it. Compatible starter-only swaps keep everyone starting and require no MFL membership write.
- [ ] Try a cross-position move into FLEX. Cancel/Back before the second choice must change nothing; completing the follow-up applies the rotation atomically. Review any resulting bench-to-starter change before submission.
- [ ] Confirm locked/reserve players are excluded, stale/conflicting picks are rejected, and a promoted bench tiebreaker requires another valid tiebreaker before submitting. Observe lock behavior; test deliberately invalid submissions only in a disposable league.

### My Team, players and schedule

- [ ] My Team and other-team headers use the same record/place pattern: e.g. `6–2 · 1st in Warner`, or the actual league name without divisions. Tap to open that team's matching standings context; the scope selector should remain accessible. Schedule, Adds / Drops, Trades, Watchlist, Injured Reserve and League Activity open distinct pages in that order without changing lineup/trade drafts; the badge stays trade-specific. Other teams do not display your tools.
- [ ] Compare My Team's position-grouped roster and season-to-date points with MFL. Players sort highest to lowest within each position; real zero/negative totals remain distinct from missing “—” values. Pull to refresh after processing; no Starting/Bench assignment callout should reappear.
- [ ] Compare the current roster and labeled starting/bench assignments with MFL. Generic roster status must not be guessed as Bench. Open players and check ownership, available matching-week points/projections and optional biography.
- [ ] Compare your remaining opponents and the league timeline against MFL, including playoff boundaries. Future games must not show fake scores; missing opponents are not assumed byes.
- [ ] Make an unsent lineup edit, browse a different schedule week/player/team, then return. The edit and selected Lineup/Scores week must remain unchanged. Check Back and section/scroll restoration.
- [ ] Open this week's schedule matchup and confirm player scoring matches Scores. Backgrounding stops polling; returning does not create duplicate refreshers.

### Waivers and Activity

- [ ] Search stays below Available / My roster in Adds / Drops, preserving a separate query for each side. Trades and League Activity open directly from My Team. Loading is centered; a failed read is not an empty pool/history. Retry respects MFL's cooldown.
- [ ] Build two conditional rounds, edit amount/drop, reorder alternatives and review the complete queue. When you intend to submit, compare every saved round on MFL. Remove/clear/cancel only requests you intend to remove.
- [ ] Check the $0 minimum for league 41333/2026. It is an owner-confirmed fallback only when MFL omits the rule; explicit MFL data wins. Make a real $0 bid only for a claim you actually want.
- [ ] Compare the displayed explicit future blind-bid event with MFL. Missing dates are not guessed. Supported first-come adds use the native roster-move review; unsupported formats/windows retain the MFL link.
- [ ] Compare Activity/recent waiver results with MFL: added/dropped player names, bid amounts and trade direction; no “Player 0” or ID-sized dollar amounts. These are recent processed acquisitions, not the complete unsuccessful-bid report.

### Trades and drafts

- [ ] Create trade is obvious on the direct Trades page and stays visible while scrolling. A confirmed empty inbox says No active trades; loading/errors/unresolved actions never falsely look empty. A saved draft changes the action to Resume trade.
- [ ] Open a blank composer: Cancel is available and Save & close disabled. Whitespace or only changing expiry does not enable it; choosing a partner/assets or entering a message does. Saving an incomplete draft must not send an offer.
- [ ] Save partner/assets, reopen, change them, then Cancel → Discard changes. Resume must show the original partner and all original assets. Canceling a new counteroffer must not leave an unwanted draft.
- [ ] Review exact players, picks, FAAB, message and expiry. On the **first** tap of Decline or Withdraw, check the matching review title/button, then Cancel. Accept must only open from Accept; merely opening a review performs no action.
- [ ] With a consenting owner, send only an intended offer and compare every term on MFL. Verify acceptance, decline and withdrawal separately on appropriate offers/test fixtures. Do not assume acceptance means approval/processing or player movement has finished.
- [ ] A counteroffer is a separate offer; acknowledge that the original stays open and decline it separately only if intended.
- [ ] For an actual interrupted action, use Check outcome without resending. Inspect MFL before manually resolving an unconfirmed warning. Never repeat an offer/acceptance merely because a spinner stopped.

### Board

- [ ] Close an empty thread/reply: no save prompt or empty draft. With text, Close offers Save draft / Discard draft / Keep editing. Save and reopen via Board → Drafts (or Resume reply in its thread); confirm the correct text. Discard must not resurrect after reopening. Post only an intended message and verify exactly one matching copy on MFL. See the [Board interaction contract](board-drafts.md).
- [ ] If a post is unconfirmed, use Check MFL without sending again. Clear its warning only after inspecting MFL; do not repost an existing message.

## During games

- [ ] Compare team totals and player points/FLEX with MFL at kickoff, halftime and after games. Open every relevant matchup; unclassified/incomplete data must not invent slot assignments.
- [ ] Leave Scores/detail foregrounded for several minutes: one poller refreshes about every 90 seconds. Background/reopen and check the update state, clocks and standings. No background push is promised.
- [ ] Briefly lose connectivity: previously loaded scores remain visible with a warning and drafts stay intact. Recover without duplicate submits or an endless reconnect overlay.
- [ ] Check lock hints against MFL's actual rules. App hints do not replace server enforcement.
- [ ] If a waiver save stops mid-queue, compare saved rounds with the preserved draft. Some rounds may already have succeeded; do not assume a complete failure or blindly resend.

## After processing and Week 2 rollover

- [ ] Compare awarded players, roster changes and remaining budget with MFL after waiver processing; no guessed outcome before processing.
- [ ] Compare official final totals and later scoring corrections after MFL marks Week 1 complete.
- [ ] Compare completed-week division/overall places and pairwise H2H tiebreakers with MFL's signed-in standings report. Record any manual/custom commissioner order, median-win adjustment or unresolved comparison; fixtures are not live-rank certification.
- [ ] Reopen at Week 2: the default follows MFL current week, while explicitly selected historical weeks remain selected. Lineup offers MFL's lineup week when different. Week-specific drafts and tiebreakers stay correctly scoped.
- [ ] With actual users, check small-screen/iPad layout, light/dark appearance, long names, large text, VoiceOver and non-gesture actions. Automated synthetic personas are not a comprehension/accessibility study.

## Week 2 release decision — still pending

Do not invite the league until P0 [release gates](roadmap.md) are complete: live Week 1 evidence, intended-write verification, regression/manual usability checks, production MFL registration/exact User-Agent, Apple signing/TestFlight/privacy/review setup, safe support/security reporting and Josh's go-ahead. Unsupported formats must be clearly excluded from the release scope with a usable MFL fallback.

My Team, player detail and fantasy schedules are included and need the live comparisons above. The 0.5.0 player-tools increment adds progressive fantasy history, watchlists, native FCFS and IR for supported formats; use the checks below before considering those live-owner certified. Taxi management, notifications, widgets and Live Activities remain unavailable.

## Record findings safely

For each open check, record **build, device/OS, selected week, timestamp/time zone, expected behavior, observed result, pass/fail and follow-up issue**. Compare sensitive receipts inside MFL; do not publish cookies, credentials, private messages, trade terms, bids or authenticated payloads. Sanitized screenshots and synthetic reproductions belong in public issues; sensitive security details require a private channel.

A complete game-week result is not recorded yet. Keep unchecked items unchecked until observed; dates and aggregate automated test counts do not close them.


## Player tools 1–5 — intentional owner checks

Do these only for moves you actually intend. Automated journeys use Preview, not the live league.

- [ ] Compare an Out/Questionable player, opponent, local kickoff and bye against MFL. An absent report is not proof of health; NFL schedule is not a live score feed.
- [ ] After Week 1 completes, compare one player's points/zero/missing week, season total and average. Earlier history loads only on request. Current empty preseason values should stay absent.
- [ ] Compare opponent position points-allowed totals with MFL; these are not per-game averages or forecasts.
- [ ] Star/unstar a player and confirm MFL's watchlist, My Team Watchlist and the waiver filter agree after reload. Preserve unrelated saved players.
- [ ] In an open first-come window, review an intended add (and necessary drop), cancel once, then submit only the intended move. Verify membership, lineup/waiver draft conflicts, free-agent pool and Activity.
- [ ] Verify locked/unavailable players and unsupported/closed capabilities cannot be submitted as immediate adds.
- [ ] Confirm Move to IR is absent from Player Detail (build 21+) and absent from Injured Reserve's eligible list for players without Out/IR, including Questionable, and while the injury report is unavailable. Compare an eligible player's designation to MFL before an intended move.
- [ ] On build 21 or later, check compact Player Detail actions in Light/Dark and preferred text size. Compare a locked free agent and an unlocked FCFS player: only the latter should offer enabled Add review. Generic lock wording must not invent a waiver deadline. Drop must still require explicit review and confirmation; cancel unless it is an intended move.
- [ ] Compare ordinary browsing and section refresh after the build-20 traffic changes. If MFL returns 429, honor its wait; note the screen/build without repeated retries. No claim of immunity to MFL's variable limits is made.
- [ ] For an actually eligible Out/IR player, compare capacity, review Move to IR and verify on MFL. Later activate, including an explicit reviewed drop only if needed. No starter or FLEX position should imply eligibility.
- [ ] For any unconfirmed action, use Check status/MFL rather than retrying the import. Resolve the notice before disconnecting or making another roster-affecting move.
- [ ] Verify the updated build does not alter existing unsent lineup/waiver/trade drafts simply through research navigation.
