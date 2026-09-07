import Foundation
import MFLCore
import Testing
import UIKit
@testable import MFLBlitz

@MainActor
struct MyTeamNavigationTests {
    @Test("My Team exposes six unique direct destinations with Schedule first")
    func directDestinations() {
        let routes = TeamToolsRoute.Destination.allCases
        #expect(routes == [.schedule, .addsDrops, .trades, .watchlist, .injuredReserve, .activity])
        #expect(routes.map(\.title) == ["Schedule", "Adds / Drops", "Trades", "Watchlist", "Injured Reserve", "League Activity"])
        #expect(Set(routes.map(\.accessibilityID)).count == 6)
        #expect(routes.allSatisfy { !$0.symbol.isEmpty })
    }

    @Test("Roster tools require a matching successful capability read")
    func rosterToolCapabilities() async throws {
        let tools = RosterToolsModel()
        let context = try await DemoLeagueRepository().loadRosterActionContext()
        #expect(!tools.canPerform(.add, scope: context.scope))
        await tools.load(scope: context.scope) { context }
        #expect(tools.canPerform(.add, scope: context.scope))
        #expect(!tools.canPerform(.add, scope: nil))
        #expect(!tools.canPerform(.add, scope: "other-owner"))
        var disabled = context
        disabled.allowed = [.drop]
        await tools.load(scope: context.scope) { disabled }
        #expect(!tools.canPerform(.add, scope: context.scope))
        #expect(tools.canPerform(.drop, scope: context.scope))
    }

    @Test("Failed refresh keeps roster readable but disables mutations")
    func rosterToolRefreshFailure() async throws {
        let tools = RosterToolsModel()
        let context = try await DemoLeagueRepository().loadRosterActionContext()
        await tools.load(scope: context.scope) { context }
        await tools.load(scope: context.scope) {
            #expect(tools.isLoading)
            #expect(!tools.canPerform(.drop, scope: context.scope))
            throw URLError(.notConnectedToInternet)
        }
        #expect(tools.context == context)
        #expect(tools.error != nil && !tools.isLoading)
        #expect(!tools.canPerform(.drop, scope: context.scope))
        await tools.load(scope: context.scope) { context }
        #expect(tools.error == nil && tools.canPerform(.drop, scope: context.scope))
    }

    @Test("Changing owner clears selected actions and rejects mismatched payloads")
    func rosterToolOwnerChange() async throws {
        let tools = RosterToolsModel()
        let context = try await DemoLeagueRepository().loadRosterActionContext()
        await tools.load(scope: context.scope) { context }
        tools.selected = RosterActionRequest(kind: .drop, playerID: "12620")
        await tools.load(scope: "other-owner") {
            #expect(tools.context == nil && tools.selected == nil)
            return context
        }
        #expect(tools.context == nil && tools.error != nil)
        #expect(!tools.canPerform(.drop, scope: "other-owner"))
    }

    @Test("Late roster reads cannot overwrite a newer owner")
    func rosterToolLateRead() async throws {
        let tools = RosterToolsModel()
        let original = try await DemoLeagueRepository().loadRosterActionContext()
        var next = original
        next.scope = "other-owner"; next.ownerID = "0002"
        var gate: CheckedContinuation<RosterActionContext, Never>?
        let oldRead = Task { await tools.load(scope: original.scope) {
            await withCheckedContinuation { gate = $0 }
        } }
        while gate == nil { await Task.yield() }
        await tools.load(scope: next.scope) { next }
        gate?.resume(returning: original)
        await oldRead.value
        #expect(tools.context == next)
        #expect(tools.canPerform(.drop, scope: next.scope))
        #expect(!tools.canPerform(.drop, scope: original.scope))
    }

