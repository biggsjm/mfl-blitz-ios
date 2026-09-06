import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

struct TradeSafetyTests {
    @Test("A trade response reuses authoritative readback instead of downloading the inbox twice")
    @MainActor func responseRequestBudget() async throws {
        let transport = MutationFixtureTransport()
        await transport.seedTrade()
        let repository = try await connected(transport)
        let workspace = try await repository.loadWorkspace()
        let model = TransactionsModel(repository: repository, workspace: workspace, privateStore: MemoryPrivateStore())
        await model.refresh()
        let offer = try #require(model.snapshot.offers.first)
        #expect(await model.perform(.respond(offer, .accept, comments: "")))
        #expect(model.snapshot.offers.isEmpty && model.readError == nil)
        #expect(await transport.imports == ["tradeResponse"])
        // Initial inbox, fresh preflight, authoritative readback. No fourth read.
        #expect(await transport.requestCounts["pendingTrades"] == 3)
        #expect(await transport.requestCounts["assets"] == 3)
    }

    private func connected(_ transport: MutationFixtureTransport, store: MemoryPrivateStore = MemoryPrivateStore()) async throws -> LiveMFLRepository {
        try store.encode(SavedSession(cookie: "synthetic-cookie", season: 2026, leagueID: "41333", franchiseID: "0001"), key: "session")
        let repository = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero)
        _ = try await repository.restoreSession()
        return repository
    }
    private var draft: TradeDraft { TradeDraft(partnerID: "0002", giving: ["201"], receiving: ["101"], comments: "Synthetic offer") }

    @Test("Incoming trade perspective and ownership remain correct")
    func direction() async throws {
        let transport = MutationFixtureTransport()
        await transport.seedTrade()
        let repository = try await connected(transport)
        let snapshot = try await repository.loadTrades()
        let offer = try #require(snapshot.offers.first)
        #expect(offer.sending(for: "0001").map(\.id) == ["201"])
        #expect(offer.getting(for: "0001").map(\.id) == ["101"])
        #expect(offer.isActionable)
        #expect(snapshot.teams.first { $0.id == "0002" }?.assets.contains { $0.id == "FP_0002_2027_1" } == true)
    }

    @Test("A verified new offer clears the durable marker and a duplicate is not sent")
    func proposal() async throws {
        let transport = MutationFixtureTransport()
        let repository = try await connected(transport)
        let receipt = try await repository.performTrade(.propose(draft))
        #expect(receipt.confirmed)
        #expect(try await repository.pendingTradeAction() == nil)
        await #expect(throws: (any Error).self) { try await repository.performTrade(.propose(draft)) }
        #expect(await transport.imports == ["tradeProposal"])
    }

    @Test("Changed asset ownership stops a proposal before any POST")
    func movedAsset() async throws {
        let transport = MutationFixtureTransport()
        let repository = try await connected(transport)
        _ = try await repository.loadTrades()
        await transport.moveTradePlayer()
        await #expect(throws: (any Error).self) { try await repository.performTrade(.propose(draft)) }
        #expect(await transport.imports.isEmpty)
    }

    @Test("A changed offer cannot be accepted with the old review")
    func changedOffer() async throws {
        let transport = MutationFixtureTransport()
        await transport.seedTrade()
        let repository = try await connected(transport)
        let offer = try #require(try await repository.loadTrades().offers.first)
        await transport.changeTradeTerms()
        await #expect(throws: (any Error).self) { try await repository.performTrade(.respond(offer, .accept, comments: "")) }
        #expect(await transport.imports.isEmpty)
    }

    @Test("Accept, decline and withdraw enforce participant roles", arguments: [MFLTradeResponse.accept, .reject, .revoke])
    func roles(action: MFLTradeResponse) async throws {
        let transport = MutationFixtureTransport()
        await transport.seedTrade(outgoing: action != .revoke)
        let repository = try await connected(transport)
        let offer = try #require(try await repository.loadTrades().offers.first)
        await #expect(throws: (any Error).self) { try await repository.performTrade(.respond(offer, action, comments: "")) }
        #expect(await transport.imports.isEmpty)
    }

    @Test("Expired offers and unrecognized assets cannot be accepted", arguments: [true, false])
    func unsafeOffer(expired: Bool) async throws {
        let transport = MutationFixtureTransport()
        await transport.seedTrade(expired: expired, unknownAsset: !expired)
        let repository = try await connected(transport)
        let offer = try #require(try await repository.loadTrades().offers.first)
        #expect(!offer.isActionable)
        await #expect(throws: (any Error).self) { try await repository.performTrade(.respond(offer, .accept, comments: "")) }
        #expect(await transport.imports.isEmpty)
    }

    @Test("Response acknowledgements plus fresh disappearance verify the response, not completed roster movement", arguments: [MFLTradeResponse.accept, .reject, .revoke])
    func acknowledged(action: MFLTradeResponse) async throws {
        let transport = MutationFixtureTransport()
        await transport.seedTrade(outgoing: action == .revoke)
        let repository = try await connected(transport)
        let offer = try #require(try await repository.loadTrades().offers.first)
        let receipt = try await repository.performTrade(.respond(offer, action, comments: "Thanks"))
        #expect(receipt.confirmed)
        if action == .accept { #expect(receipt.message.contains("approval")) }
        #expect(try await repository.pendingTradeAction() == nil)
    }

    @Test("A lost proposal response survives relaunch and readback confirms it without a second POST")
    func proposalTimeout() async throws {
        let store = MemoryPrivateStore()
        let transport = MutationFixtureTransport()
        let repository = try await connected(transport, store: store)
        await transport.failTrade()
        let receipt = try await repository.performTrade(.propose(draft))
        #expect(!receipt.confirmed)
        let restored = try await connected(transport, store: store)
        #expect(try await restored.pendingTradeAction() != nil)
        await #expect(throws: (any Error).self) { try await restored.performTrade(.propose(draft)) }
        #expect(try await restored.reconcileTradeAction().confirmed)
        #expect(await transport.imports == ["tradeProposal"])
    }

    @Test("Disappearance after an accept timeout is not proof of acceptance")
    func ambiguousAcceptance() async throws {
        let transport = MutationFixtureTransport()
        await transport.seedTrade()
        let repository = try await connected(transport)
        let offer = try #require(try await repository.loadTrades().offers.first)
        await transport.failTrade(afterRemoval: true)
        #expect(try await !repository.performTrade(.respond(offer, .accept, comments: "")).confirmed)
        #expect(try await !repository.reconcileTradeAction().confirmed)
        #expect(try await repository.pendingTradeAction() != nil)
        #expect(await transport.imports == ["tradeResponse"])
    }

    @Test("Counteroffers require acknowledgement and do not silently reject the original")
    func counteroffer() async throws {
        let transport = MutationFixtureTransport()
        await transport.seedTrade()
        let repository = try await connected(transport)
        let original = try #require(try await repository.loadTrades().offers.first)
        var counter = draft
        counter.countering = original
        await #expect(throws: (any Error).self) { try await repository.performTrade(.propose(counter)) }
        counter.acknowledgesOriginalStaysOpen = true
        #expect(try await repository.performTrade(.propose(counter)).confirmed)
        #expect(try await repository.loadTrades().offers.contains { $0.id == original.id })
        #expect(await transport.imports == ["tradeProposal"])
    }

    @Test("Trade drafts survive reopening and stay isolated by franchise")
    @MainActor func privateDrafts() throws {
        let store = MemoryPrivateStore()
        let first = TransactionsModel(workspace: SampleData.workspace, privateStore: store)
        let saved = draft
        first.saveDraft(saved)
        let reopened = TransactionsModel(workspace: SampleData.workspace, privateStore: store)
        #expect(reopened.draft == saved)
        let other = LeagueWorkspace(leagueID: "41333", season: 2026, leagueName: "Test", franchiseID: "0002", franchiseName: "Other",
            baseURL: SampleData.workspace.baseURL, week: 1)
        #expect(TransactionsModel(workspace: other, privateStore: store).draft == nil)
    }
}
