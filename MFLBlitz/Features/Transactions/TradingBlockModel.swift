import Foundation
import Observation
import MFLCore

@MainActor @Observable
final class TradingBlockModel {
    let feed: OptionalLeagueFeed<TradingBlockSnapshot>
    let workspace: LeagueWorkspace
    var draft: TradingBlockDraft?
    private(set) var pending: PendingTradingBlock?
    private(set) var isBusy = false
    var notice: String?
    private let repository: any LeagueRepository
    private let store: ProtectedFeedStore
    private var invalidated = false
    private var restored = false

    init(repository: any LeagueRepository, workspace: LeagueWorkspace, store: ProtectedFeedStore) {
        self.repository = repository; self.workspace = workspace; self.store = store
        feed = OptionalLeagueFeed(scope: workspace.storageScope, key: "block.snapshot", ttl: 300, store: store) {
            try await repository.loadTradingBlock(refresh: $0)
        }
    }
    var listing: MFLTradingBlockListing? { feed.snapshot?.listing(for: workspace.franchiseID) }
    var owner: TradeTeam? { feed.snapshot?.teams.first { $0.id == workspace.franchiseID } }
    var canEdit: Bool { feed.snapshot != nil && !isBusy && pending == nil && !feed.isLoading && feed.errorMessage == nil }
    var initialDraft: TradingBlockDraft {
        draft ?? TradingBlockDraft(codes: listing?.codes ?? [], lookingFor: listing?.lookingFor ?? "", baseline: listing)
    }

    func refresh(force: Bool = false) async {
        guard !invalidated, !isBusy else { return }
        if !restored {
            restored = true
            let saved = try? await store.load(TradingBlockDraft.self, key: "block.draft.\(workspace.storageScope)")
            guard !invalidated else { return }
            draft = saved?.hasContent == true ? saved : nil
        }
        do { pending = try await repository.pendingTradingBlock() }
        catch { notice = error.localizedDescription; return }
        await feed.refresh(force: force)
    }

    func saveDraft(_ value: TradingBlockDraft?) async -> Bool {
        guard !invalidated, !isBusy else { return false }
        do {
            if let value, value.hasContent { try await store.save(value, key: "block.draft.\(workspace.storageScope)") }
            else { try await store.remove("block.draft.\(workspace.storageScope)") }
            guard !invalidated else { return false }
            draft = value?.hasContent == true ? value : nil
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    func publish(_ value: TradingBlockDraft) async -> Bool {
        guard canEdit, value.canPublish else { return false }
        guard await saveDraft(value) else { return false }
        isBusy = true
        defer { isBusy = false }
        do { return await accept(try await repository.publishTradingBlock(value)) }
        catch {
            pending = try? await repository.pendingTradingBlock()
            notice = error.localizedDescription
            return false
        }
    }

    func checkStatus() async {
        guard !isBusy, !invalidated else { return }
        isBusy = true
        defer { isBusy = false }
        do { _ = await accept(try await repository.reconcileTradingBlock()) }
        catch { notice = "Your publication is still unconfirmed. Check MFL before changing the block again." }
    }

    private func accept(_ receipt: TradingBlockReceipt) async -> Bool {
        guard !invalidated else { return false }
        pending = try? await repository.pendingTradingBlock()
        if let snapshot = receipt.snapshot { await feed.accept(snapshot) }
        if receipt.confirmed {
            do { try await store.remove("block.draft.\(workspace.storageScope)"); draft = nil }
            catch { notice = "Saved. The draft couldn’t be cleared yet."; return true }
        }
        notice = receipt.confirmed ? (receipt.removed ? "Trading block removed." : "Trading block published.")
            : "Change isn’t confirmed yet. Check status before trying again."
        return receipt.confirmed
    }

    func invalidate() { invalidated = true; feed.invalidate() }
    func disconnect() async { invalidate(); await feed.finishInvalidation() }
}
