import Foundation
import Observation
import MFLCore

@MainActor
@Observable
final class TransactionsModel {
    var snapshot = TradeSnapshot()
    var activity: [TransactionActivity] = []
    private(set) var history = TradeHistory()
    var historyError: String?
    var draft: TradeDraft?
    var pending: PendingTradeAction?
    var isLoading = false
    var isLoadingActivity = false
    var isBusy = false
    var readError: String?
    var activityError: String?
    var retryAfter: Date?
    var lastActivityRefresh: Date?
    private var lastActivityAttempt: Date?
    private var lastTradeAttempt: Date?
    @ObservationIgnored private var tradeReadWaiters: [CheckedContinuation<Void, Never>] = []
    private var historyLoaded = false
    var notice: String?
    let workspace: LeagueWorkspace?
    let isDemo: Bool
    private let repository: any LeagueRepository
    private let privateStore: any PrivateStore

    init(repository: any LeagueRepository = DemoLeagueRepository(), workspace: LeagueWorkspace? = nil,
         privateStore: any PrivateStore = KeychainPrivateStore(), isDemo: Bool = false) {
        self.repository = repository; self.workspace = workspace
        self.privateStore = privateStore; self.isDemo = isDemo
        if isDemo { snapshot = SampleData.tradePreview }
        #if DEBUG
        if isDemo, ProcessInfo.processInfo.arguments.contains("--preview-trade-history") {
            try? history.observe(SampleData.trades, ownerID: SampleData.workspace.franchiseID)
            try? history.observe(snapshot, ownerID: SampleData.workspace.franchiseID)
        }
        #endif
        if !isDemo, let workspace {
            do {
                let saved = try privateStore.decode(TradeDraft.self, key: "trade.draft.\(workspace.storageScope)")
                draft = saved?.hasContent == true ? saved : nil
            }
            catch { readError = error.localizedDescription }
            do { try restoreHistory() }
            catch { historyError = "Trade history couldn’t be read. Unlock your phone and refresh." }
        }
    }

