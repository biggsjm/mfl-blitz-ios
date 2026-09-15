import Foundation
import Testing
import MFLCore
@testable import MFLBlitz

@MainActor
@Suite("Craft: continuity, truthful scores and league weeks")
struct CraftFlowTests {
    @Test("Summary refreshes retain loaded messages even when the thread leaves the first page")
    func boardContinuity() async throws {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore(), foregroundRefreshInterval: 0)
        await model.signIn(credentials: LoginCredentials())
        let thread = try #require(SampleData.board.first)
        await model.loadThread(id: thread.id)
        #expect(model.boardThread(id: thread.id)?.posts == thread.posts)
        await repository.setBoard(SampleData.board.map { item in var summary = item; summary.posts = []; return summary })
        await model.refreshForForeground()
        #expect(model.boardThread(id: thread.id)?.posts == thread.posts)
        await repository.setBoard([])
        await model.refreshBoard()
        #expect(model.boardThreads.isEmpty)
        #expect(model.boardThread(id: thread.id)?.posts == thread.posts)
        // Use an offline notification service: this test verifies account-scoped content,
        // not Simulator notification-daemon delivery or cleanup.
        model.leagueCalendar = LeagueCalendarModel(repository: repository, workspace: SampleData.workspace,
            store: ProtectedFeedStore(MemoryPrivateStore()), notifications: PreviewDeadlineNotifications())
        await model.signOut()
        #expect(model.boardThread(id: thread.id) == nil)
        #expect(model.boardThreadErrors.isEmpty)
    }

    @Test("Thread loading exposes state, coalesces reentry and preserves messages on retry failure")
    func threadRecovery() async throws {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        let thread = try #require(SampleData.board.first)
        let gate = TestGate()
        await repository.pauseThread(gate)
        let request = Task { await model.loadThread(id: thread.id) }
        let began = await waitUntil { model.loadingBoardThreadIDs.contains(thread.id) }
        await model.loadThread(id: thread.id)
        await gate.open()
        await request.value
        #expect(began)
        #expect(await repository.threadLoads == 1)
        #expect(model.loadingBoardThreadIDs.isEmpty)
        await repository.failThread(URLError(.notConnectedToInternet))
        await model.loadThread(id: thread.id)
        #expect(model.boardThread(id: thread.id)?.posts == thread.posts)
        #expect(model.boardThreadErrors[thread.id] != nil)
        #expect(model.notice == nil)
        await repository.failThread(nil)
        await model.loadThread(id: thread.id)
        #expect(model.boardThreadErrors[thread.id] == nil)
    }

    @Test("An older thread refresh cannot erase a confirmed reply readback")
    func threadReplyWinsOverOlderRead() async throws {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        var thread = try #require(SampleData.board.first)
        let gate = TestGate()
        await repository.pauseThread(gate)
        let old = Task { await model.loadThread(id: thread.id) }
        let began = await waitUntil { model.loadingBoardThreadIDs.contains(thread.id) }
        // Wait for the repository to capture its old response before exposing a newer reply.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await repository.threadLoads == 0, ContinuousClock.now < deadline { await Task.yield() }
        thread.posts.append(BoardPost(id: "craft-reply", author: "Preview owner", body: "A newly confirmed reply", postedAt: .now, isUser: true))
        await repository.setThreadDetails([thread])
        await repository.resumeThreads()
        let posted = await model.post(subject: nil, body: "A newly confirmed reply", threadID: thread.id)
        await gate.open()
        await old.value
        #expect(began && posted)
        #expect(model.boardThread(id: thread.id)?.posts.last?.id == "craft-reply")
        #expect(!model.loadingBoardThreadIDs.contains(thread.id))
    }

    @Test("Week change publishes scores without waiting for lineup, and vice versa", arguments: [true, false])
    func independentWeekResults(holdLineup: Bool) async {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        let gate = TestGate()
        if holdLineup { await repository.pauseLineup(gate) }
        else { await repository.pauseScores(gate) }
        let change = Task { await model.changeWeek(to: 2) }
        let arrived = await waitUntil {
            model.selectedWeek == 2 && (holdLineup ? !model.isLoadingScores : !model.isLoadingLineup)
        }
        let otherStillLoading = holdLineup ? model.isLoadingLineup : model.isLoadingScores
        let immediateWeek = holdLineup ? model.scores.week : model.lineup.week
        await gate.open()
        await change.value
        #expect(arrived && otherStillLoading && immediateWeek == 2)
        #expect(!model.isLoadingScores && !model.isLoadingLineup)
    }

    @Test("An older week request cannot replace results from a newer selection")
    func changedWeekIdentity() async {
        let repository = ReliabilityRepository()
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        let gate = TestGate()
        await repository.pauseLineup(gate)
        let old = Task { await model.changeWeek(to: 2) }
        let began = await waitUntil { model.selectedWeek == 2 && !model.isLoadingScores }
        await repository.resumeLineups()
        await model.changeWeek(to: 3)
        await gate.open()
        await old.value
        #expect(began)
        #expect(model.selectedWeek == 3 && model.scores.week == 3 && model.lineup.week == 3)
        #expect(!model.isLoadingScores && !model.isLoadingLineup)
    }

    @Test("Projection margin is an owner-oriented points difference with honest missing data")
    func projectedMargin() throws {
        var matchup = try #require(SampleData.scores.featuredMatchup)
        matchup.away.projectedScore = 150
        matchup.home.projectedScore = 100
        #expect(matchup.projectedMargin(for: matchup.away.id) == 50)
        #expect(matchup.projectedMargin(for: matchup.home.id) == -50)
        #expect(matchup.projectedMargin(for: "missing") == nil)
        matchup.home.projectedScore = 150
        #expect(matchup.projectedMargin(for: matchup.home.id) == 0)
        matchup.home.projectedScore = nil
        #expect(matchup.projectedMargin(for: matchup.away.id) == nil)
        matchup.home.projectedScore = .infinity
        #expect(matchup.projectedMargin(for: matchup.away.id) == nil)
    }

    @Test("A league game does not become the owner's matchup on a bye or missing-owner response")
    func absentOwnerMatchup() {
        var snapshot = SampleData.scores
        snapshot.matchups = snapshot.matchups.map { item in var other = item; other.isUserMatchup = false; return other }
        #expect(!snapshot.matchups.isEmpty)
        #expect(snapshot.featuredMatchup == nil)
    }

    @Test("A reopened session can return to a published start week when the end is unknown")
    func partialLeagueBounds() async {
        let repository = ReliabilityRepository()
        let sample = SampleData.workspace
        let workspace = LeagueWorkspace(leagueID: sample.leagueID, season: sample.season,
            leagueName: sample.leagueName, franchiseID: sample.franchiseID,
            franchiseName: sample.franchiseName, baseURL: sample.baseURL, week: 5, firstWeek: 1)
        await repository.setWorkspace(workspace)
        await repository.setWeek(5)
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore(), foregroundRefreshInterval: 0)
        await model.signIn(credentials: LoginCredentials())
        #expect(model.availableWeeks == [1, 5])
        await model.changeWeek(to: 1)
        await model.refreshForForeground()
        #expect(model.selectedWeek == 1 && model.currentWeek == 5)
    }

    @Test("Configured week bounds govern navigation and older cached workspaces decode safely")
    func leagueWeeks() async throws {
        let repository = ReliabilityRepository()
        var workspace = SampleData.workspace
        workspace.firstWeek = 2; workspace.lastWeek = 20
        await repository.setWorkspace(workspace)
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await model.signIn(credentials: LoginCredentials())
        #expect(model.availableWeeks == Array(2...20))
        await model.changeWeek(to: 20)
        #expect(model.selectedWeek == 20)
        await model.changeWeek(to: 21)
        #expect(model.selectedWeek == 20)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        json.removeValue(forKey: "firstWeek"); json.removeValue(forKey: "lastWeek")
        let legacy = try JSONDecoder().decode(LeagueWorkspace.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.configuredWeeks == nil)
        model.workspace = legacy
        #expect(model.availableWeeks == [1, 20])
        model.seasonSchedule = SeasonScheduleModel {
            SeasonScheduleSnapshot(source: MFLSchedule(weeks: []), season: 2026, leagueID: "sample")
        }
        await model.seasonSchedule.loadIfNeeded()
        #expect(model.configuredWeekRange == nil)
        #expect(model.availableWeeks == [1, 20])
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() && ContinuousClock.now < deadline { await Task.yield() }
        return predicate()
    }
}
