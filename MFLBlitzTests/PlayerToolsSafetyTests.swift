import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

struct PlayerToolsSafetyTests {
    @Test("IR controls require a current matching injury report and an eligible designation") @MainActor
    func irControlEligibility() async {
        let model = PlayerToolsModel(), now = Date()
        model.reset(scope: "s")
        #expect(model.irIneligibilityReason(playerID: "201", week: 1) != nil)
        #expect(model.irAvailabilityIssue(week: 1) != nil)
        for designation in ["Out", "IR", "Questionable", "Doubtful", "Suspended", "Unknown", ""] {
            var snapshot = PlayerAvailabilitySnapshot(scope: "s", week: 1)
            snapshot.fetchedAt = now
            snapshot.injuries["201"] = PlayerHealth(status: designation)
            await model.loadAvailability(week: 1, refresh: true) {
                #expect(model.irIneligibilityReason(playerID: "201", week: 1) != nil)
                return snapshot
            }
            #expect((model.irIneligibilityReason(playerID: "201", week: 1, now: now) == nil) == ["Out", "IR"].contains(designation))
            #expect(model.irAvailabilityIssue(week: 1, now: now) == nil)
            #expect(model.irIneligibilityReason(playerID: "201", week: 2) != nil)
            #expect(model.irIneligibilityReason(playerID: "202", week: 1) != nil)
        }
        var eligible = PlayerAvailabilitySnapshot(scope: "s", week: 1)
        eligible.injuries["201"] = PlayerHealth(status: "Out")
        eligible.fetchedAt = now
        await model.loadAvailability(week: 1, refresh: true) { eligible }
        #expect(model.irIneligibilityReason(playerID: "201", week: 1, now: now.addingTimeInterval(901)) != nil)
        await model.loadAvailability(week: 1, refresh: true) { throw RepositoryError.server("unavailable") }
        #expect(model.irAvailabilityIssue(week: 1) == "IR eligibility unavailable")
        #expect(model.irIneligibilityReason(playerID: "201", week: 1) != nil)
        model.reset(scope: "another")
        #expect(model.irIneligibilityReason(playerID: "201", week: 1) != nil)
    }

