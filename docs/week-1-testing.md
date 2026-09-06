# Week 1 private test plan

These are live actions only when **you** submit them in the app. Automated tests use synthetic data and have not posted or changed any league roster, bid, or message.

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

Week 2 distribution is a separate step: production MFL API-client registration/User-Agent confirmation, Apple/TestFlight setup, privacy/review details, and a successful live Week 1 run. Other league configurations, native FCFS, trades, IR/taxi moves, push notifications, widgets, and Live Activities are not included in this private test milestone.

## Implementation evidence

The test suites cover current-week decoding, completed-result reads, authenticated session restoration, team-scoped draft recovery, refresh conflicts, all-bid cancellation, partial round saves, stale-baseline rejection, timeout-after-save reconciliation, restart-safe unconfirmed replies, and rejecting another owner’s matching post. Live scoring timing and actual league processing still require the checks above.

## Same-position replacements — 0.2.3 (5)

Tap a starter's down arrow (or swipe → Replace) to open a native replacement sheet. It lists only eligible bench players at that exact position, sorted by projection with unpublished values last. Locked players and IR players are excluded. Cancel leaves the lineup unchanged; selecting a replacement makes one atomic draft swap and preserves the number of starters and position counts. Nothing is submitted until Review & submit. If the incoming player was the bench tiebreaker, choose a new bench tiebreaker before submitting. Bench up arrows still allow filling an incomplete lineup.

Regression coverage includes QB/RB/WR/TE filtering, canceled/empty selection, lock/IR checks, keeping players with missing projections selectable, stale week/account/refresh/conflict rejection, draft persistence without a server write, and an iPhone UI test that opens, cancels, and completes a QB swap.
