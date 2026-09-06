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
    var testLineup = SampleData.lineup
    var testWaivers = SampleData.waivers
    var week = 1
    var expired = false
    var scoreLoads = 0
    var submittedClaims: [WaiverClaim]?
    var testWorkspace = SampleData.workspace

    init() { testLineup.serverStarterPlayerIDs = Set(testLineup.starters.map(\.id)); testWaivers.unavailableReason = nil }
    func signIn(with credentials: LoginCredentials) async throws -> LeagueWorkspace { testWorkspace }
    func restoreSession() async throws -> LeagueWorkspace? { testWorkspace }
    func loadWorkspace() async throws -> LeagueWorkspace { testWorkspace }
    func currentWeek() async throws -> Int {
        if expired { throw MFLCoreError.unauthorized("Expired") }
        return week
    }
    func loadScores(week: Int) async throws -> ScoresSnapshot {
        scoreLoads += 1
        var result = SampleData.scores; result.week = week; return result
    }
    func loadLineup(week: Int) async throws -> LineupSnapshot {
        var result = testLineup; result.week = week; return result
    }
    func submitLineup(_ lineup: LineupSnapshot) async throws { testLineup = lineup }
    func loadWaivers() async throws -> WaiverSnapshot { testWaivers }
    func submitWaivers(_ claims: [WaiverClaim], replacing baseline: [WaiverClaim]) async throws {
        submittedClaims = claims; testWaivers.claims = claims
    }
    func loadStandings() async throws -> [StandingRow] { SampleData.standings }
    func loadBoard() async throws -> [BoardThread] { SampleData.board }
    func loadThread(id: String) async throws -> BoardThread { SampleData.board[0] }
    func postMessage(subject: String?, body: String, threadID: String?) async throws {}
    func signOut() async {}
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

@MainActor
struct ReliabilityTests {
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
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
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
        let model = AppModel(repository: repository, privateStore: store)
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