    @Test("Missing roster status is not authoritative enough for write review")
    func missingMembershipStatus() throws {
        let data = Data(#"{"franchise":{"id":"0001","player":{"id":"101"}}}"#.utf8)
        let roster = try JSONDecoder().decode(MFLRosterCollection.self, from: data)
        #expect(throws: (any Error).self) { try LiveMFLRepository.uniqueMembership(roster, owner: "0001") }
    }

    @Test("Points allowed uses verified position totals, preserving zero and omitting duplicates")
    func allowedTotals() throws {
        let data = Data(#"{"pointsAllowed":{"team":{"id":"DET","position":[{"name":"QB","points":"414.5"},{"name":"RB","points":"0"},{"name":"WR","points":"1"},{"name":"WR","points":"2"}]}}}"#.utf8)
        let value = try JSONDecoder().decode(MFLJSONValue.self, from: data)
        #expect(LiveMFLRepository.pointsAllowed(value, opponent: "DET", position: "QB") == 414.5)
        #expect(LiveMFLRepository.pointsAllowed(value, opponent: "DET", position: "RB") == 0)
        #expect(LiveMFLRepository.pointsAllowed(value, opponent: "DET", position: "WR") == nil)
        #expect(LiveMFLRepository.pointsAllowed(value, opponent: "CHI", position: "QB") == nil)
    }

    @Test("Unconfirmed watchlist toggles persist and cannot be repeated after relaunch")
    func watchTimeout() async throws {
        let server = PlayerToolsFixtureServer(), store = MemoryPrivateStore()
        let repository = try await connected(server, store: store)
        await server.configure("timeoutBefore")
        #expect(try await repository.setWatched(playerID: "301", isWatched: true).pending != nil)
        let restored = try await connected(server, store: store)
        #expect(try await restored.loadWatchList(refresh: true).pending != nil)
        await #expect(throws: (any Error).self) { try await restored.setWatched(playerID: "301", isWatched: true) }
        #expect(await server.posts.count == 1)
        try await restored.acknowledgeWatchList()
        #expect(try await restored.loadWatchList(refresh: true).pending == nil)
        #expect(await server.posts.count == 1)
    }

    @Test("Unrecognized, denied and contradictory capabilities never grant roster writes")
    func capabilities() throws {
        func allowed(_ json: String) throws -> Set<RosterActionKind> {
            RosterAbilityPolicy.allowed(try JSONDecoder().decode(MFLJSONValue.self, from: Data(json.utf8)), ownerID: "0001")
        }
        #expect(try allowed(#"{"abilities":{"franchise":{"id":"0001","ability":[{"id":"WAIVERS","value":"1","desc":"Perform Add/Drops"},{"id":"DROP","value":"1"},{"id":"INJURED_RESERVE","value":"1"}]}}}"#) == Set(RosterActionKind.allCases))
        #expect(try allowed(#"{"abilities":{"franchise":{"id":"0002","ability":{"id":"WAIVERS","value":"1"}}}}"#).isEmpty)
        #expect(try allowed(#"{"abilities":{"franchise":{"id":"0001","ability":[{"id":"WAIVERS","value":"1"},{"id":"WAIVERS","value":"0"},{"id":"FUTURE","value":"1"}]}}}"#).isEmpty)
        #expect(try allowed(#"{"abilities":{"franchise":{"id":"0001","ability":{"id":"INJURED_RESERVE","value":"maybe"}}}}"#).isEmpty)
    }

    @Test("Review calculates capacity and exact target membership without mutating the baseline")
    func impact() {
        let baseline = RosterActionContext(scope: "s", ownerID: "0001", players: [],
            membership: ["101": "ROSTER", "102": "ROSTER", "103": "INJURED_RESERVE"],
            activeLimit: 2, irLimit: 1, allowed: Set(RosterActionKind.allCases))
        #expect(baseline.problem(for: .init(kind: .reserve, playerID: "101")) == "Your IR is full.")
        #expect(baseline.problem(for: .init(kind: .activate, playerID: "103")) != nil)
        let activation = RosterActionRequest(kind: .activate, playerID: "103", dropID: "102")
        #expect(baseline.problem(for: activation) == nil)
        #expect(baseline.expectedMembership(after: activation) == ["101": "ROSTER", "103": "ROSTER"])
        #expect(baseline.membership["102"] == "ROSTER")
        #expect(baseline.problem(for: .init(kind: .add, playerID: "301", dropID: "103")) != nil)
    }

    @Test("FCFS is submitted once, confirmed by membership, and retains unrelated players")
    func addDrop() async throws {
        let server = PlayerToolsFixtureServer()
        let repository = try await connected(server)
        let reviewed = try await repository.loadRosterActionContext()
        let receipt = try await repository.performRosterAction(.init(kind: .add, playerID: "301", dropID: "202"), reviewed: reviewed)
        #expect(receipt.confirmed)
        #expect(await server.membership == ["201": "ROSTER", "301": "ROSTER"])
        #expect(await server.posts.count == 1)
        #expect(try await repository.pendingRosterAction() == nil)
    }

    @Test("Roster races, acquisition restrictions, denied permissions and duplicate-player formats fail before POST", arguments: ["race", "locked", "closed", "duplicate", "cantAdd", "invalidLock", "owned"])
    func preflight(mode: String) async throws {
        let server = PlayerToolsFixtureServer()
        let repository = try await connected(server)
        let baseline = try await repository.loadRosterActionContext()
        await server.configure(mode)
        await #expect(throws: (any Error).self) {
            try await repository.performRosterAction(.init(kind: .add, playerID: "301", dropID: "202"), reviewed: baseline)
        }
        #expect(await server.posts.isEmpty)
        #expect(try await repository.pendingRosterAction() == nil)
    }

    @Test("A timeout survives relaunch, blocks another mutation, and reconciles without replay")
    func durableUncertainty() async throws {
        let server = PlayerToolsFixtureServer(), store = MemoryPrivateStore()
        let repository = try await connected(server, store: store)
        let baseline = try await repository.loadRosterActionContext()
        await server.configure("timeoutBefore")
        let request = RosterActionRequest(kind: .add, playerID: "301", dropID: "202")
        #expect(try await !repository.performRosterAction(request, reviewed: baseline).confirmed)
        #expect(try await repository.pendingRosterAction() != nil)
        let restored = try await connected(server, store: store)
        #expect(try await restored.pendingRosterAction() != nil)
        await #expect(throws: (any Error).self) { try await restored.performRosterAction(request, reviewed: baseline) }
        await #expect(throws: (any Error).self) { try await restored.submitLineup(SampleData.lineup) }
        #expect(await server.posts.count == 1)
        await server.applyDelayedAdd()
        #expect(try await restored.reconcileRosterAction().confirmed)
        #expect(try await restored.pendingRosterAction() == nil)
        #expect(await server.posts.count == 1)
    }

    @Test("A lost response after a successful add is confirmed from fresh membership")
    func appliedTimeout() async throws {
        let server = PlayerToolsFixtureServer()
        let repository = try await connected(server)
        let baseline = try await repository.loadRosterActionContext()
        await server.configure("timeoutAfter")
        #expect(try await repository.performRosterAction(.init(kind: .add, playerID: "301", dropID: "202"), reviewed: baseline).confirmed)
        #expect(await server.posts.count == 1)
    }

    @Test("Two synthetic game weeks: watch research, move Out player to IR, add, then activate with an explicit drop")
    func twoWeekJourney() async throws {
        let server = PlayerToolsFixtureServer()
        let repository = try await connected(server)
        let first = try await repository.loadPlayerAvailability(week: 1, refresh: false)
        #expect(first.games["CHI"]?.opponent == "DET" && first.injuries["201"]?.status == "Out")
        #expect(first.byeWeeks["CHI"] == 2)
        _ = try await repository.setWatched(playerID: "301", isWatched: true)
        #expect(try await repository.loadWatchList(refresh: true).playerIDs == ["201", "301"])
        let reserve = try await repository.loadRosterActionContext()
        #expect(try await repository.performRosterAction(.init(kind: .reserve, playerID: "201"), reviewed: reserve).confirmed)
        let add = try await repository.loadRosterActionContext()
        #expect(try await repository.performRosterAction(.init(kind: .add, playerID: "301"), reviewed: add).confirmed)
        let weekTwo = try await repository.loadPlayerAvailability(week: 2, refresh: false)
        #expect(weekTwo.byeWeeks["CHI"] == weekTwo.week)
        let activate = try await repository.loadRosterActionContext()
        await #expect(throws: (any Error).self) {
            try await repository.performRosterAction(.init(kind: .activate, playerID: "201"), reviewed: activate)
        }
        #expect(try await repository.performRosterAction(.init(kind: .activate, playerID: "201", dropID: "202"), reviewed: activate).confirmed)
        #expect(await server.membership == ["201": "ROSTER", "301": "ROSTER"])
        _ = try await repository.setWatched(playerID: "301", isWatched: false)
        #expect(try await repository.loadWatchList(refresh: true).playerIDs == ["201"])
        #expect(await server.posts.filter { $0["TYPE"] == "ir" }.count == 2)
    }

