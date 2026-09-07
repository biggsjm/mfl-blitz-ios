import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

final class MemoryPrivateStore: PrivateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(_ key: String) -> Data? { lock.withLock { values[key] } }
    func write(_ data: Data, key: String) { lock.withLock { values[key] = data } }
    func remove(_ key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
}

actor ReliabilityRepository: LeagueRepository {
    var waiverGate: TestGate?
    var transactionGate: TestGate?
    var restoreGate: TestGate?
    var lineupGate: TestGate?
    var scoreGate: TestGate?
    var scoreFailure: (any Error)?
    var restoreFailure: MFLCoreError?
    var testLineup = SampleData.lineup
    var testWaivers = SampleData.waivers
    var week = 1
    var expired = false
    var scoreLoads = 0
    var lineupLoads = 0
    var boardLoads = 0
    var standingsLoads = 0
    var waiverLoads = 0
    var tradeLoads = 0
    var activityLoads = 0
    var tradeReadFailure: MFLCoreError?
    var waiverReadFailure: MFLCoreError?
    var submittedClaims: [WaiverClaim]?
    var testWorkspace = SampleData.workspace

    init() { testLineup.serverStarterPlayerIDs = Set(testLineup.starters.map(\.id)); testWaivers.unavailableReason = nil }
    func signIn(with credentials: LoginCredentials) async throws -> LeagueWorkspace { testWorkspace }
    func restoreSession() async throws -> LeagueWorkspace? {
        if let restoreGate { await restoreGate.wait() }
        if let restoreFailure { throw restoreFailure }
        return testWorkspace
    }
    func loadWorkspace() async throws -> LeagueWorkspace { testWorkspace }
    func currentWeek() async throws -> Int {
        if expired { throw MFLCoreError.unauthorized("Expired") }
        return week
    }
    func loadScores(week: Int) async throws -> ScoresSnapshot {
        scoreLoads += 1
        if let scoreGate { await scoreGate.wait() }
        if let scoreFailure { throw scoreFailure }
        var result = SampleData.scores; result.week = week; return result
    }
    func failScores(_ error: (any Error)?) { scoreFailure = error }
    func pauseScores(_ gate: TestGate) { scoreGate = gate }
    func loadLineup(week: Int) async throws -> LineupSnapshot {
        lineupLoads += 1
        if let lineupGate { await lineupGate.wait() }
        var result = testLineup; result.week = week; return result
    }
    func submitLineup(_ lineup: LineupSnapshot) async throws {
        testLineup = lineup
        testLineup.serverStarterPlayerIDs = Set(lineup.starters.map(\.id))
        testLineup.preferredStartingAssignments = nil // MFL does not store presentation slots.
    }
    func loadWaivers() async throws -> WaiverSnapshot {
        waiverLoads += 1
        if let waiverReadFailure { throw waiverReadFailure }
        if let waiverGate { await waiverGate.wait() }
        return testWaivers
    }
    func pauseWaivers(_ gate: TestGate) { waiverGate = gate }
    func pauseRestore(_ gate: TestGate) { restoreGate = gate }
    func pauseLineup(_ gate: TestGate) { lineupGate = gate }
    func failRestore(_ error: MFLCoreError?) { restoreFailure = error }
    func submitWaivers(_ claims: [WaiverClaim], replacing baseline: [WaiverClaim]) async throws {
        submittedClaims = claims; testWaivers.claims = claims
    }
    func loadStandings() async throws -> [StandingRow] { standingsLoads += 1; return SampleData.standings }
    func loadBoard() async throws -> [BoardThread] { boardLoads += 1; return SampleData.board }
    func loadThread(id: String) async throws -> BoardThread { SampleData.board[0] }
    func postMessage(subject: String?, body: String, threadID: String?) async throws {}
    func signOut() async {}
    func failTradeReads() { tradeReadFailure = .rateLimited(retryAfter: 15) }
    func pauseTransactions(_ gate: TestGate) { transactionGate = gate }
    func failWaiverReads() { waiverReadFailure = .rateLimited(retryAfter: 15) }
    func loadTrades() async throws -> TradeSnapshot {
        tradeLoads += 1
        if let transactionGate { await transactionGate.wait() }
        if let tradeReadFailure { throw tradeReadFailure }
        var snapshot = SampleData.trades; snapshot.updatedAt = Date(); return snapshot
    }
    func loadTransactionActivity() async throws -> [TransactionActivity] {
        activityLoads += 1
        if let transactionGate { await transactionGate.wait() }
        if let tradeReadFailure { throw tradeReadFailure }
        return [TransactionActivity(id: "fixture", title: "Trade", detail: "Synthetic activity", isTrade: true)]
    }
    func setWeek(_ value: Int) { week = value }
    func expire() { expired = true }
    func changeSavedLineup() {
        testLineup.players[0].isStarter.toggle()
        testLineup.serverStarterPlayerIDs = Set(testLineup.starters.map(\.id))
    }
    func changeTeam() {
        testWorkspace = LeagueWorkspace(leagueID: testWorkspace.leagueID, season: testWorkspace.season,
            leagueName: testWorkspace.leagueName, franchiseID: "other", franchiseName: "Other",
            baseURL: testWorkspace.baseURL, week: 1)
    }
}

