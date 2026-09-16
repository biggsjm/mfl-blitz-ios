import Foundation
import Testing
@testable import MFLBlitz

struct TradeHistoryTests {
    @Test("History survives a locked initial read and is merged after unlocking")
    @MainActor func lockedHistory() async throws {
        let store = TradeHistoryReadStore()
        var previous = TradeHistory()
        try previous.observe(SampleData.trades, ownerID: SampleData.workspace.franchiseID, now: .distantPast)
        let key = "trade.history.\(SampleData.workspace.storageScope)"
        try store.encode(previous, key: key)
        store.setRejectReads(true)
        let model = TransactionsModel(repository: ReliabilityRepository(), workspace: SampleData.workspace, privateStore: store)
        #expect(model.historyError != nil)
        store.setRejectReads(false)
        await model.refresh()
        #expect(model.history.entries.allSatisfy { $0.firstSeen == .distantPast })
        #expect(model.history.entries.count == previous.entries.count)
        #expect(model.historyError == nil)
        #expect(try store.decode(TradeHistory.self, key: key) == model.history)
    }

    @Test("Unreadable saved history is not silently overwritten by a fresh inbox")
    @MainActor func invalidStoredHistory() async throws {
        let store = MemoryPrivateStore()
        let key = "trade.history.\(SampleData.workspace.storageScope)"
        let retained = Data("unreadable fixture".utf8)
        store.write(retained, key: key)
        let model = TransactionsModel(repository: ReliabilityRepository(), workspace: SampleData.workspace, privateStore: store)
        await model.refresh()
        #expect(store.read(key) == retained)
        #expect(model.historyError != nil)
        #expect(!model.canAct)
    }

    @Test("Missing offers close without inventing a rejection; unread state survives relaunch")
    func closedAndDurable() throws {
        var history = TradeHistory()
        let first = SampleData.trades
        try history.observe(first, ownerID: SampleData.workspace.franchiseID)
        let id = try #require(first.offers.first?.id)
        try history.observe(TradeSnapshot(updatedAt: Date()), ownerID: SampleData.workspace.franchiseID)
        let saved = try JSONDecoder().decode(TradeHistory.self, from: JSONEncoder().encode(history))
        #expect(saved.entries.first { $0.id == id }?.outcome == .closed)
        #expect(saved.entries.first { $0.id == id }?.unread == true)
        let date = saved.entries.first { $0.id == id }?.changedAt
        try history.observe(TradeSnapshot(updatedAt: Date()), ownerID: SampleData.workspace.franchiseID)
        #expect(history.entries.first { $0.id == id }?.changedAt == date)
    }

    @Test("Unverified or duplicate snapshots cannot close retained offers")
    func incompleteRead() throws {
        var history = TradeHistory()
        try history.observe(SampleData.trades, ownerID: SampleData.workspace.franchiseID)
        let baseline = history
        #expect(throws: (any Error).self) { try history.observe(TradeSnapshot(), ownerID: "0001") }
        var duplicate = SampleData.trades
        duplicate.offers.append(try #require(duplicate.offers.first))
        #expect(throws: (any Error).self) { try history.observe(duplicate, ownerID: "0001") }
        #expect(history == baseline)
    }

    @Test("Confirmed local responses are distinguished from disappearance")
    func confirmedResponse() throws {
        var history = TradeHistory()
        try history.observe(SampleData.trades, ownerID: SampleData.workspace.franchiseID)
        let offer = try #require(SampleData.trades.offers.first)
        try history.observe(TradeSnapshot(updatedAt: Date()), ownerID: SampleData.workspace.franchiseID)
        history.confirm(.respond(offer, .reject, comments: ""))
        #expect(history.entries.first { $0.id == offer.id }?.outcome == .declined)
        #expect(history.entries.first { $0.id == offer.id }?.unread == false)
    }

    @Test("Lightweight badge reads skip assets; trade submission still uses fresh preflight and readback")
    @MainActor func inboxBudget() async throws {
        let transport = MutationFixtureTransport()
        await transport.seedTrade()
        let store = MemoryPrivateStore()
        try store.encode(SavedSession(cookie: "synthetic-cookie", season: 2026, leagueID: "41333", franchiseID: "0001"), key: "session")
        let repository = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero)
        let workspace = try #require(try await repository.restoreSession())
        let model = TransactionsModel(repository: repository, workspace: workspace, privateStore: store)
        await model.refreshInbox()
        await model.refreshInbox()
        #expect(await transport.requestCounts["pendingTrades"] == 1)
        #expect(await transport.requestCounts["assets"] == nil)
        #expect(!model.canAct)
        await model.refresh(ifNeeded: true)
        #expect(model.canAct)
        let offer = try #require(model.snapshot.offers.first)
        #expect(await model.perform(.respond(offer, .reject, comments: "")))
        #expect(await transport.requestCounts["assets"] == 3)
        #expect(await transport.requestCounts["pendingTrades"] == 4)
        let restored = TransactionsModel(repository: repository, workspace: workspace, privateStore: store)
        #expect(restored.closedOffers.first?.outcome == .declined)
        #expect(restored.closedOffers.first?.offer.id == offer.id)
        #expect(!restored.canAct)
    }
}

private final class TradeHistoryReadStore: PrivateStore, @unchecked Sendable {
    private let backing = MemoryPrivateStore()
    private let lock = NSLock()
    private var rejectsReads = false
    func setRejectReads(_ value: Bool) { lock.withLock { rejectsReads = value } }
    func read(_ key: String) throws -> Data? {
        if lock.withLock({ rejectsReads }), key.hasPrefix("trade.history.") { throw StoreError.unavailable }
        return backing.read(key)
    }
    func write(_ data: Data, key: String) throws { backing.write(data, key: key) }
    func remove(_ key: String) throws { backing.remove(key) }
}