    @Test("Questionable is not sufficient for the supported IR path")
    func injuryGuard() async throws {
        let server = PlayerToolsFixtureServer()
        let repository = try await connected(server)
        let baseline = try await repository.loadRosterActionContext()
        await server.configure("questionable")
        await #expect(throws: (any Error).self) { try await repository.performRosterAction(.init(kind: .reserve, playerID: "201"), reviewed: baseline) }
        #expect(await server.posts.isEmpty)
    }

    @Test("Research loads at most four completed weeks per page and preserves real zero vs missing")
    func researchBudget() async throws {
        let server = PlayerToolsFixtureServer()
        let repository = try await connected(server)
        let initial = try await repository.loadPlayerResearch(playerID: "201", beforeWeek: nil, contextWeek: 7)
        #expect(initial.weeks.map(\.week) == [6, 5, 4, 3])
        #expect(initial.weeks.first?.points == 0 && initial.weeks[1].points == nil)
        #expect(initial.nextBeforeWeek == 3)
        #expect(initial.total == nil && initial.average == nil && initial.opponentPointsAllowed == nil)
        let firstQueries = await server.reads.filter { $0["TYPE"] == "playerScores" }
        #expect(firstQueries.count == 4)
        _ = try await repository.loadPlayerResearch(playerID: "201", beforeWeek: nil, contextWeek: 7)
        #expect(await server.reads.filter { $0["TYPE"] == "playerScores" }.count == 4)
        let next = try await repository.loadPlayerResearch(playerID: "201", beforeWeek: initial.nextBeforeWeek, contextWeek: 7)
        #expect(next.weeks.map(\.week) == [2, 1] && next.nextBeforeWeek == nil)
        let queries = await server.reads.filter { $0["TYPE"] == "playerScores" }
        #expect(queries.count == 6 && queries.allSatisfy { $0["PLAYERS"] == "201" })
        #expect(!queries.contains { $0["W"] == "7" })
        #expect(!queries.contains { ["YTD", "AVG"].contains($0["W"] ?? "") })
        #expect(await !server.reads.contains { ["pointsAllowed", "injuries"].contains($0["TYPE"] ?? "") })
        let schedules = await server.reads.filter { $0["TYPE"] == "nflSchedule" }
        #expect(schedules.count == 1 && schedules.first?["W"] == "ALL")
        #expect(await server.reads.filter { $0["TYPE"] == "nflByeWeeks" }.count == 1)
        #expect(initial.scheduleTeam == "CHI")
        #expect(initial.weeks.map(\.opponentLabel) == ["vs DET", "@ DET", "vs DET", "@ DET"])
        #expect(next.weeks.map(\.opponentLabel) == ["Bye", "@ DET"])
        _ = try await repository.loadPlayerResearch(playerID: "202", beforeWeek: nil, contextWeek: 7)
        #expect(await server.reads.filter { $0["TYPE"] == "nflSchedule" }.count == 1)
        #expect(await server.reads.filter { $0["TYPE"] == "nflByeWeeks" }.count == 1)
    }

