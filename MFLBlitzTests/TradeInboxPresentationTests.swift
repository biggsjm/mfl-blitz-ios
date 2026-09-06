import Foundation
import Testing
@testable import MFLBlitz

@MainActor
struct TradeInboxPresentationTests {
    @Test("Each composer session retains an independent rollback snapshot")
    func editSessionSnapshot() {
        let model = TransactionsModel(workspace: SampleData.workspace, privateStore: MemoryPrivateStore())
        let original = TradeDraft(partnerID: "0008", giving: ["12620"], receiving: ["demo-wr"])
        model.saveDraft(original)
        let session = TradeComposerSession(savedDraft: model.draft)
        var edited = session.initial
        edited.partnerID = "0002"
        edited.receiving = []
        model.saveDraft(edited)
        #expect(session.savedDraft == original && session.initial == original)
        model.saveDraft(session.savedDraft)
        #expect(model.draft == original)
        let resumed = TradeComposerSession(savedDraft: model.draft)
        #expect(resumed.id != session.id && resumed.initial == original)
        let counter = TradeComposerSession(savedDraft: nil, counteroffer: original)
        #expect(counter.initial == original && counter.savedDraft == nil)
    }

    @Test("Blank and whitespace-only trades never become resumable drafts")
    func blankDrafts() throws {
        let store = MemoryPrivateStore()
        let model = TransactionsModel(workspace: SampleData.workspace, privateStore: store)
        var blank = TradeDraft()
        #expect(!blank.hasContent)
        blank.comments = " \n "
        #expect(!blank.hasContent)
        model.saveDraft(blank)
        #expect(model.draft == nil)
        #expect(TransactionsModel(workspace: SampleData.workspace, privateStore: store).draft == nil)
        // Older builds saved a draft as soon as the composer opened.
        try store.encode(blank, key: "trade.draft.\(SampleData.workspace.storageScope)")
        #expect(TransactionsModel(workspace: SampleData.workspace, privateStore: store).draft == nil)
        for draft in [TradeDraft(partnerID: "0008"), TradeDraft(giving: ["12620"]),
                      TradeDraft(receiving: ["demo-wr"]), TradeDraft(comments: "Let's talk")] {
            #expect(draft.hasContent)
            model.saveDraft(draft)
            #expect(model.draft == draft)
        }
    }

    @Test("No active trades appears only for a confirmed empty inbox")
    func emptyInbox() {
        let model = TransactionsModel(workspace: SampleData.workspace, privateStore: MemoryPrivateStore())
        #expect(!model.hasConfirmedEmptyInbox)
        model.snapshot = SampleData.trades
        #expect(!model.hasConfirmedEmptyInbox)
        model.snapshot.offers = []
        #expect(model.hasConfirmedEmptyInbox)
        #expect(model.canAct)
        model.isLoading = true
        #expect(!model.hasConfirmedEmptyInbox)
        #expect(!model.canAct)
        model.isLoading = false
        model.isBusy = true
        #expect(!model.hasConfirmedEmptyInbox)
        model.isBusy = false
        model.readError = "Could not load offers"
        #expect(!model.hasConfirmedEmptyInbox)
        #expect(!model.canAct)
        model.readError = nil
        model.pending = PendingTradeAction(command: .propose(TradeDraft()), existingIDs: [])
        #expect(!model.hasConfirmedEmptyInbox)
        #expect(!model.canAct)
        model.pending = nil
        var unresolved = SampleData.trades.offers[0]
        unresolved.offeredBy = nil
        unresolved.offeredTo = "unverified"
        model.snapshot.offers = [unresolved]
        #expect(model.incoming.isEmpty && model.outgoing.isEmpty && !model.unresolved.isEmpty)
        #expect(!model.hasConfirmedEmptyInbox)
    }

    @Test("Resuming and discarding a private draft do not change pending offers")
    func draftAndOffers() {
        let model = TransactionsModel(workspace: SampleData.workspace, privateStore: MemoryPrivateStore())
        model.snapshot = SampleData.trades
        let offers = model.snapshot.offers
        model.saveDraft(TradeDraft(partnerID: "0008"))
        #expect(model.draft?.partnerID == "0008")
        #expect(model.snapshot.offers == offers)
        model.saveDraft(nil)
        #expect(model.draft == nil && model.snapshot.offers == offers)
        #expect(!model.hasConfirmedEmptyInbox)
    }
}
