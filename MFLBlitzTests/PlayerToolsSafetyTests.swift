import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

struct PlayerToolsSafetyTests {
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

    @Test("Roster races, acquisition locks, denied permissions and duplicate-player formats fail before POST", arguments: ["race", "locked", "closed", "duplicate"])
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
        let next = try await repository.loadPlayerResearch(playerID: "201", beforeWeek: initial.nextBeforeWeek, contextWeek: 7)
        #expect(next.weeks.map(\.week) == [2, 1] && next.nextBeforeWeek == nil)
        let queries = await server.reads.filter { $0["TYPE"] == "playerScores" }
        #expect(queries.count == 8 && queries.allSatisfy { $0["PLAYERS"] == "201" })
        #expect(!queries.contains { $0["W"] == "7" })
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
            return try response(["mfl_status": ["year": "2026", "weeks": ["CurrentWeek": 7, "LineupWeek": 7, "CompletedWeek": 6, "LiveScoringWeek": 7]]])
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
        case "playerRosterStatus": return try response(["playerRosterStatuses": ["playerStatus": ["id": "301", "is_fa": "1", "cant_add": "0", "locked": mode == "locked" ? "1" : "0"]]])
        case "injuries": return try response(["injuries": ["week": query["W"] ?? "7", "injury": ["id": "201", "status": mode == "questionable" ? "Questionable" : "Out"]]])
        case "nflByeWeeks": return try response(["nflByeWeeks": ["year": "2026", "team": ["id": "CHI", "bye_week": "2"]]])
        case "nflSchedule": return try response(["nflSchedule": ["week": query["W"] ?? "1", "matchup": ["kickoff": "1788999600", "team": [["id": "CHI", "isHome": "1"], ["id": "DET", "isHome": "0"]]]]])
        case "playerScores": return try response(["playerScores": ["week": query["W"] ?? "1", "playerScore": ["id": "201", "score": query["W"] == "5" ? "" : "0"]]])
        case "pointsAllowed": return try response(["pointsAllowed": [:]])
        case "myWatchList": return try response(["myWatchList": ["player": watched.sorted().map { ["id": $0] }]])
        default: return try await fallback.send(request)
        }
    }
}
