# Week 1 private test plan

These are live actions only when **you** submit them in the app. Automated tests use synthetic data and have not posted or changed any league roster, bid, trade, or message.

## Before kickoff

1. Sign in once on the updated build. Confirm your league, franchise, season, and selected week.
2. Make an unfinished lineup edit, switch tabs, pull to refresh, close the app, and reopen. Confirm the draft is retained and not submitted. Verify a submitted lineup on MFL, including the write-only tiebreaker.
3. Draft a board thread and reply, close each composer, and reopen. Post a short test message when ready; verify exactly one copy on MFL.
4. Build two conditional bid rounds, edit an amount/drop, reorder alternatives, and review before submission. Compare every round on the MFL website. Test removing an alternative, clearing one round, and cancelling all saved bids **only on bids you intend to cancel**.
5. Check the displayed calendar event against MFL. If no explicit future blind-bid date is returned, use the league-calendar link. First-come adds and unsupported waiver types still use MFL.

## During games

- Compare scoreboard totals and player-by-player scores with MFL at kickoff, halftime, and after games.
- Leave Scores open for a few minutes: a single foreground poller refreshes roughly every 90 seconds. Background the app, reopen, and check freshness.
- Briefly lose connectivity: existing scores must stay visible with an out-of-date warning; drafts must remain intact.
- Check a locked player and verify MFL rejects any now-invalid lineup. App lock hints do not replace league enforcement.
- If a waiver save stops, inspect the saved-MFL queue alongside your preserved draft before choosing what to keep. Never assume all rounds failed.
- If a post is unconfirmed, use **Check MFL without sending again**. Only manually clear the warning after inspecting MFL; do not repost a message that already exists.

## After processing / next week

- Compare successful waiver results and updated budget/roster with MFL. The native list shows recent processed acquisitions, not a complete failed-bid audit.
- Check final totals after MFL marks the week completed, including any scoring corrections.
- Reopen when MFL moves to Week 2. The default follows its current week; explicitly selected historical weeks stay selected. The lineup screen offers MFL’s lineup week when it differs.

## Before inviting the league

Week 2 distribution is a separate step: production MFL API-client registration/User-Agent confirmation, Apple/TestFlight setup, privacy/review details, and a successful live Week 1 run. Other league configurations, native FCFS, IR/taxi moves, push notifications, widgets, and Live Activities are not included in this private test milestone.

## Transactions — 0.3.0 (8)

- Waivers, Trades, and Activity share one tab. Waiver search sits below the section control and retains its query when switching sections. Loading indicators are centered; waiver refresh is scoped to waivers.
- Draft a trade, select assets on both sides, close it, and resume. Confirm the exact players, picks, optional FAAB, message, and expiration in Review. Nothing is sent by selecting assets or saving a draft.
- With a cooperating owner, send only an offer you intend to make. Compare every term on MFL; withdraw it if appropriate. Verify incoming acceptance and decline separately. Acceptance is not a guarantee that MFL has finished approval/processing or moved the players.
- Counteroffers explicitly leave the original open. The acknowledgment is required; decline the original separately if desired.
- For an interrupted action, use Check outcome without resending. Clear its warning manually only after inspecting MFL. Never repeat an offer or acceptance because a spinner stopped.
- Check Activity against MFL's recent transactions. A failed read is not an empty history. Repeated section changes reuse recent results, shared catalog/projection requests are combined, and Retry is disabled during MFL's cooldown.

Native authenticated trade reads returned all 12 teams, 433 tradable assets, and zero pending offers during development. Synthetic tests cover proposals, all three responses, participant roles, changed ownership/terms, expiration, ambiguous timeouts, persistent markers, and separate counteroffers. No real trade was sent or accepted during automated verification; the cooperating-owner checks above remain necessary.

## League-aware FLEX replacements — 0.3.0 (8)

MFL stores starter IDs rather than named FLEX assignments. The app reserves the league's required positional minimums first and labels the additional starters FLEX. League 41333's live rules were rechecked September 6: nine starters, QB 1, RB 2–4, WR 3–5, TE 1–3, giving two RB/WR/TE FLEX spots. FLEX candidates must keep every minimum/maximum satisfied; the starter's own NFL position does not narrow the picker. A league that permits another QB can allow one in FLEX; this league does not.

