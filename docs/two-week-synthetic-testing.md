# Performance audit and synthetic user testing — 0.3.3 (11)

Historical report for 0.3.3, September 6, 2026. Original benchmarks and counts below remain tied to that build. The current installed release is **0.3.7 (16)**; see [current status](current-status.md) and the [remaining plan](roadmap.md).

## Subsequent regression evidence

Build 16 passed the full app unit suite (including these four two-week model scenarios) plus five native trade journeys: 96 functions / 121 executions, no failures or runtime warnings. This does not mean all 11 historical UI journeys below were rerun locally in that build-16 selection. The documentation audit also reran all 62 MFLCore tests successfully in a fresh build directory.

Later click-through testing found UI-state bugs that model scenarios alone did not catch: first-tap Decline/Withdraw could show the default Accept review, and reused composer state could redisplay canceled edits. Fresh identifiable response payloads and explicit editor identities fix these in 0.3.7; targeted native tests assert action labels and cancel/reopen behavior. See [trade release details](trade-inbox-ux.md). No real league action was performed by those tests.

## Scope and limits

Four synthetic managers use the production `AppModel`, `TransactionsModel`, `LiveMFLRepository`, and MFLCore request/response pipeline against a shared, stateful in-memory league. An accelerated game clock advances through pregame, live games, final results, and the next week. No network transport, real credentials, or real league writes are involved.

This is automated persona/scenario testing, not a study with human participants, two elapsed real-world weeks, a load test of MFL's servers, or a substitute for the live Week 1 checklist. Waiver awards use deterministic fixtures without ties; they do not reimplement MFL's processing rules. Cache expiration is tested separately with dated records, not by advancing the game clock.

| Synthetic manager | Emphasis | Two-week coverage |
| --- | --- | --- |
| Avery — casual manager | Scores and essential actions | Position-by-position scores, two FLEX slots, lineup review/save, receive and accept a trade, reply to a board thread, historical selection and scoring corrections |
| Morgan — lineup optimizer | Lineups and conditional waivers | League-eligible FLEX replacements, projections, $0 alternatives, reorder and restore priority, submit two rounds, cancel the second round, verify the retained queue |
| Casey — active trader | Cross-manager transactions | Propose a trade in each week, exact incoming terms on Avery's account, acceptance/readback, updated assets and activity |
| Riley — commuter | Unreliable connectivity | Board timeout after save without duplicate posting, retained scores during offline refresh, reconnect, expired authentication, private draft recovery |

All four managers also submit legal lineups and bids, see processed pickups/balances, reopen the app models, inspect standings owner names, and verify that kickoff locks prevent replacement. The two weeks have different opponents, projections, scores, and free agents.

The scenario checks exact synthetic mutation counts: eight lineup saves, twelve waiver-round imports (including Morgan's cancellations), two trade proposals, two acceptances, and four board posts/replies. Lost board acknowledgements must not increase the post count. Existing focused tests additionally cover partial waiver saves, stale lineup/offer baselines, trade decline/withdrawal/counteroffers, ambiguous acceptance, expired offers, unknown assets, and team-scoped drafts.

Native XCUITest journeys complement these model/API scenarios: scores and FLEX drill-down, replacement/cancel/review, direct lineup controls, waiver search placement, activity formatting, trade inbox/review, trade draft recovery, board draft recovery, standings owner names, and a two-week offline-preview journey through the visible tabs. Final-button UI testing explicitly enters and verifies offline preview first.

## Bugs fixed

- A canceled initiating caller could discard a successful shared read, causing an unnecessary repeat download. Validated responses now publish within the shared operation; each canceled caller still receives cancellation. Forced preflights and invalidations retain their newer-response protections.
- A successful trade action fetched the inbox again after authoritative readback. The receipt now carries that readback snapshot. A response journey needs three pending-trade/assets snapshots total (initial inbox, preflight, readback), not four; the POST and confirmation protections are unchanged.
- Malformed trade expirations could turn into never-expiring actionable offers or unsafe integer conversions. Invalid nonempty dates now fail decoding; missing/zero expiry remains supported.
- Invalid numeric rate-limit headers could create nonfinite countdown values. They now use the existing finite fallback cooldown without automatic retries.
- Duplicate player IDs could reach unique-key dictionary construction. Catalog decoding now rejects ambiguous duplicates before the app can build those dictionaries.
- The two-week scenario reproduced live player clocks being labeled Pregame when aggregate currently-playing counts were absent. Reported active starter clocks now supply a fallback. Missing clocks and a playing bench alone do not prove a live matchup; completed-week results remain authoritative.

## Performance

- The validated, decoded player catalog is retained alongside its existing raw cache entry. It shares the same expiration, invalidation, and forced-refresh rules. Tabs no longer reparse thousands of player records on each warm read. The public disk cache retains its original daily fetch time; private data is not added to it.
- Synthetic Mac debug benchmark: 20 warm reads of 10,000 players measured **414 ms before** and **under 1 ms after** (about 0.03–0.04 ms in the measured runs). This isolates catalog reuse, not total launch time or an iPhone frame-rate benchmark. Test correctness checks also prove one download plus fresh data after invalidation/forced reload.
- Waiver filtering/sorting is evaluated once per view-body update instead of separately for the rows and empty-state footer.

## Reproduce

```sh
swift test --package-path Packages/MFLCore
xcodebuild -project MFLBlitz.xcodeproj -scheme MFLBlitz \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MFLBlitzTests -only-testing:MFLBlitzUITests test
```

Choose an installed iPhone simulator if that model is unavailable. Run simulator jobs serially: overlapping test runs targeting the same simulator can terminate the test runner. A simulator launch failure is not recorded as an app pass.

## Historical verified results — 0.3.3, September 6, 2026

- **62 MFLCore tests passed**, including the catalog benchmark, cache cancellation/invalidation, duplicate IDs, malformed trade dates, and invalid rate-limit headers.
- **78 app test functions passed**, including all four managers completing both weeks, conditional bid reordering/cancellation, cross-manager trades, lost board acknowledgements, offline recovery, week rollover, corrections, and private draft isolation.
- **All 11 native UI tests passed** on the iPhone 17 Pro simulator. The two-week UI journey saved a preview lineup in each week, selected the required Week 2 bench tiebreaker, opened both matchup details/FLEX groups, and visited all transaction sections, standings, and board. No runtime warnings were reported in the successful UI result.
- One earlier UI run lost its simulator test-manager connection; it was rerun serially. The new two-week UI script initially omitted the required Week 2 tiebreaker selection: the app correctly blocked submission, and the script was updated to perform that manager action. These intermediate runs were not treated as passes.
- **0.3.3 (11) built and installed on Josh's iPhone.** A read-only launch reused the on-disk player catalog, loaded 12 teams/433 trade assets, 12 owner names, and 446 usable Week 1 projections (17 of 18 roster players had values). No startup error was logged. The bounded console capture ended at its configured 35-second timeout; that was not an app crash.

## Still requires real-world validation

- Compare actual MFL live clocks, totals, corrections, and FLEX lineups during Week 1.
- Josh should deliberately verify any real lineup, bid, trade, or board action on MFL.
- MFL client registration/rate limits and TestFlight distribution remain release prerequisites.
- Synthetic managers do not validate real human comprehension, VoiceOver usability, every league configuration, MFL processing/tiebreakers, or production network conditions. Follow [the live checklist](week-1-testing.md) before inviting the league.
