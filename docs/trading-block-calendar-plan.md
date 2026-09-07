# Trading Block, League Calendar and Deadline Reminders

Status: **Implemented, tested, installed and merged in [PR #10](https://github.com/biggsjm/mfl-blitz-ios/pull/10)**, September 7, 2026. Josh approved items 1–3 and added a current-matchup Live Activity. Build 0.6.0 (35) includes his feedback: Lineup-style roster/block promotion/demotion with review/submit, explicit last-player removal, and Settings relocated to My Team. Build 33 launched; build 35's automatic launch was blocked by the phone lock. Full local/current-iOS and GitHub/older-iOS suites pass on the installed source; exact evidence is in [current status](current-status.md). No real league listing, personal calendar event or reminder has been created or removed for automated QA.

## Implementation checkpoint

- [x] Trading Block browse, separate recoverable drafts, publish/edit with fresh membership/asset/ability checks, conflict detection, durable pending marker and exact terms readback; Make offer protects an existing proposal draft.
- [x] Shared typed Calendar JSON/ICS feed, explicit published occurrences, agenda, event details and links to existing workflows. Existing waiver timing uses the same cached source.
- [x] Opt-in per-event/category local reminders, bounded scheduling, reconciliation, permission-denial handling, scoped deep links and user-reviewed single-event Apple Calendar export.
- [x] Live Activity extension and on-device lifecycle: current owner's matchup, actively playing starters, foreground updates, stale-state presentation, user dismissal and disconnect handling.
- [x] Final exact-source regression, signed phone delivery and GitHub merge/documentation completion. Source `3663a37`; merge `e946b1c`; all 107 core tests, 209 app unit functions and 45 native journeys pass. Installation is not live-owner acceptance.
- [ ] Owner Week 1 validation of intended native publication, device reminders, Apple Calendar handoff and real Live Activity behavior.
- [x] Build 35: explicit last-player/full-block removal review, recoverable empty draft, owner/baseline preflight and exact empty readback; requested after Josh found the build-34 restriction.
- [x] Owner-reported acceptance: Josh confirmed September 7 that removing the last trading-block player works on MFL. This closes the specific removal check; fixtures alone were not provider acceptance evidence.
- [ ] Listing new blind-bid dollars remains MFL-only until its undocumented import semantics are verified.
- [ ] Continuous background Live Activity updates need an APNs service; none is connected in this increment. Inferred lineup-review reminders remain deferred until a general league lock-rule interpretation is verified.

See [implementation and test contract](league-extras-implementation.md) for precise behavior and limitations.

## Decisions already made

- Josh will validate Week 1 on his development device.
- TestFlight is on hold until **both iOS 27 and macOS 27 are out of beta**, followed by the existing release gates and Josh's go-ahead. The earlier Week 2 invitation target is no longer a release deadline. This is the owner's distribution preference, not a claim that Apple requires waiting for both operating systems.
- Approved features: Trading Block and League Calendar/deadline reminders, plus the subsequently requested matchup Live Activity. Polls, playoff brackets, remote push, home-screen widgets and commissioner tools stay queued.
- Josh confirmed the build-32 Scores cancellation fix works. That does not independently certify player-card speed or all game-week behavior.

## Implemented navigation

Keep the five main tabs and the six My Team shortcuts unchanged. Extend two existing destinations:

| Entry | Modes | Primary job |
| --- | --- | --- |
| My Team → Trades | Offers / Trading Block | Negotiate an offer or browse what owners are willing to trade |
| My Team → Schedule | Matchups / Calendar | See fantasy opponents or upcoming league events |
| Calendar event → Remind me | Reminder timing | Choose an alert and return to the relevant task when it arrives |

Offers and Matchups remain the default modes. Each mode preserves its scroll position. No additional bottom tab or competing Transactions/Manage roster umbrella. Existing direct season-schedule links still open matchups; the shared calendar is league-wide, not a second per-team download. New subnavigation must adapt at large text without clipping.

Build 34 moves Settings to the top-left of My Team. Scores retains its Week selector at the top-right.

## 1. Trading Block

### League view

- A compact **My trading block** card sits first: available assets, Looking for text, and **Edit block**. If empty, use **Add to trading block** so creation is discoverable without finding a plus icon.
- Other listings show the team logo/name, smaller owner name, available players/picks and a short Looking for line. Do not invent a listing date or sort by recency unless MFL supplies usable timestamps. Otherwise use a stable team-name order.
- Player names open the existing player card. A labeled **Make offer** action opens the current trade composer with the owner and selected requested assets filled in. Nothing is sent automatically; the manager chooses their side and reviews the offer.
- Preserve any existing offer draft. Ask whether to resume it or explicitly replace it before prefilling another proposal.
- An empty block means no published listings, not no tradable players. Failed/stale reads retain known content and offer Retry separately from a confirmed-empty state.

### Editing my block

- Following Josh's build-34 feedback, use the Lineup pattern: **On the block** above **Your roster**, with green up arrows to list players and orange down arrows to remove them from the draft listing. Position badges identify players; supported owned draft picks live in a secondary disclosure. These controls never add/drop players or change starters. The API's Looking for text is limited to **256 characters**; use a restrained counter near the limit.
- One concise publication hint: **Visible to your league.** A block advertises interest; it is not a trade offer and moves no assets.
- **Close** follows the established draft pattern: ask Save draft / Discard / Keep editing only after meaningful changes. Empty/unchanged edits cannot publish. A saved block draft is accessible from My trading block as **Resume draft**, separate from an offer draft.
- A pinned **Review & submit trading block** action opens a cancelable review of the exact assets and Looking for text. **Submit trading block** is the publication action. Blank new drafts and unchanged listings cannot submit. Clearing an existing listing instead offers **Review removal → Remove listing**; the review states that the listing/needs note will clear while every player remains on the roster. Empty removal drafts can be saved and resumed.
- Refresh the current listing, ownership, supported assets and applicable capabilities before publishing. If the listing changed on MFL since editing began, preserve the draft and require review instead of overwriting the other version.
- Store a scoped pending marker before the single write; read the full owner's block back and verify the requested asset set and text. A timeout offers Check status, not an automatic retry. Do not silently remove unknown or unsupported asset codes when editing an existing block.

### Verified API facts and open checks

The official [MFL request reference](https://api.myfantasyleague.com/2026/api_info?STATE=details) documents `tradeBait` export/import. Export with `INCLUDE_DRAFT_PICKS` includes additional asset codes. Import replaces the owner's existing block, accepts player/pick codes and a 256-character needs description. Export documents blind-bid dollars, but import does not explicitly document them: display existing dollar assets if recognized, but do not enable new dollar listings without verification.

The league's unauthenticated export required sign-in on September 7. After approval, Josh supplied authenticated empty and nonempty singleton examples: `tradeBaits.tradeBait` uses `franchise_id`, `willGiveUp`, `inExchangeFor` and `timestamp`. Sanitized tests cover empty/singleton/array handling, assets, escaping, ownership conflicts and uncertain readback. At Josh's subsequent request, build 35 implements explicit full-list removal through empty `WILL_GIVE_UP` and `IN_EXCHANGE_FOR` fields, with fresh absent/empty readback required. MFL's reference documents full replacement but not clearing semantics; Josh subsequently confirmed September 7 that last-player removal works on MFL. That owner observation is separate from synthetic tests and does not certify every league or unsupported asset format. Unknown assets remain visible and prevent silent partial replacement, but can be cleared in an explicit whole-list removal. No real import was sent by automated QA.

## 2. League Calendar

### Agenda-first design

- Default to a chronological agenda: **Today**, **This week**, then later dates. Keep past events behind Earlier events. Start without a month grid; dates and actions matter more than empty calendar cells.
- Show the next relevant event prominently but compactly, with date/time and a clear type. Avoid running second-by-second countdowns and permanent explanatory cards.
- Include MFL-published waiver processing, add/drop window openings/closings, trade deadlines and custom league events. Use event categories for optional filtering only if the list needs it.
- Label events accurately: **Waivers process** is not the same as **Bidding closes**; **Adds open** is not proof a particular player can be added. Preserve those distinctions in alerts too.
- An event opens details with a relevant action: **Manage bids**, **Browse players**, **View trades**, or the supplied event details. Actions navigate to existing workflows; they never submit a bid, lineup or trade.
- Use local display time and expose the source/time-zone context under an information button when useful. A date with unknown time stays date-only; an uncertain recurrence does not become a precise deadline.
- Kickoff-based **Review lineup** prompts are a separately labeled source derived from the verified NFL schedule and supported league rules. Do not claim every league locks at the first kickoff or confuse acquisition locks with lineup locks. If that interpretation is unverified, omit the inferred lineup-deadline reminder rather than guessing.

### Calendar data boundary

MFL documents owner-only `calendar` and `ics` exports. Writing a league event uses commissioner-only `calendarEvent`; **creating/editing league events is outside this phase**. [MFL reference](https://api.myfantasyleague.com/2026/api_info?STATE=details).

The previous raw calendar download for waiver timing is replaced with one shared typed calendar snapshot used by Waivers, Calendar and reminders. There is no additional independent polling stream.

Josh supplied matching JSON and ICS exports after approval. JSON has epoch dates and `happens` counts; ICS provides the expanded occurrences, including November's DST shift. Its clock values lack `Z`/`TZID`, so Blitz accepts those UTC values only after every JSON event independently matches the same ICS UID/date. Additional occurrences must map unambiguously to their series and match the published count. Regenerated ICS child UIDs are not stable reminder IDs. Unknown recurrence/all-day/time-zone/exclusion formats remain partial rather than guessed. No full-calendar subscription is included.

## 3. Opt-in deadline reminders and Apple Calendar

### Reminders

- Put an accessible bell/Remind me control on dated events. First enablement presents a small timing sheet, then the system permission request in context—not at launch. [Apple permission guidance](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).
- Choices: **15 minutes**, **1 hour** (default), or **1 day** before. An event-specific override and Off remain easy to find.
- Optional category preferences let a manager opt into future published waiver events and trade deadlines. All categories start off; no alert is inferred from merely opening Calendar. Inferred lineup-review prompts remain deferred.
- Use on-device local notifications, not a push server. Deep links open the relevant league/event and workflow, with authentication/scope checks and preserved drafts. A reminder must not silently switch or overwrite an edited lineup week.
- Schedule a bounded rolling window: **next 14 days, at most 32 pending reminders**, with stable scoped identifiers and one notification per event occurrence. Refresh/reconcile when the app becomes active or the user refreshes/enables reminders; do not schedule an endless guessed weekly rule. The budget is an app policy, not a claim about Apple's maximum.
- Cancel/replace pending requests when a successful refresh confirms events were moved/removed; clear this app's scoped reminders on disconnect/account change. An ordinary failed refresh is not proof that all events were deleted.
- Never create a late catch-up notification for an already-passed trigger. Explain unavailable lead times inside the timing sheet. Check current system authorization and offer Open Settings after denial without repeatedly prompting.
- Keep alert copy short and nonsensitive. Do not put bid amounts, trade terms, credentials or unnecessary player information on the lock screen. No critical/time-sensitive bypass or badge clutter in the first version.

Local notifications can be delivered while Blitz is closed, but the app cannot promise it learned about later MFL changes while closed. Focus, notification settings and system delivery behavior also apply. Use a small information note: **Reminders follow the last updated league calendar.** Show refresh status in reminder settings; do not call a reminder guaranteed or use cached events as permission to make a roster change. [Apple local-notification lifecycle](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).

### Add to Apple Calendar

Offer **Add to Calendar** for a selected, verified dated event using Apple's event editor. The user reviews and saves it there; Blitz does not request full access to read their calendars. This is a one-time copy, not automatic two-way synchronization, and the app cannot reliably inspect the user's saved edits or guarantee duplicate detection without broader access. Do not embed an MFL cookie/API key in a subscription URL. [Apple EventKitUI access guidance](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui).

## Performance, security and implementation boundaries

- New feeds are optional and on demand. They must not delay sign-in, Scores, Lineup or primary player cards.
- Ordinary TTLs: Trading Block 5 minutes, Calendar 15 minutes. Reuse one in-flight read, the daily catalog/team metadata and existing 1.25-second request spacing/host cooldowns. User-requested refresh and publication preflight/readback remain explicitly fresh.
- Replace the existing forced calendar fetch in ordinary waiver display with the shared reader. Calendar information remains descriptive; MFL and fresh existing preflight enforce actual waiver eligibility.
- Persist bounded protected display snapshots and reminder preferences/identifiers only as needed, bound to season/league/franchise. Preserve original fetch dates; cancelled or failed reads must not overwrite valid snapshots with empty data. Fresh event verification is required before adding/changing reminders from stale display data.
- Protect listing/offer draft independence, active week, selected player and navigation Back behavior. Keep writes behind existing fresh-auth and uncertainty protections.
- Privacy/storage/notification disclosures, deep-link handling, API docs, fixtures and the owner checklist are updated with the implementation. Installation and owner acceptance are recorded separately in [current status](current-status.md).

## Delivery sequence after approval

| Stage | Deliverable | Acceptance gate |
| --- | --- | --- |
| 0 — Contracts and layout | Authenticated read-only wire validation, sanitized fixtures, reviewable native layout | Confirm listing round trip/clear behavior and precise calendar occurrences; unresolved cases get explicit read-only limits |
| 1 — Trading Block | Browse, staged edit/publish/remove, draft recovery, Make offer handoff | Exact MFL readback, conflict/timeout handling, no lost offer draft or unintended roster change; last-player removal owner-confirmed September 7, broader cases remain open |
| 2 — Calendar | Shared typed feed and agenda with correct event/action labels | Matches MFL dates/types, time-zone/DST correctness, cancellation and offline recovery |
| 3 — Reminders | Opt-in local alerts, timing preferences, deep links, selected-event Apple Calendar handoff | No duplicate/wrong-league/past reminders; changed-event reconciliation and permission-denial paths work |
| 4 — Owner trial | Signed development builds and updated documentation | Josh validates intended live actions on his dev device; TestFlight stays on hold |

Each implemented stage gets core/model/native regression coverage before phone delivery. Use synthetic owners and two accelerated weeks for changed blocks, traded-away assets/picks, another device's edits, failed imports, changed/removed deadlines, DST/travel, off-season/empty calendars, disabled notifications, relaunch, sign-out and preserved lineup/trade drafts. Validate VoiceOver, large text, light/dark appearance and the first action/Back path. Real block publication or calendar insertion requires the owner's intended action; automated QA is offline and never creates real league offers or events.

## Approved defaults and added Live Activity

Approved defaults: **Trading Block inside Trades; Calendar inside Schedule; agenda first; players and verified draft picks; one-hour opt-in reminders; local notifications without a backend; single-event Add to Calendar; staged dev-device delivery.** Calendar creation, continuous Calendar subscriptions/sync, new trade-value advice, polls, brackets and remote push remain outside this increment.

The added Live Activity shows the current owner's matchup while at least one identified starter has a live MFL clock. It reuses foreground score reads, excludes bench-only games and historical weeks, and marks scores stale after two minutes. Settings exposes an off switch and the foreground-update limitation. It cannot poll MFL from its extension; continuous updates while Blitz is suspended require a separately authorized APNs service. No background-score guarantee, push-token registration or credentials-on-a-server is introduced. [Apple ActivityKit lifecycle](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).