Test a FLEX RB → WR or TE draft swap, cancel once, then select and review. Verify required QB/RB/WR/TE slots retain their positional requirements, locked/reserve players stay excluded, and the draft survives reopening without submission. Regression tests cover caps, league-specific QB eligibility, stale slot changes, and cross-position draft persistence. The older same-position description below applies only to required positional slots in this version.

## Implementation evidence

### Daily cache and scoring slots — 0.3.2 (10)

- Open the app, allow data to load, close it, and reopen. The public player directory should reuse its original daily download; league membership is still verified. Tests cover disk-store recreation, expiry without extending the fetch date, future dates, wrong seasons, corrupt files, forced refreshes, and private-response isolation.
- Stable league reads reuse the in-memory export for up to 24 hours. Waiver balances accept at most 60 seconds of age; a submission always fetches fresh rules/balance and checks all existing ownership/queue safeguards. A repository regression exercises every tab and reconnects with only one player download.
- Open a matchup and scroll to FLEX. Qualifying extra starters should appear there with their actual NFL positions underneath, not be included again in RB/WR/TE groups. Scores and projections are unchanged. The same allocator drives lineup editing, so response ordering cannot choose different FLEX players. Partial scoring lineups retain their reported positions without guessed FLEX labels.

Build 0.3.2 (10) was installed on the connected iPhone. Read-only verification saw one initial player-directory download followed by a disk-cache hit after reopening, all 12 owner names, 446 usable Week 1 projections, and 12 teams/433 tradable assets. Core regression tests passed (56 tests); the app/unit and FLEX UI run passed (77 test functions, 97 parameterized runs), followed by a final focused cache/scoring pass. No live lineup, waiver, or trade action was submitted by automated verification.

### Refinements — 0.3.1 (9)

- Review & submit lineup now opens a native modal with the exact starters, projections, and tiebreaker. Cancel preserves the draft. If the lineup changes behind the review, submitting is blocked until reviewed again.
- Activity separates teams, player moves, and bid amounts. Verify a $0/no-drop result and a result with a dropped player against MFL; no synthetic “Player 0” or player-ID-sized dollar amounts should appear. Trade rows show both teams and asset direction.
- Waivers use clearer budget/run/queue wording, one projection note, and no placeholder rostered/trending percentages. Search remains below the section control; cancelled reads don't become false refresh failures.
- Josh confirmed the league 41333/2026 minimum bid is $0. The app uses that only when MFL omits the rule; explicit MFL data takes precedence. New drafts start at the minimum, and the editor states it. A synthetic server verifies a $0 save and exact readback; no live bid was submitted during development. Test a real $0 bid only when you intend to make that claim.
- Standings show MFL owner names beneath team names in both Divisions and Overall. Divisions stay as headings, and undisclosed names say “Owner not listed.” Confirm names in the signed-in session; automated fixtures use synthetic owners.

The test suites cover current-week decoding, completed-result reads, authenticated session restoration, team-scoped draft recovery, refresh conflicts, all-bid cancellation, partial round saves, stale-baseline rejection, timeout-after-save reconciliation, restart-safe unconfirmed replies, and rejecting another owner’s matching post. Live scoring timing and actual league processing still require the checks above.

## Same-position replacements — 0.2.3 (5)

Tap a starter's down arrow (or swipe → Replace) to open a native replacement sheet. It lists only eligible bench players at that exact position, sorted by projection with unpublished values last. Locked players and IR players are excluded. Cancel leaves the lineup unchanged; selecting a replacement makes one atomic draft swap and preserves the number of starters and position counts. Nothing is submitted until Review & submit. If the incoming player was the bench tiebreaker, choose a new bench tiebreaker before submitting. Bench up arrows still allow filling an incomplete lineup.

Regression coverage includes QB/RB/WR/TE filtering, canceled/empty selection, lock/IR checks, keeping players with missing projections selectable, stale week/account/refresh/conflict rejection, draft persistence without a server write, and an iPhone UI test that opens, cancels, and completes a QB swap.
