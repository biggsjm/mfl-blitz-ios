# Roadmap

## 0.1 — Native product prototype

- [x] Scores, lineup, conditional FAAB, standings, and board information architecture
- [x] Interactive Champion Hall preview
- [x] iPhone/iPad adaptive SwiftUI shell
- [x] Dynamic Type, VoiceOver summaries, non-color status, Reduce Motion
- [x] Original app icon and semantic design tokens
- [x] Dependency-free MFL transport package and fixture tests
- [x] Secure login/session architecture
- [x] Review-confirmed lineup import with exact saved-starter verification
- [ ] Verify every mutation against a disposable MFL league
- [ ] Register the production API User-Agent with MFL

## 0.2 — Read-only TestFlight

- Live league picker and multi-league switching
- Server-host rediscovery and session-expiry UI
- Cached cold start with explicit stale state
- Live/current and final score state reconciliation
- Rule-driven lineup rendering across the test matrix
- Official/dynamic standings columns
- Message HTML sanitization and link handling
- iPad split-view details
- Diagnostics export with privacy redaction

## 0.3 — Verified writes

- Validate lineup import, lock behavior, write-only tiebreakers, and receipts across the configuration matrix
- Conditional and non-conditional BBID, waiver-priority, and FCFS workflows
- Draft-preserved local claim forms; no automatic retry
- Board new-thread/reply verification
- IR, taxi, tiebreaker, and commissioner-on-behalf support where capabilities allow
- Accessibility audit with VoiceOver, Voice Control, Switch Control, contrast, and XXL text

## 0.4 — Game-day Apple features

- WidgetKit score and lineup-lock widgets
- Live Activity for the user's matchup, updated only when source data changes
- App Shortcuts: “Show my score,” “Check lineup,” “Open waivers”
- Spotlight indexing for leagues, franchises, and board threads
- Contextual notification opt-in for lock reminders, waiver results, mentions, and replies

MFL has no documented webhook or third-party APNs contract, so background freshness needs a separately reviewed architecture and likely written MFL coordination.

## Configuration test matrix

Before public write access, fixtures and disposable test leagues should cover:

- redraft, keeper, and dynasty;
- standard offense, superflex, and IDP;
- fixed slots and flexible min–max positions;
- BBID only, conditional BBID, BBID + FCFS, classic priority, and no waivers;
- partial lineups, locked players, backup/tiebreaker players;
- IR and taxi squads;
- salary/contracts and contract-years variants;
- duplicate-player leagues;
- best ball, total points, median/all-play, doubleheaders, byes, and playoffs;
- 8-, 12-, 16-, 32-, and 48-team leagues;
- owner, commissioner-with-team, and commissioner-without-team sessions;
- HTTP 200 body errors, 429, timeout, cross-host redirect, malformed singleton/array payloads, and expired sessions.