actor TestGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

@MainActor
struct ReliabilityTests {
    private func cancellation(_ kind: String) -> any Error {
        switch kind {
        case "swift": CancellationError()
        case "url": URLError(.cancelled)
        default: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled,
                         userInfo: [NSURLErrorFailingURLStringErrorKey: "https://synthetic.invalid/private"])
        }
    }

    @Test("Cancelled manual and polling score reads retain data without a stale banner or alert",
          arguments: ["swift", "url", "ns"], [false, true])
    func cancelledScoreRefresh(kind: String, silent: Bool) async throws {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        let previous = model.scores
        await repository.failScores(cancellation(kind))
        await model.refreshScores(silent: silent)
        #expect(model.scores == previous)
        #expect(model.scoreRefreshError == nil && model.notice == nil)
        #expect(!model.isLoadingScores && !model.isRefreshing)
        #expect(model.phase == .signedIn)
        let beforeRetry = await repository.scoreLoads
        await repository.failScores(nil)
        await model.refreshScores()
        #expect(await repository.scoreLoads == beforeRetry + 1)
        #expect(model.scoreRefreshError == nil && model.notice == nil)
    }

    @Test("A cancelled score branch does not fail the full refresh or strand loading states", arguments: ["swift", "url", "ns"])
    func cancelledFullRefresh(kind: String) async throws {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        let previous = model.scores, beforeBoard = await repository.boardLoads
        await repository.failScores(cancellation(kind))
        await model.refreshAll()
        #expect(model.scores == previous)
        #expect(model.scoreRefreshError == nil && model.notice == nil)
        #expect(!model.isLoadingScores && !model.isLoadingLineup && !model.isLoadingBoard && !model.isLoadingWaivers)
        #expect(!model.isRefreshing)
        #expect(await repository.boardLoads == beforeBoard + 1)
        // An interrupted full refresh must not start the foreground cooldown.
        let beforeRetry = await repository.scoreLoads
        await repository.failScores(nil)
        await model.refreshForForeground()
        #expect(await repository.scoreLoads == beforeRetry + 1)
        #expect(model.notice == nil && model.scoreRefreshError == nil)
    }

    @Test("Cancelling a running score task does not surface its late network failure")
    func cancelledScoreTask() async throws {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        let before = await repository.scoreLoads
        let gate = TestGate()
        await repository.pauseScores(gate)
        await repository.failScores(URLError(.networkConnectionLost))
        let task = Task { await model.refreshScores() }
        while await repository.scoreLoads == before { await Task.yield() }
        task.cancel()
        await gate.open()
        await task.value
        #expect(model.scoreRefreshError == nil && model.notice == nil)
        #expect(!model.isRefreshing && !model.isLoadingScores)
    }

    @Test("Genuine score failures remain visible and cancellation does not erase an existing warning")
    func genuineScoreFailure() async throws {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        let previous = model.scores
        await repository.failScores(MFLCoreError.transport("private diagnostics"))
        await model.refreshScores()
        #expect(model.notice == .error("Couldn’t complete the MFL request. Please try again."))
        let warning = try #require(model.scoreRefreshError)
        model.notice = nil
        await repository.failScores(URLError(.cancelled))
        await model.refreshScores()
        #expect(model.notice == nil && model.scoreRefreshError == warning && model.scores == previous)
        await repository.failScores(nil)
        await model.refreshScores()
        #expect(model.scoreRefreshError == nil && model.notice == nil)
    }

    @Test("Visible-section refreshes do not reload unrelated feeds or replace an edited lineup")
    func scopedRefreshBudget() async throws {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        let beforeScores = await repository.scoreLoads, beforeLineups = await repository.lineupLoads
        let beforeWaivers = await repository.waiverLoads, beforeBoard = await repository.boardLoads
        let beforeStandings = await repository.standingsLoads
        let replacement = try #require(model.replacementRequest(for: "14073"))
        #expect(model.replaceStarter(replacement, with: "15712"))
        let drafted = model.lineup
        await model.refreshLineup()
        #expect(await repository.lineupLoads == beforeLineups + 1)
        #expect(await repository.scoreLoads == beforeScores)
        #expect(await repository.waiverLoads == beforeWaivers)
        #expect(await repository.boardLoads == beforeBoard)
        #expect(await repository.standingsLoads == beforeStandings)
        #expect(model.lineup.starters.map(\.id) == drafted.starters.map(\.id))
        await model.refreshScores()
        await model.refreshBoard()
        await model.refreshStandings()
        #expect(await repository.scoreLoads == beforeScores + 1)
        #expect(await repository.boardLoads == beforeBoard + 1)
        #expect(await repository.standingsLoads == beforeStandings + 1)
        #expect(await repository.lineupLoads == beforeLineups + 1)
        #expect(await repository.waiverLoads == beforeWaivers)
    }

    @Test("Replacement drafts survive restart without submitting, and old-account pickers cannot act")
    func replacementDraftRecovery() async throws {
        let store = MemoryPrivateStore()
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: store)
        await model.signIn(credentials: LoginCredentials())
        let request = try #require(model.replacementRequest(for: "14073"))
        #expect(model.replaceStarter(request, with: "15712"))
        let savedOnServer = await repository.testLineup
        #expect(savedOnServer.starters.contains { $0.id == "14073" })
        #expect(!savedOnServer.starters.contains { $0.id == "15712" })
        let restored = AppModel(repository: repository, privateStore: store)
        await restored.restoreSession()
        #expect(restored.lineup.starters.contains { $0.id == "15712" })
        #expect(restored.lineup.bench.contains { $0.id == "14073" })
        #expect(restored.lineup.starters.count == savedOnServer.starters.count)
        #expect(restored.hasLineupChanges)
        let oldAccountRequest = try #require(model.replacementRequest(for: "12620"))
        await model.signOut()
        await repository.changeTeam()
        await model.signIn(credentials: LoginCredentials())
        #expect(model.replacementCandidates(for: oldAccountRequest).isEmpty)
        #expect(!model.replaceStarter(oldAccountRequest, with: "14056"))
        #expect(!model.hasLineupChanges)
    }

    @Test("Reconnect ends and each tab appears before slow waivers finish")
    func progressiveReconnect() async throws {
        let repository = ReliabilityRepository()
        let gate = TestGate()
        await repository.pauseWaivers(gate)
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        let restore = Task { await model.restoreSession() }
        for _ in 0..<100 {
            if model.phase == .signedIn && !model.lineup.players.isEmpty && !model.scores.matchups.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.phase == .signedIn)
        #expect(!model.isRestoringSession)
        #expect(!model.isBusy)
        #expect(!model.scores.matchups.isEmpty)
        #expect(!model.lineup.players.isEmpty)
        #expect(model.isLoadingWaivers)
        #expect(model.canSubmitLineup)
        #expect(!model.canSubmitWaivers)
        await gate.open()
        await restore.value
        #expect(!model.isLoadingWaivers)
    }

    @Test("Cancel reconnect leaves drafts alone and ignores late completion")
    func cancelReconnect() async throws {
        let repository = ReliabilityRepository()
        let gate = TestGate()
        await repository.pauseRestore(gate)
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        let restore = Task { await model.restoreSession() }
        for _ in 0..<100 {
            if model.isRestoringSession { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        model.cancelReconnect()
        #expect(!model.isRestoringSession)
        #expect(!model.isBusy)
        await model.continueInDemo()
        await gate.open()
        await restore.value
        #expect(model.isDemo)
        #expect(model.phase == .signedIn)
    }

    @Test("Refresh preserves lineup edits and detects a server conflict")
    func lineupRefresh() async {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        let id = model.lineup.starters.first(where: { !$0.isLocked })!.id
        model.toggleStarter(id)
        await model.refreshAll()
        #expect(model.hasLineupChanges)
        #expect(model.lineup.players.first(where: { $0.id == id })?.isStarter == false)
        await repository.changeSavedLineup()
        await model.refreshAll()
        #expect(model.lineupConflict != nil)
        #expect(!model.canSubmitLineup)
        model.discardLineupDraft()
        #expect(model.lineupConflict == nil)
        #expect(!model.hasLineupChanges)
    }

    @Test("Lineup and board drafts survive a new app model and remain team scoped")
    func restoredDrafts() async {
        let store = MemoryPrivateStore()
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: store)
        await model.signIn(credentials: LoginCredentials())
        let id = model.lineup.starters.first(where: { !$0.isLocked })!.id
        model.toggleStarter(id)
        model.saveBoardDraft(subject: "Week one", body: "Fixture draft", threadID: nil)
        let restored = AppModel(repository: repository, privateStore: store)
        await restored.restoreSession()
        #expect(restored.phase == .signedIn)
        #expect(restored.hasLineupChanges)
        #expect(restored.lineup.players.first(where: { $0.id == id })?.isStarter == false)
        #expect(restored.boardDraft(threadID: nil).body == "Fixture draft")
        await repository.changeTeam()
        let other = AppModel(repository: repository, privateStore: store)
        await other.restoreSession()
        #expect(other.boardDraft(threadID: nil).body.isEmpty)
        #expect(!other.hasLineupChanges)
    }

    @Test("Deleting the final bid stays a draft through refresh and can clear MFL")
    func cancelAllBids() async {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        for round in Set(model.waivers.claims.map(\.round)) {
            model.removeClaims(inRound: round, at: IndexSet(0..<model.waivers.claims.filter { $0.round == round }.count))
        }
        #expect(model.waivers.claims.isEmpty)
        #expect(model.hasWaiverChanges)
        await model.refreshAll()
        #expect(model.waivers.claims.isEmpty)
        #expect(await model.submitWaivers())
        #expect(await repository.submittedClaims?.isEmpty == true)
        #expect(!model.hasWaiverChanges)
    }

    @Test("Week rollover follows current week but preserves explicitly selected history")
    func rollover() async {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore(), foregroundRefreshInterval: 0)
        await model.signIn(credentials: LoginCredentials())
        await repository.setWeek(2)
        await model.refreshForForeground()
        #expect(model.selectedWeek == 2)
        #expect(model.scores.week == 2)
        #expect(model.lineup.week == 2)
        await model.changeWeek(to: 1)
        await repository.setWeek(3)
        await model.refreshForForeground()
        #expect(model.selectedWeek == 1)
        #expect(model.currentWeek == 3)
    }

    @Test("Expired authentication returns to sign-in without deleting drafts")
    func expiredSession() async {
        let repository = ReliabilityRepository()
        let store = MemoryPrivateStore()
        let model = AppModel(repository: repository, privateStore: store, foregroundRefreshInterval: 0)
        await model.signIn(credentials: LoginCredentials())
        model.saveBoardDraft(subject: "Keep", body: "Private fixture", threadID: nil)
        await repository.expire()
        await model.refreshForForeground()
        #expect(model.phase == .onboarding)
        let restored = AppModel(repository: repository, privateStore: store)
        await restored.restoreSession()
        #expect(restored.boardDraft(threadID: nil).body == "Private fixture")
    }

    @Test("Disconnect deletes this team's drafts")
    func disconnect() async {
        let repository = ReliabilityRepository()
        let store = MemoryPrivateStore()
        let model = AppModel(repository: repository, privateStore: store)
        await model.signIn(credentials: LoginCredentials())
        model.saveBoardDraft(subject: "Delete", body: "Fixture", threadID: nil)
        let key = "drafts.\(model.workspace!.storageScope)"
        #expect(store.read(key) != nil)
        await model.signOut()
        #expect(store.read(key) == nil)
    }

    @Test("Calendar uses explicit future blind-bid occurrences, not stale recurrences")
    func deadline() throws {
        let calendar = try JSONDecoder().decode(MFLJSONValue.self, from: Data(#"{"calendar":{"event":[{"type":"WAIVER_BBID","start_time":"100"},{"type":"WAIVER_BBID","start_time":"300"},{"type":"WAIVER_LOCK","start_time":"200"}]}}"#.utf8))
        #expect(LiveMFLRepository.nextBlindBidDate(in: calendar, now: Date(timeIntervalSince1970: 150)) == Date(timeIntervalSince1970: 300))
    }
}
