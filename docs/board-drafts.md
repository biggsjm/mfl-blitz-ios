# Board drafts

Implemented in **0.4.1 (18)**, September 6, 2026. [Current status](current-status.md) records verification; [roadmap](roadmap.md) retains live-testing and release gates.

## Close and resume

- New thread and Reply composers use **Close**, not Save & close.
- Empty or whitespace-only content closes without a prompt or an empty draft.
- With content, a centered **Save draft?** alert offers **Save draft**, **Discard draft**, and **Keep editing**. The hint is “Continue later from Drafts on Board.”
- **Board → Drafts** is the visible entry for every saved new thread or reply. A thread with an unfinished reply also shows **Resume reply**. Existing New thread/Reply entry points continue to restore their corresponding draft.
- Swiping away a nonempty composer is disabled so it cannot bypass the decision; Close remains available. Posting/busy states prevent dismissal during a write.
- Saving/closing a draft sends no MFL post. Only the explicit Post action sends the message through the existing verification workflow.

## Data and recovery

There is one new-thread draft and one reply draft per thread, scoped to season/league/franchise. Blank legacy entries do not appear in Drafts. Subject-only new threads are meaningful drafts even though Post still requires a body.

Meaningful edits remain autosaved to the existing device-only Keychain for interruption recovery. Closing deliberately asks whether to retain or discard them. Save/discard confirms the storage write before closing; failures keep text and the composer available for retry. Other lineup/waiver/message drafts are preserved.

Discard removes only that draft, never an MFL post or an unconfirmed-post marker. Confirmed posting removes the matching draft. Session guards and a completed-editor guard prevent late field changes from recreating discarded drafts or writing into another team's scope. Unconfirmed outcomes still block duplicate sends until resolved.

## Verification and remaining checks

Model coverage includes blank filtering, independent new-thread/reply restoration, team isolation, selective discard, storage failures and post cleanup. Native synthetic journeys cover immediate empty close, Keep editing, Save draft, visible resume, reply resume and discard/reopen without resurrecting text.

Actual intended posts/replies, interrupted-write reconciliation and complete accessibility/device validation remain in the [owner checklist](week-1-testing.md). No automated QA sends a live league message. Trade drafts retain their separate Cancel/Save & close interaction; this update is scoped to Board.