    @Test("A newer same-owner roster revision supersedes an in-flight read")
    func rosterToolSameOwnerRevision() async throws {
        let tools = RosterToolsModel()
        let original = try await DemoLeagueRepository().loadRosterActionContext()
        var updated = original
        updated.membership["12620"] = "INJURED_RESERVE"
        var gate: CheckedContinuation<RosterActionContext, Never>?
        let oldRead = Task { await tools.load(scope: original.scope) {
            await withCheckedContinuation { gate = $0 }
        } }
        while gate == nil { await Task.yield() }
        await tools.load(scope: updated.scope) { updated }
        gate?.resume(returning: original)
        await oldRead.value
        #expect(tools.context == updated)
        #expect(!tools.isLoading)
    }

    @Test("The native team tab uses a small original-rendering logo or readable fallback")
    func tabArtwork() {
        let fallback = TeamTabArtwork.image(abbreviation: "UB")
        #expect(fallback.size == CGSize(width: 26, height: 26))
        #expect(fallback.renderingMode == .alwaysOriginal)
        #expect(TeamTabArtwork.image(abbreviation: " ").size == fallback.size)
        if let pixels = fallback.cgImage {
            let loaded = TeamTabArtwork.image(abbreviation: "UB", artwork: pixels)
            #expect(loaded.size == fallback.size && loaded.renderingMode == .alwaysOriginal)
        }
    }

    @Test("Canonical browse routes include season, league and owner scope")
    func routeScope() {
        func workspace(season: Int = 2026, owner: String = "0001") -> LeagueWorkspace {
            LeagueWorkspace(leagueID: "41333", season: season, leagueName: "Synthetic",
                            franchiseID: owner, franchiseName: "Synthetic owner",
                            baseURL: URL(string: "https://www45.myfantasyleague.com")!, week: 1)
        }
        let scope = LeagueBrowseScope(workspace: workspace())
        #expect(scope != LeagueBrowseScope(workspace: workspace(season: 2027)))
        #expect(scope != LeagueBrowseScope(workspace: workspace(owner: "0002")))
        #expect(TeamRoute(scope: scope, franchiseID: "0002", initialSection: .roster)
                != TeamRoute(scope: scope, franchiseID: "0002", initialSection: .schedule))
        #expect(PlayerRoute(scope: scope, playerID: "00042", inspectedWeek: 1)
                != PlayerRoute(scope: scope, playerID: "00042", inspectedWeek: 2))
    }

    @Test("Roster, player and other-week scoring reads preserve lineup, score selection and trade drafts")
    func draftIsolation() async throws {
        let app = AppModel(repository: DemoLeagueRepository(), privateStore: MemoryPrivateStore())
        let starter = try #require(app.lineup.starters.first)
        app.toggleStarter(starter.id)
        let draft = app.lineup
        let scores = app.scores
        let week = app.selectedWeek
        var trade = TradeDraft()
        trade.partnerID = "0002"
        trade.comments = "Synthetic saved draft"
        app.transactions.saveDraft(trade)
        let teams = try await app.loadTeams()
        #expect(!teams.isEmpty)
        _ = try await app.loadTeamRoster(franchiseID: teams[0].id, lineupWeek: week)
        _ = try await app.loadPlayerDetail(playerID: starter.id)
        _ = try await app.loadMatchupScores(week: week + 1)
        #expect(app.selectedWeek == week)
        #expect(app.lineup == draft && app.scores == scores)
        #expect(app.transactions.draft == trade)
    }

    @Test("A late team read from a replaced session cannot publish even when its franchise scope matches")
    func staleAccountRead() async throws {
        let repository = BrowseGateRepository()
        let app = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        await app.signIn(credentials: LoginCredentials())
        let originalScope = try #require(app.browseScope)
        let read = Task { try await app.loadTeams() }
        while !(await repository.started) { await Task.yield() }
        await app.continueInDemo()
        #expect(app.browseScope == originalScope)
        await repository.complete()
        do {
            _ = try await read.value
            Issue.record("A replaced session published its team metadata")
        } catch is CancellationError {
            #expect(app.teams.isEmpty)
        }
    }

    @Test("Schedule detail resolves a unique pair without changing the scoring week")
    func uniqueMatchup() throws {
        let match = try #require(SampleData.scores.featuredMatchup)
        let schedule = schedule(matches: [wireGame(match)], week: SampleData.scores.week)
        let game = try #require(schedule.weeks.first?.matchups.first)
        #expect(ScheduleMatchupDetailModel.matchingGame(game, in: SampleData.scores, schedule: schedule)?.id == match.id)
        var otherWeek = SampleData.scores
        otherWeek.week += 1
        #expect(ScheduleMatchupDetailModel.matchingGame(game, in: otherWeek, schedule: schedule) == nil)
    }

    @Test("Duplicate schedule pairs never guess a scoring game; a proven source ID can disambiguate")
    func duplicateMatchupSafety() throws {
        let match = try #require(SampleData.scores.featuredMatchup)
        let duplicate = schedule(matches: [wireGame(match), wireGame(match)], week: SampleData.scores.week)
        let game = try #require(duplicate.weeks.first?.matchups.first)
        #expect(ScheduleMatchupDetailModel.matchingGame(game, in: SampleData.scores, schedule: duplicate) == nil)
        let identified = schedule(matches: [wireGame(match, id: match.id), wireGame(match, id: "other-game")],
                                  week: SampleData.scores.week)
        let exact = try #require(identified.weeks.first?.matchups.first)
        #expect(ScheduleMatchupDetailModel.matchingGame(exact, in: SampleData.scores, schedule: identified)?.id == match.id)
        let repeatedID = schedule(matches: [wireGame(match, id: match.id), wireGame(match, id: match.id)],
                                  week: SampleData.scores.week)
        let ambiguous = try #require(repeatedID.weeks.first?.matchups.first)
        #expect(ScheduleMatchupDetailModel.matchingGame(ambiguous, in: SampleData.scores, schedule: repeatedID) == nil)
    }

    private func wireGame(_ match: Matchup, id: String? = nil) -> MFLScheduleMatchup {
        MFLScheduleMatchup(id: id, franchises: [
            MFLScheduleFranchise(franchiseID: match.away.id, isHome: false),
            MFLScheduleFranchise(franchiseID: match.home.id, isHome: true)
        ])
    }

    private func schedule(matches: [MFLScheduleMatchup], week: Int) -> SeasonScheduleSnapshot {
        SeasonScheduleSnapshot(source: MFLSchedule(weeks: [MFLScheduleWeek(week: week, matchups: matches)]),
                               season: 2026, leagueID: "41333", currentWeek: week, completedWeek: week - 1)
    }
}

