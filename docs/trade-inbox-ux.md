# Trade inbox

Implemented at [`e779e4b`](https://github.com/biggsjm/mfl-blitz-ios/commit/e779e4b), installed on the owner's phone September 6, 2026. See [current status](current-status.md), [remaining plan](roadmap.md), and [owner verification](week-1-testing.md). Build 22 exposes this workflow directly at My Team → Trades, retaining the trade badge and draft/review protections. Earlier Transactions-tab and Transactions-hub routes are historical; see [direct-tool navigation](my-team-shortcuts.md).

Native trading is the primary path. A full-width **Create trade** button sits directly below the transaction selector and remains visible while the inbox scrolls. A saved draft changes that same action to **Resume trade**; there is no duplicate draft card.

- A successfully loaded, empty inbox shows one **No active trades** state. Loading, failed reads, unverified actions, and unresolved offers never masquerade as an empty inbox.
- Received and Sent sections appear only when they contain offers. Offer rows retain the trading partner, both sides of the deal, and expiration.
- **Trade options** contains Refresh offers, Open on MFL, and (when relevant) Discard draft. Discard uses a centered confirmation with an explicit Cancel action and does not change sent offers.
- MFL recovery links remain visible beside errors and unverified actions. Important safeguards are not hidden in the menu.
- The last-checked time is secondary text, not an external-link card. League constraints appear in the final review where the owner decides whether to send or accept.

Trade API preflight and readback safeguards remain unchanged. New offers remain gated on a successful inbox read; a saved draft can still be resumed after a read failure, but sending remains blocked until data and verification are safe. No action is automatically sent from the inbox.

## Composer and response reviews

Build **0.6.0 (33)** adds **Offers / Trading Block**, defaulting to Offers and retaining the existing inbox/composer behavior. Trading Block puts the owner's Add/Edit/Resume first, followed by league listings with secondary owner names, asset research links and Make offer. The latter stages a draft, never sends one. If a trade draft already exists, Resume or explicit Replace is required. Block editing has its own protected draft, Close/save/discard flow and first-action publication with fresh owner/asset/baseline checks and readback. Unconfirmed publication exposes Check status and prevents another POST. Build 33 kept entire-block removal and cash listings on MFL; build 35 adds reviewed removal as described below, while new cash listings remain MFL-only. See [implementation and remaining limits](league-extras-implementation.md).

Cancel is at the leading edge; Save & close is at the trailing edge and disabled for a blank/whitespace-only draft. Choosing a partner, assets, or entering a message enables saving even if the offer is not ready to send. Merely opening a blank composer does not create a resumable draft, and blank drafts from older builds are ignored on restore.

Changing only expiration does not make a blank draft meaningful. Dirty editors cannot be swiped away without resolving edits; Cancel/Discard changes restores the pre-opening snapshot rather than deleting an already saved draft or sent offer.

Meaningful edits retain crash-safe autosaving. Cancel restores the saved draft from before the composer opened; edited drafts require a centered Discard changes confirmation. An unchanged blank composer cancels immediately. Counteroffers are staged separately so canceling a newly opened counteroffer does not leave an unwanted draft.

Every editor opening uses a unique, explicit SwiftUI view identity and an immutable rollback snapshot. Click-through tracing found that presentation reuse could retain a previous editor's unsaved on-screen state even after the saved data had been restored correctly. Fresh view identity prevents that stale state from reappearing; closing also stops late autosave callbacks. Changing partners clears receiving selections in the same update.

Click-through QA uncovered a first-presentation bug: separate response-action and sheet-visibility state could show the default Accept review after tapping Withdraw or Decline. The response sheet now receives the selected action as one identifiable payload. The API role checks remain in place; UI tests also assert the exact first-tap Decline/Withdraw titles and confirmation labels, then cancel without performing an action.

## Regression coverage

Build 34 responds to owner feedback with a Lineup-style block editor: On the block / Your roster, green up/orange down controls, optional needs text, secondary owned picks and a pinned Review & submit action. The cancelable review lists exact terms before the final send. Empty/unchanged drafts cannot submit; roster membership and starter assignments never change. Native tests must cover promote → demote → promote, saved-draft recovery, Cancel review, explicit offline submit and unchanged readback. The Offers page's Create action remains directly below the new mode selector; geometry tests must account for that selector instead of assuming the action touches the navigation bar.

Build 35 supersedes the empty-existing-block restriction: demoting the last player from a published listing offers **Review removal → Remove listing**. The short review distinguishes removing a league-visible listing/needs note from dropping a player. Empty removal drafts can be saved/resumed; Cancel retains them. A blank new draft remains disabled. Native QA continues the first-edit journey through publish → remove last player → save/resume → cancel removal → confirm removal → disabled blank new draft, using only the offline repository.

The native test helper enters Trades directly through My Team. UI validation includes large-text access to the new entry, then the existing Create/Resume, draft and response journeys. See [current status](current-status.md) for candidate-specific results; the build-16 counts below remain historical.

`TradeInboxPresentationTests` checks confirmed-empty states, loading/errors, pending verification, unresolved offers, and draft changes that must not alter existing offers. Existing trade safety and transaction refresh suites cover ownership, preflight, authoritative readback, duplicate prevention, cancellation, caching, and cooldowns.

Native UI tests cover the full-width action and overflow menu, creating/resuming/discarding a draft, populated offer review, draft asset persistence, and scrolling with accessibility-size text. The `--preview-empty-trades` debug argument affects only the offline preview fixture; signed-in leagues never use it. UI journeys stop before sending or accepting any offer.

September 6 final build-16 verification completed the full app unit suite plus five native trade journeys: 96 test functions (121 executions including parameterized cases), with no failures or runtime warnings. The existing two-week synthetic simulation also passed as part of the unit suite. Screenshots cover dark/light appearance across the UI passes, accessibility-size text, empty and populated inboxes, the options menu, blank-draft controls, correct Accept/Decline/Withdraw reviews, and canceling/confirming draft discard. Canceling edits and resuming must restore both the original partner and every selected asset. All QA used preview/in-memory data; no live offers or responses were submitted.