    @Test("Season summary needs only two targeted cached reads, independently of game history")
    func seasonSummaryBudget() async throws {
        let server = PlayerToolsFixtureServer()
        let repository = try await connected(server)
        let baseline = await server.reads.count
        let summary = try await repository.loadPlayerSeasonSummary(playerID: "201")
        #expect(summary.total == 0 && summary.average == 0 && summary.issues.isEmpty)
        #expect(summary.playerID == "201")
        let queries = await Array(server.reads.dropFirst(baseline))
        #expect(queries.count == 2)
        #expect(queries.allSatisfy { $0["TYPE"] == "playerScores" && $0["PLAYERS"] == "201" })
        #expect(Set(queries.compactMap { $0["W"] }) == ["YTD", "AVG"])
        #expect(try await repository.loadPlayerSeasonSummary(playerID: "201") == summary)
        #expect(await server.reads.count == baseline + 2)
        _ = try await repository.loadPlayerResearch(playerID: "201", beforeWeek: nil, contextWeek: 7)
        #expect(await server.reads.filter { $0["TYPE"] == "playerScores" }.count == 6)
    }

    @Test("Missing and failed season values stay distinct from actual zero, including preseason",
          arguments: ["summaryMissing", "summaryUnavailable", "preseason"])
    func seasonSummaryMissingValues(mode: String) async throws {
        let server = PlayerToolsFixtureServer()
        await server.configure(mode)
        let repository = try await connected(server)
        let summary = try await repository.loadPlayerSeasonSummary(playerID: "201")
        if mode == "summaryUnavailable" {
            #expect(summary.total == 0 && summary.average == nil)
            #expect(summary.issues == ["Weekly average could not be refreshed."])
        } else {
            #expect(summary.total == nil && summary.average == nil)
            #expect(summary.issues.isEmpty)
        }
        #expect(await server.reads.filter { $0["TYPE"] == "playerScores" }.count == 2)
    }