private actor BrowseGateRepository: LeagueRepository {
    let demo = DemoLeagueRepository()
    private(set) var started = false
    private var continuation: CheckedContinuation<[TeamSummary], Never>?

    func loadTeams(refresh: Bool) async throws -> [TeamSummary] {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func complete() {
        continuation?.resume(returning: [TeamSummary(id: "0001", name: "Old session", abbreviation: "OLD")])
        continuation = nil
    }
    func signIn(with credentials: LoginCredentials) async throws -> LeagueWorkspace { SampleData.workspace }
    func loadWorkspace() async throws -> LeagueWorkspace { try await demo.loadWorkspace() }
    func loadScores(week: Int) async throws -> ScoresSnapshot { try await demo.loadScores(week: week) }
    func loadLineup(week: Int) async throws -> LineupSnapshot { try await demo.loadLineup(week: week) }
    func submitLineup(_ lineup: LineupSnapshot) async throws { try await demo.submitLineup(lineup) }
    func loadWaivers() async throws -> WaiverSnapshot { try await demo.loadWaivers() }
    func submitWaivers(_ claims: [WaiverClaim], replacing baseline: [WaiverClaim]) async throws { try await demo.submitWaivers(claims, replacing: baseline) }
    func loadStandings() async throws -> [StandingRow] { try await demo.loadStandings() }
    func loadBoard() async throws -> [BoardThread] { try await demo.loadBoard() }
    func loadThread(id: String) async throws -> BoardThread { try await demo.loadThread(id: id) }
    func postMessage(subject: String?, body: String, threadID: String?) async throws { try await demo.postMessage(subject: subject, body: body, threadID: threadID) }
    func signOut() async { await demo.signOut() }
}
