import Foundation
import Observation
import MFLCore

@MainActor
@Observable
final class TransactionsModel {
    var snapshot = TradeSnapshot()
    var activity: [TransactionActivity] = []
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
    var notice: String?
    let workspace: LeagueWorkspace?
    let isDemo: Bool
    private let repository: any LeagueRepository
    private let privateStore: any PrivateStore

    init(repository: any LeagueRepository = DemoLeagueRepository(), workspace: LeagueWorkspace? = nil,
         privateStore: any PrivateStore = KeychainPrivateStore(), isDemo: Bool = false) {
        self.repository = repository; self.workspace = workspace
        self.privateStore = privateStore; self.isDemo = isDemo
        if isDemo { snapshot = SampleData.trades }
        if !isDemo, let workspace {
            do { draft = try privateStore.decode(TradeDraft.self, key: "trade.draft.\(workspace.storageScope)") }
            catch { readError = error.localizedDescription }
        }
    }

    var ownerID: String { workspace?.franchiseID ?? "" }
    var incoming: [TradeOffer] { snapshot.offers.filter { $0.offeredTo == ownerID }.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) } }
    var outgoing: [TradeOffer] { snapshot.offers.filter { $0.offeredBy == ownerID }.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) } }
    var unresolved: [TradeOffer] { snapshot.offers.filter { $0.offeredBy == nil && $0.offeredTo != ownerID } }
    var needsAttentionCount: Int { incoming.filter { !$0.isExpired }.count + unresolved.count + (pending == nil ? 0 : 1) }
    var canAct: Bool { workspace != nil && snapshot.updatedAt != nil && readError == nil && pending == nil && !isBusy && !isLoading }
    func team(_ id: String?) -> TradeTeam? { snapshot.teams.first { $0.id == id } }

    func refresh(ifNeeded: Bool = false) async {
        guard workspace != nil, !isLoading, !isBusy else { return }
        guard retryAfter.map({ $0 <= Date() }) ?? true else { return }
        if ifNeeded, readError == nil, let updated = snapshot.updatedAt, Date().timeIntervalSince(updated) < 60 { return }
        if let lastTradeAttempt, Date().timeIntervalSince(lastTradeAttempt) < 5 { return }
        lastTradeAttempt = Date()
        isLoading = true
        defer { isLoading = false }
        do {
            pending = try await repository.pendingTradeAction()
            let fresh = try await repository.loadTrades()
            try Task.checkCancellation()
            snapshot = fresh
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

    func saveDraft(_ value: TradeDraft?) {
        guard !isBusy else { return }
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
            do { snapshot = try await repository.loadTrades(); readError = nil }
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
            let receipt = try await repository.reconcileTradeAction()
            if receipt.confirmed, let pending, case .propose = pending.command {
                draft = nil
                if !isDemo, let workspace { try privateStore.remove("trade.draft.\(workspace.storageScope)") }
            }
            pending = try await repository.pendingTradeAction()
            notice = receipt.message
            snapshot = try await repository.loadTrades()
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