    @Test("Game log distinguishes a failed week from a missing score and never fetches future weeks")
    func gameLogFailureAndPreseason() async throws {
        let server = PlayerToolsFixtureServer()
        await server.configure("historyUnavailable")
        let repository = try await connected(server)
        let page = try await repository.loadPlayerResearch(playerID: "201", beforeWeek: nil, contextWeek: 7)
        #expect(page.weeks.map(\.week) == [6, 5, 4, 3])
        #expect(page.weeks[0].points == 0 && !page.weeks[0].unavailable)
        #expect(page.weeks[1].points == nil && !page.weeks[1].unavailable)
        #expect(page.weeks[2].points == nil && page.weeks[2].unavailable)
        #expect(await server.reads.filter { $0["TYPE"] == "playerScores" }.count == 4)

        let preseasonServer = PlayerToolsFixtureServer()
        await preseasonServer.configure("preseason")
        let preseasonRepository = try await connected(preseasonServer)
        let empty = try await preseasonRepository.loadPlayerResearch(playerID: "201", beforeWeek: nil, contextWeek: 1)
        #expect(empty.completedWeek == 0 && empty.weeks.isEmpty && empty.nextBeforeWeek == nil)
        #expect(await !preseasonServer.reads.contains { $0["TYPE"] == "playerScores" })
    }

    @Test("Missing or malformed shared NFL schedule leaves game-log scores intact",
          arguments: ["scheduleUnavailable", "scheduleDuplicate", "scheduleMissingWeek"])
    func gameLogScheduleFallback(mode: String) async throws {
        let server = PlayerToolsFixtureServer()
        await server.configure(mode)
        let repository = try await connected(server)
        let page = try await repository.loadPlayerResearch(playerID: "201", beforeWeek: nil, contextWeek: 7)
        #expect(page.weeks.count == 4 && page.weeks.first?.points == 0)
        #expect(page.weeks.allSatisfy { $0.opponentLabel == nil })
        #expect(page.issues.contains("Opponent schedule unavailable."))
        #expect(await server.reads.filter { $0["TYPE"] == "nflSchedule" }.count == 1)
        #expect(await server.reads.filter { $0["TYPE"] == "playerScores" }.count == 4)
    }

