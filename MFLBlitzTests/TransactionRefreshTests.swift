import Foundation
import Testing
@testable import MFLBlitz

@MainActor
struct TransactionRefreshTests {
    @Test("Switching sections during a read does not create a false failure or delay the next load", arguments: [true, false])
    func canceledRead(activity: Bool) async {
        let repository = ReliabilityRepository()
        let gate = TestGate()
        await repository.pauseTransactions(gate)
        let model = TransactionsModel(repository: repository, workspace: SampleData.workspace, privateStore: MemoryPrivateStore())
        let read = Task { if activity { await model.refreshActivity() } else { await model.refresh() } }
        while !model.isLoading && !model.isLoadingActivity { await Task.yield() }
        read.cancel()
        await gate.open()
        await read.value
        #expect(model.readError == nil && model.activityError == nil)
        #expect(model.lastActivityRefresh == nil && model.snapshot.updatedAt == nil)
        if activity { await model.refreshActivity() } else { await model.refresh() }
        #expect(activity ? model.lastActivityRefresh != nil : model.snapshot.updatedAt != nil)
    }

    @Test("Reentering Trades and Activity reuses recent successful reads")
    func avoidsRepeatedLoads() async {
        let repository = ReliabilityRepository()
        let model = TransactionsModel(repository: repository, workspace: SampleData.workspace, privateStore: MemoryPrivateStore())
        await model.refresh(ifNeeded: true)
        await model.refreshActivity(ifNeeded: true)
        await model.refresh(ifNeeded: true)
        await model.refreshActivity(ifNeeded: true)
        #expect(await repository.tradeLoads == 1)
        #expect(await repository.activityLoads == 1)
        #expect(model.canAct)
        #expect(model.lastActivityRefresh != nil)
    }

    @Test("An MFL cooldown blocks repeated trade requests and never makes unread Activity look empty")
    func sharedCooldown() async {
        let repository = ReliabilityRepository()
        await repository.failTradeReads()
        let model = TransactionsModel(repository: repository, workspace: SampleData.workspace, privateStore: MemoryPrivateStore())
        model.saveDraft(TradeDraft(partnerID: "0002", giving: ["201"], receiving: ["101"]))
        let draft = model.draft
        await model.refresh()
        await model.refresh()
        await model.refreshActivity()
        #expect(await repository.tradeLoads == 1)
        #expect(await repository.activityLoads == 0)
        #expect(model.readError != nil && model.activityError != nil)
        #expect(model.retryAfter.map { $0 > Date() } == true)
        #expect(model.lastActivityRefresh == nil)
        #expect(!model.canAct && !model.isLoading && !model.isLoadingActivity)
        #expect(model.draft == draft)
    }

    @Test("Refreshing waivers does not reload scores or discard existing data on failure")
    func scopedWaivers() async {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        let scores = await repository.scoreLoads
        let waivers = await repository.waiverLoads
        let existing = model.waivers.claims
        model.waiverReadError = "Needs refresh"
        await repository.failWaiverReads()
        await model.refreshWaivers()
        #expect(await repository.scoreLoads == scores)
        #expect(await repository.waiverLoads == waivers + 1)
        #expect(model.waivers.claims == existing)
        #expect(model.waiverReadError != nil && model.notice == nil)
        #expect(!model.isLoadingWaivers)
    }

    @Test("Quick foreground transitions do not repeat a full league refresh")
    func foregroundCooldown() async {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        let loads = await repository.scoreLoads
        await model.refreshForForeground()
        await model.refreshForForeground()
        #expect(await repository.scoreLoads == loads)
    }
}
