# Current app status

Audited September 6, 2026. This is the implementation/evidence snapshot; [roadmap](roadmap.md) is the remaining execution plan. Design proposals do not describe installed features.

## Installed baseline

- **MFL Blitz 0.3.7 (16)**, app commit [`e779e4b`](https://github.com/biggsjm/mfl-blitz-ios/commit/e779e4b), on `main` and installed/launched on Josh's iPhone.
- **Private owner testing**, not a published App Store/TestFlight release. No production MFL client registration or Week 2 invitation readiness has been confirmed.
- Current tabs: **Scores / Lineup / Transactions / Standings / Board**. Settings is upper-left on Scores; Scores and Lineup share a labeled Week N control.
- Connected mode performs real MFL reads and explicitly reviewed writes. Champion Hall preview is synthetic; preview offers, owners, dates and transactions are not live offers or commitments.

## Shipped workflows

| Area | Current behavior | Important boundary |
| --- | --- | --- |
| Scores | Featured matchup, all league matchups, player-by-player detail, league-derived FLEX, foreground refresh and final-result reconciliation | No background push/Live Activity; projections are pregame, not a live win forecast |
| Lineup | Bench and eligible starter replacements, FLEX rotations, saved drafts, exact review and starter readback | MFL stores starter IDs, not named FLEX placements; tiebreaker saved state cannot be read back |
| Waivers | Available-player search, supported conditional blind-bid queue, round order, budget/minimum checks, full-queue review and partial-save recovery | Native FCFS/classic/non-conditional formats not implemented; MFL remains fallback; processed results are not a full failed-bid audit |
| Trades | Create/Resume, private drafts, Cancel/rollback, blank-save disabled, exact proposal/response review, separate counters | Counter does not close original; acceptance can await MFL processing; uncertain outcomes never trigger blind retries |
| Standings | Official overall/division order, owner names, artwork, anchored info popover | No team roster/schedule drill-through yet; missing owner name is not guessed |
| Board | Native threads, posts/replies, drafts and exact-post readback | Plain-text HTML cleanup, not rich HTML rendering or a separate chat service |
| Storage/network | Device-only Keychain sessions/drafts/markers, bounded reconnect, shared daily public catalog, private memory caches | No persistent private response/offline cache, analytics or application backend |

The current [trade release](trade-inbox-ux.md) also fixes first-presentation response state: tapping Decline or Withdraw must show that action's review, never a default Accept review. Every composer opening receives a new view identity and rollback snapshot so canceled edits cannot reappear from reused sheet state.

## Verification evidence

| Evidence | Result and scope |
| --- | --- |
| Build-16 local app suite, September 6 | **96 test functions / 121 executions**, zero failures, skipped tests or runtime warnings; full app unit suite plus five native trade journeys on iPhone 17 Pro / iOS 27 simulator, Xcode 27 beta |
| Native journeys in that run | `testDecliningPreviewOfferOpensDeclineReviewFirst`, `testEmptyTradeInboxMakesCreatingAndResumingObvious`, `testTradeActionStaysVisibleWithLargeText`, `testTradeDraftPersistsAndRequiresReview`, `testTransactionsReviewsIncomingOfferWithoutAccepting` |
| MFLCore documentation-audit rerun, September 6 | **62 tests / 9 suites passed** in a fresh temporary build directory; no live network writes |
| App-commit GitHub CI | [`e779e4b` CI](https://github.com/biggsjm/mfl-blitz-ios/actions/runs/34046368810) passed both core and iOS jobs, including app build and full app/UI test command |
| Earlier 0.3.3 audit | 62 core tests, 78 app functions and 11 UI journeys; four synthetic managers through two accelerated weeks. Historical benchmark/methodology in [synthetic report](two-week-synthetic-testing.md) |
| Earlier 0.3.5 lineup verification | 92 functions / 117 executions, including five lineup UI journeys; [starter/FLEX contract](lineup-starter-swaps.md) |
| Device evidence | Build 16 installed/launched; earlier authenticated read-only checks confirmed projections, artwork, owner names, catalog reuse and tradable assets. Counts are dated observations, not guarantees about future league data |
| Owner feedback | Josh reported successful lineup submission and visible projections. Full actual Week 1 scoring/processing and cooperating-owner trade validation remain open |

Local build-16 evidence bundle: `Test-MFLBlitz-2026.09.06_11-37-54--0500.xcresult` (development artifact, not committed). The documentation audit's initial core run was blocked by sandbox caches, then an existing build bundle's signing metadata. A fresh `--scratch-path` build passed; those failed build attempts are not counted as tests passed.

Native QA explicitly enters preview and never sends real offers, accepts trades or modifies the league. Two-week model simulations exercise production model/repository code against in-memory data, not two real calendar weeks or human participants. Local build-16 UI coverage is five trade journeys, not a claim that the entire UI suite was rerun locally for that build. Repository CI independently runs core, app build and app/UI jobs; inspect [GitHub Actions](https://github.com/biggsjm/mfl-blitz-ios/actions) for commit-specific results.

## Known gaps and data limits

- **No My Team tab, team roster/detail, fantasy season schedule, or shared Player Detail yet.** The [schedule](schedule-ux.md) and [player](player-detail-ux.md) documents are coordinated proposals. Their final tabs retain Lineup; they do not add a Players tab/global directory.
- Existing waiver search covers available players only. A full-player search is not a committed requirement.
- The week picker still uses `1...18`; future schedule work must use decoded league season bounds and route-scoped data rather than changing the lineup's selected week while browsing.
- Live lineup model `opponent` is a dash and `gameTime` is a placeholder date. Its field named `seasonPoints` is populated from a weekly live score, not a season total. Waiver season points/rostered percentage/trend are zero placeholders (not exposed as real metrics in current waiver UI). Do not reuse them as verified Player Detail data.
- Optional bio fields exist in MFLCore, but their live population and reliable player season-history coverage still need verification. No headshot/news/licensed raw-stat feed is integrated.
- Broad league-format certification, multi-league switching, native FCFS/IR/taxi/commissioner management, rich HTML/links, private offline snapshots, diagnostics export and iPad split-view remain unfinished.
- Accessibility foundations and selected large-text tests exist; a complete manual accessibility/device/OS audit is not recorded.
- API-client registration is unconfirmed. The app sends `MFL Blitz/0.1 (com.biggsjm.MFLBlitz)`; the package's default is a separate sample string. Neither should be treated as proof of production registration.
- GitHub private vulnerability reporting was checked and **disabled** on September 6. Establish a safe private contact/reporting route before wider distribution; never post secrets in an issue.

## Next decision

Complete the [owner Week 1 checklist](week-1-testing.md) and P0 [release gates](roadmap.md) before a Week 2 invitation. Player/team/schedule implementation is the next coordinated product increment, not a substitute for those gates. This documentation update changes no app code, version, installed build, or live league state.