    @Test("History opponents distinguish home, away, confirmed bye and ambiguous or absent games")
    func gameLogOpponentLabels() throws {
        let json = #"{"fullNflSchedule":{"nflSchedule":[{"week":"1","matchup":{"team":[{"id":"CHI","isHome":"1"},{"id":"DET","isHome":"0"}]}},{"week":"2","matchup":[]},{"week":"3","matchup":{"team":[{"id":"CHI","isHome":"0"},{"id":"DET","isHome":"1"}]}},{"week":"4","matchup":{"team":[{"id":"CHI"},{"id":"DET"}]}},{"week":"5","matchup":[{"team":[{"id":"CHI"},{"id":"DET"}]},{"team":[{"id":"CHI"},{"id":"MIN"}]}]},{"week":"6","matchup":{"team":[{"id":"CHI","isHome":"1"},{"id":"DET","isHome":"1"}]}},{"week":"7","matchup":{"team":[{"id":"CHI"},{"id":"CHI"}]}},{"week":"8","matchup":{"team":{"id":"CHI"}}},{"week":"9","matchup":{"team":[{"id":"DAL"},{"id":"DET"}]}}]}}"#
        let schedule = try JSONDecoder().decode(MFLNFLSeasonScheduleResponse.self, from: Data(json.utf8)).fullNflSchedule
        let byes = try JSONDecoder().decode(MFLByeWeeksResponse.self,
            from: Data(#"{"nflByeWeeks":{"team":{"id":"CHI","bye_week":"2"}}}"#.utf8)).nflByeWeeks
        func label(_ week: Int) -> String? {
            LiveMFLRepository.historyOpponentLabel(teamID: "CHI", week: week, schedule: schedule, byes: byes)
        }
        #expect(label(1) == "vs DET" && label(2) == "Bye" && label(3) == "@ DET" && label(4) == "DET")
        for week in 5...10 { #expect(label(week) == nil) }
        #expect(LiveMFLRepository.historyOpponentLabel(teamID: "CHI", week: 2, schedule: schedule, byes: nil) == nil)
        #expect(LiveMFLRepository.historyOpponentLabel(teamID: "CHI", week: 2, schedule: nil, byes: byes) == nil)
        let conflict = try JSONDecoder().decode(MFLByeWeeksResponse.self,
            from: Data(#"{"nflByeWeeks":{"team":{"id":"CHI","bye_week":"1"}}}"#.utf8)).nflByeWeeks
        #expect(LiveMFLRepository.historyOpponentLabel(teamID: "CHI", week: 1, schedule: schedule, byes: conflict) == nil)
    }

    @Test("Season summary model caches success, retains same-player data on failure, and rejects wrong identities") @MainActor
    func seasonSummaryState() async {
        let model = PlayerSeasonSummaryModel()
        let summary = PlayerSeasonSummary(scope: "s", playerID: "201", total: 0, average: 0)
        var calls = 0
        await model.load(scope: "s", playerID: "201") { calls += 1; return summary }
        await model.load(scope: "s", playerID: "201") { calls += 1; return summary }
        #expect(calls == 1 && model.summary == summary && !model.isLoading)
        await model.load(scope: "s", playerID: "201", force: true) { throw RepositoryError.server("offline") }
        #expect(model.summary == summary && model.errorMessage == "offline" && !model.isLoading)
        await model.load(scope: "other", playerID: "202") { summary }
        #expect(model.summary == nil && model.errorMessage != nil && !model.isLoading)
        await model.load(scope: "s", playerID: "202") { summary }
        #expect(model.summary == nil && model.errorMessage != nil && !model.isLoading)
    }

    @Test("Cancelled or superseded season reads cannot repopulate a new player or account") @MainActor
    func seasonSummaryScopeIsolation() async {
        let model = PlayerSeasonSummaryModel()
        let old = PlayerSeasonSummary(scope: "old", playerID: "201", total: 12, average: 6)
        let current = PlayerSeasonSummary(scope: "new", playerID: "202", total: 9, average: 3)
        await model.load(scope: "old", playerID: "201") {
            await model.load(scope: "new", playerID: "202") { current }
            return old
        }
        #expect(model.summary == current && model.errorMessage == nil && !model.isLoading)
        await model.load(scope: "old", playerID: "201") {
            await model.load(scope: "new", playerID: "202") { current }
            throw RepositoryError.server("Late failure")
        }
        #expect(model.summary == current && model.errorMessage == nil && !model.isLoading)
        await model.load(scope: "old", playerID: "201") {
            model.invalidate()
            return old
        }
        #expect(model.summary == nil && model.errorMessage == nil && !model.isLoading)
        await model.load(scope: "old", playerID: "201") { throw CancellationError() }
        #expect(model.summary == nil && model.errorMessage == nil && !model.isLoading)
    }

    @Test("Cancelled old-session secondary reads cannot repopulate current state") @MainActor
    func scopeIsolation() async throws {
        let model = PlayerToolsModel()
        model.reset(scope: "old")
        await model.loadAvailability(week: 1, refresh: false) {
            model.reset(scope: "new")
            return PlayerAvailabilitySnapshot(scope: "old", week: 1)
        }
        #expect(model.availability.isEmpty && model.scope == "new")
        await model.loadWatchList(refresh: true) {
            model.reset(scope: "next")
            return WatchListSnapshot(scope: "new", players: [])
        }
        #expect(model.watchList == nil && !model.isLoadingWatchList)
    }

    private func connected(_ server: PlayerToolsFixtureServer, store: MemoryPrivateStore = MemoryPrivateStore()) async throws -> LiveMFLRepository {
        try store.encode(SavedSession(cookie: "synthetic", season: 2026, leagueID: "41333", franchiseID: "0001"), key: "session")
        let repository = LiveMFLRepository(privateStore: store, transport: server, requestInterval: .zero)
        _ = try await repository.restoreSession()
        return repository
    }
}

/// Stateful synthetic server; abilities use the owner-verified response shape.
private actor PlayerToolsFixtureServer: MFLHTTPTransport {
    private let fallback = MutationFixtureTransport()
    var membership = ["201": "ROSTER", "202": "ROSTER"]
    var watched: Set<String> = ["201"]
    var posts: [[String: String]] = []
    var reads: [[String: String]] = []
    var mode = "normal"
    func configure(_ mode: String) { self.mode = mode; if mode == "race" { membership["202"] = nil } }
    func applyDelayedAdd() { membership["202"] = nil; membership["301"] = "ROSTER"; mode = "normal" }
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        var formComponents = URLComponents()
        formComponents.percentEncodedQuery = String(data: request.httpBody ?? Data(), encoding: .utf8)?.replacingOccurrences(of: "+", with: "%20")
        let form = Dictionary(uniqueKeysWithValues: (formComponents.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            .merging(query, uniquingKeysWith: { old, _ in old })
        func response(_ object: [String: Any]) throws -> MFLHTTPResponse {
            MFLHTTPResponse(data: try JSONSerialization.data(withJSONObject: object), statusCode: 200, url: request.url)
        }
        if request.httpMethod == "POST" {
            posts.append(form)
            if mode == "timeoutBefore" { throw URLError(.timedOut) }
            switch form["TYPE"] {
            case "myWatchList":
                if let add = form["ADD"] { watched.insert(add) }
                if let remove = form["REMOVE"] { watched.remove(remove) }
            case "fcfsWaiver":
                if let add = form["ADD"] { membership[add] = "ROSTER" }
                if let drop = form["DROP"] { membership[drop] = nil }
            case "ir":
                if let activate = form["ACTIVATE"] { membership[activate] = "ROSTER" }
                if let deactivate = form["DEACTIVATE"] { membership[deactivate] = "INJURED_RESERVE" }
                if let drop = form["DROP"] { membership[drop] = nil }
            default: throw MFLCoreError.invalidRequest("Unexpected fixture mutation")
            }
            if mode == "timeoutAfter" { throw URLError(.timedOut) }
            return try response(["status": "OK"])
        }
        reads.append(query)
        if request.url!.path.contains("mfl_status") {
            let current = mode == "preseason" ? 1 : 7
            return try response(["mfl_status": ["year": "2026", "weeks": ["CurrentWeek": current, "LineupWeek": current, "CompletedWeek": mode == "preseason" ? 0 : 6, "LiveScoringWeek": current]]])
        }
        switch query["TYPE"] {
        case "league":
            let original = try await fallback.send(request)
            var data = try JSONSerialization.jsonObject(with: original.data) as! [String: Any]
            var league = data["league"] as! [String: Any]
            league.merge(["rosterSize": "2", "injuredReserve": "1", "taxiSquad": "0", "currentWaiverType": "BBID_FCFS",
                "rostersPerPlayer": mode == "duplicate" ? "2" : "1", "playerLimitUnit": "LEAGUE", "usesSalaries": "0", "usesContractYear": "0"], uniquingKeysWith: { _, new in new })
            data["league"] = league
            return try response(data)
        case "abilities": return try response(["abilities": ["franchise": ["id": "0001", "ability": [
            ["id": "WAIVERS", "value": mode == "closed" ? "0" : "1"],
            ["id": "DROP", "value": "1"], ["id": "INJURED_RESERVE", "value": "1"]]]]])
        case "players": return try response(["players": ["player": ["201", "202", "301"].map { ["id": $0, "name": "Player, \($0)", "position": "RB", "team": "CHI"] }]])
        case "rosters": return try response(["rosters": ["franchise": ["id": "0001", "player": membership.map { ["id": $0.key, "status": $0.value] }]]])
        case "freeAgents": return try response(["freeAgents": ["player": [["id": "301"]]]])
        case "playerRosterStatus":
            var status: [String: Any] = ["id": "301", "is_fa": "1"]
            if mode == "locked" { status["locked"] = "1" }
            if mode == "cantAdd" { status["cant_add"] = "1" }
            if mode == "invalidLock" { status["locked"] = "unknown" }
            if mode == "owned" { status = ["id": "301", "roster_franchise": ["franchise_id": "0008", "status": "S"]] }
            return try response(["playerRosterStatuses": ["playerStatus": status]])
        case "injuries": return try response(["injuries": ["week": query["W"] ?? "7", "injury": ["id": "201", "status": mode == "questionable" ? "Questionable" : "Out"]]])
        case "nflByeWeeks": return try response(["nflByeWeeks": ["year": "2026", "team": ["id": "CHI", "bye_week": "2"]]])
        case "nflSchedule":
            if query["W"] == "ALL" {
                if mode == "scheduleUnavailable" { throw URLError(.notConnectedToInternet) }
                if mode == "scheduleDuplicate" {
                    return try response(["fullNflSchedule": ["nflSchedule": [["week": "1"], ["week": "1"]]]])
                }
                if mode == "scheduleMissingWeek" {
                    return try response(["fullNflSchedule": ["nflSchedule": [["matchup": []]]]])
                }
                let weeks: [[String: Any]] = (1...7).map { week in
                    let games: [[String: Any]] = week == 2 ? [] : [["team": [
                        ["id": "CHI", "isHome": week.isMultiple(of: 2) ? "1" : "0"],
                        ["id": "DET", "isHome": week.isMultiple(of: 2) ? "0" : "1"]]]]
                    return ["week": String(week), "matchup": games]
                }
                return try response(["fullNflSchedule": ["nflSchedule": weeks]])
            }
            return try response(["nflSchedule": ["week": query["W"] ?? "1", "matchup": ["kickoff": "1788999600", "team": [["id": "CHI", "isHome": "1"], ["id": "DET", "isHome": "0"]]]]])
        case "playerScores":
            if (mode == "summaryUnavailable" && query["W"] == "AVG") ||
                (mode == "historyUnavailable" && query["W"] == "4") { throw URLError(.notConnectedToInternet) }
            let missing = ["summaryMissing", "preseason"].contains(mode) || query["W"] == "5"
            return try response(["playerScores": ["week": query["W"] ?? "1", "playerScore": ["id": "201", "score": missing ? "" : "0"]]])
        case "pointsAllowed": return try response(["pointsAllowed": [:]])
        case "myWatchList": return try response(["myWatchList": ["player": watched.sorted().map { ["id": $0] }]])
        default: return try await fallback.send(request)
        }
    }
}