    var ownerID: String { workspace?.franchiseID ?? "" }
    var incoming: [TradeOffer] { snapshot.offers.filter { $0.offeredTo == ownerID }.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) } }
    var outgoing: [TradeOffer] { snapshot.offers.filter { $0.offeredBy == ownerID }.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) } }
    var unresolved: [TradeOffer] { snapshot.offers.filter { $0.offeredBy == nil && $0.offeredTo != ownerID } }
    var needsAttentionCount: Int { incoming.filter { !$0.isExpired }.count + unresolved.count + (pending == nil ? 0 : 1) + history.entries.filter { $0.unread && $0.outcome != .pending }.count }
    var canAct: Bool { workspace != nil && snapshot.hasTradableAssets && snapshot.updatedAt != nil && readError == nil && pending == nil && !isBusy && !isLoading }
    var hasConfirmedEmptyInbox: Bool {
        snapshot.updatedAt != nil && snapshot.offers.isEmpty && !isLoading && !isBusy && readError == nil && pending == nil
    }
    func team(_ id: String?) -> TradeTeam? { snapshot.teams.first { $0.id == id } }

    func refreshInbox(ifNeeded: Bool = true) async {
        await refresh(ifNeeded: ifNeeded, inboxOnly: true)
    }

    func refresh(ifNeeded: Bool = false, inboxOnly: Bool = false) async {
        guard workspace != nil, !isBusy else { return }
        // Opening Trades during a badge read must still load the assets needed
        // by the composer. Join the existing read before deciding what is stale.
        while !inboxOnly && isLoading {
            await withCheckedContinuation { tradeReadWaiters.append($0) }
            guard !Task.isCancelled else { return }
        }
        guard !isLoading, !isBusy, !Task.isCancelled else { return }
        guard retryAfter.map({ $0 <= Date() }) ?? true else { return }
        if ifNeeded, (inboxOnly || snapshot.hasTradableAssets), readError == nil, let updated = snapshot.updatedAt, Date().timeIntervalSince(updated) < 60 { return }
        if (inboxOnly || snapshot.hasTradableAssets), let lastTradeAttempt, Date().timeIntervalSince(lastTradeAttempt) < 5 { return }
        lastTradeAttempt = Date()
        isLoading = true
        defer {
            isLoading = false
            let waiters = tradeReadWaiters
            tradeReadWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        do {
            pending = try await repository.pendingTradeAction()
            let fresh = try await (inboxOnly ? repository.loadTradeInbox() : repository.loadTrades())
            try Task.checkCancellation()
            try acceptSnapshot(fresh)
            readError = nil
            retryAfter = nil
        } catch {
            if Task.isCancelled || error is CancellationError { lastTradeAttempt = nil; return }
            if case MFLCoreError.rateLimited(let seconds) = error { retryAfter = Date().addingTimeInterval(seconds ?? 90) }
            readError = "Trades couldn’t be refreshed. Existing offers may be out of date. \(error.localizedDescription)"
        }
    }

    func refreshActivity(ifNeeded: Bool = false) async {
        guard workspace != nil, !isLoadingActivity else { return }
        guard retryAfter.map({ $0 <= Date() }) ?? true else {
            activityError = "MFL is temporarily limiting requests. Your existing activity is kept; retry after the countdown."
            return
        }
        if ifNeeded, activityError == nil, let lastActivityRefresh, Date().timeIntervalSince(lastActivityRefresh) < 60 { return }
        if let lastActivityAttempt, Date().timeIntervalSince(lastActivityAttempt) < 5 { return }
        lastActivityAttempt = Date()
        isLoadingActivity = true
        defer { isLoadingActivity = false }
        do {
            let fresh = try await repository.loadTransactionActivity()
            try Task.checkCancellation()
            activity = fresh; activityError = nil; lastActivityRefresh = Date(); retryAfter = nil
        }
        catch {
            if Task.isCancelled || error is CancellationError { lastActivityAttempt = nil; return }
            if case MFLCoreError.rateLimited(let seconds) = error { retryAfter = Date().addingTimeInterval(seconds ?? 90) }
            activityError = "Activity couldn’t be loaded. \(error.localizedDescription)"
        }
    }

    var closedOffers: [TradeHistoryEntry] {
        history.entries.filter { $0.outcome != .pending }.sorted { $0.changedAt > $1.changedAt }
    }

    func markHistoryRead(_ id: String) {
        var next = history
        guard let index = next.entries.firstIndex(where: { $0.id == id }) else { return }
        next.entries[index].unread = false
        saveHistory(next)
    }

    private func acceptSnapshot(_ fresh: TradeSnapshot, confirmed: TradeCommand? = nil) throws {
        // A locked Keychain is not an empty history. Restore before merging so
        // a later successful write cannot replace records we failed to read.
        do { try restoreHistory() }
        catch {
            historyError = "Trade history couldn’t be read. Unlock your phone and refresh."
            throw error
        }
        var next = history
        try next.observe(fresh, ownerID: ownerID)
        if let confirmed { next.confirm(confirmed) }
        saveHistory(next)
        snapshot = fresh
        // Retain the known sender for unchanged offers in lightweight reads.
        for index in snapshot.offers.indices where snapshot.offers[index].offeredBy == nil {
            snapshot.offers[index].offeredBy = next.entries.first { $0.id == snapshot.offers[index].id }?.offer.offeredBy
        }
    }

    private func restoreHistory() throws {
        guard !historyLoaded, !isDemo, let workspace else { return }
        history = try privateStore.decode(TradeHistory.self, key: "trade.history.\(workspace.storageScope)") ?? TradeHistory()
        historyLoaded = true
    }

    private func saveHistory(_ next: TradeHistory) {
        do {
            if !isDemo, let workspace { try privateStore.encode(next, key: "trade.history.\(workspace.storageScope)") }
            history = next
            historyError = nil
        } catch { historyError = "Trade history couldn’t be saved. Unlock your phone and refresh." }
    }

    func saveDraft(_ value: TradeDraft?) {
        guard !isBusy else { return }
        let value = value?.hasContent == true ? value : nil
        draft = value
        guard !isDemo, let workspace else { return }
        do {
            if let value { try privateStore.encode(value, key: "trade.draft.\(workspace.storageScope)") }
            else { try privateStore.remove("trade.draft.\(workspace.storageScope)") }
        } catch { notice = error.localizedDescription }
    }

    func validationMessage(for draft: TradeDraft) -> String? {
        guard let owner = team(ownerID), let partner = team(draft.partnerID), owner.id != partner.id else { return "Choose a trading partner." }
        guard !draft.giving.isEmpty, !draft.receiving.isEmpty else { return "Select what you send and what you receive." }
        for (codes, team) in [(draft.giving, owner), (draft.receiving, partner)] {
            guard codes.filter({ $0.hasPrefix("BB_") }).count <= 1 else { return "Choose one FAAB amount per team." }
            for code in codes {
                if let amount = MFLTradeAssetCode.blindBidAmount(code) {
                    if amount <= 0 || amount > (team.blindBidBalance ?? -1) { return "Review the available FAAB balance." }
                } else if !team.assets.contains(where: { $0.id == code && $0.kind != .unknown }) {
                    return "A selected asset is no longer available. Review both sides."
                }
            }
        }
        guard draft.expires > Date() else { return "Choose a future expiration." }
        guard draft.comments.count <= 1_000 else { return "Keep your message under 1,000 characters." }
        if draft.countering != nil && !draft.acknowledgesOriginalStaysOpen { return "Acknowledge that the original offer remains open." }
        return nil
    }

    func assets(_ codes: Set<String>, teamID: String) -> [TradeAsset] {
        codes.sorted().map { code in
            if let asset = team(teamID)?.assets.first(where: { $0.id == code }) { return asset }
            if let amount = MFLTradeAssetCode.blindBidAmount(code) {
                return TradeAsset(id: code, name: "\(amount.formatted(.currency(code: "USD"))) blind-bid budget", detail: "FAAB dollars", kind: .budget)
            }
            return TradeAsset(id: code, name: "Unavailable asset: \(code)", detail: "Remove or check MFL", kind: .unknown)
        }.sorted { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) }
    }

    func perform(_ command: TradeCommand) async -> Bool {
        guard canAct else { return false }
        if case .propose(let draft) = command, let error = validationMessage(for: draft) { notice = error; return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let receipt = try await repository.performTrade(command)
            pending = try await repository.pendingTradeAction()
            notice = receipt.message
            if receipt.confirmed, case .propose = command {
                draft = nil
                if !isDemo, let workspace { try privateStore.remove("trade.draft.\(workspace.storageScope)") }
            }
            do {
                if let fresh = receipt.snapshot { try acceptSnapshot(fresh, confirmed: receipt.confirmed ? command : nil) }
                else { try acceptSnapshot(try await repository.loadTrades(), confirmed: receipt.confirmed ? command : nil) }
                readError = nil
            }
            catch { readError = "Trade action checked, but the list couldn’t refresh. Pull to retry." }
            return receipt.confirmed
        } catch {
            notice = error.localizedDescription
            pending = try? await repository.pendingTradeAction()
            readError = "Refresh trades and review the latest offer before trying again."
            return false
        }
    }

    func checkPending() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let command = pending?.command
            let receipt = try await repository.reconcileTradeAction()
            if receipt.confirmed, let pending, case .propose = pending.command {
                draft = nil
                if !isDemo, let workspace { try privateStore.remove("trade.draft.\(workspace.storageScope)") }
            }
            pending = try await repository.pendingTradeAction()
            notice = receipt.message
            if let fresh = receipt.snapshot { try acceptSnapshot(fresh, confirmed: receipt.confirmed ? command : nil) }
            else { try acceptSnapshot(try await repository.loadTrades(), confirmed: receipt.confirmed ? command : nil) }
            readError = nil
        } catch { notice = "The outcome still couldn’t be verified. Check MFL before sending anything again." }
    }

    func resolveAfterManualCheck() async {
        guard !isBusy else { return }
        do {
            try await repository.acknowledgeUnconfirmedTrade()
            pending = nil
            await refresh()
        } catch { notice = error.localizedDescription }
    }
}
