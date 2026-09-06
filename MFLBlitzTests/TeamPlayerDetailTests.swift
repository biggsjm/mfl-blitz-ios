import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

struct TeamPlayerDetailTests {
    @Test("Generic and unknown assignments never imply bench, and current reserve membership wins")
    func rosterClassification() {
        let identity = PlayerIdentity(id: "101", name: "Fixture Player")
        #expect(RosterPlayerSummary(identity: identity, membership: .active).group == .roster)
        #expect(RosterPlayerSummary(identity: identity, membership: .active, lineupAssignment: .rostered).group == .roster)
        #expect(RosterPlayerSummary(identity: identity, membership: .active, lineupAssignment: .unknown("NEW")).group == .roster)
        #expect(RosterPlayerSummary(identity: identity, membership: .active, lineupAssignment: .nonstarter).group == .bench)
        #expect(RosterPlayerSummary(identity: identity, membership: .injuredReserve, lineupAssignment: .starter).group == .injuredReserve)
        #expect(RosterPlayerSummary(identity: identity, membership: .taxiSquad, lineupAssignment: .nonstarter).group == .taxiSquad)
        #expect(RosterMembership(rawValue: "FUTURE_STATE") == .unknown("FUTURE_STATE"))
    }

    @Test("Ownership keeps all assignments and franchise-scoped free agency together")
    func multipleOwnership() throws {
        let statuses = try decodeStatus(#"{"playerStatus":{"id":"101","is_fa":"1","cant_add":"0","locked":"1","roster_franchise":[{"franchise_id":"0001","status":"R"},{"franchise_id":"0002","status":"NEW"}]}}"#)
        let value = try #require(TeamPlayerMapper.ownership(statuses, playerID: "101", teams: [], availabilityFranchiseID: "0003"))
        #expect(value.assignments.map(\.team.id) == ["0001", "0002"])
        #expect(value.assignments[0].status == .rostered)
        #expect(value.assignments[1].status == .unknown("NEW"))
        #expect(value.isFreeAgent == true && value.cannotAdd == false && value.acquisitionLocked == true)
        #expect(value.availabilityFranchiseID == "0003")
    }

    @Test("Duplicate status rows or duplicate franchise assignments are unavailable, not first-match ownership")
    func ambiguousOwnership() throws {
        let duplicates = try decodeStatus(#"{"playerStatus":[{"id":"101","is_fa":"1"},{"id":"101","is_fa":"0"}]}"#)
        #expect(TeamPlayerMapper.ownership(duplicates, playerID: "101", teams: [], availabilityFranchiseID: "0001") == nil)
        #expect(TeamPlayerMapper.lineupAssignments(duplicates, franchiseID: "0001").isEmpty)
        let duplicateTeams = try decodeStatus(#"{"playerStatus":{"id":"101","roster_franchise":[{"franchise_id":"0001","status":"S"},{"franchise_id":"0001","status":"NS"}]}}"#)
        #expect(TeamPlayerMapper.ownership(duplicateTeams, playerID: "101", teams: [], availabilityFranchiseID: "0001") == nil)
        #expect(TeamPlayerMapper.lineupAssignments(duplicateTeams, franchiseID: "0001").isEmpty)
    }

    @Test("Missing ownership does not become a free agent, including singleton responses with no fields")
    func omittedOwnership() throws {
        let empty = try decodeStatus(#"{"playerStatus":[]}"#)
        #expect(TeamPlayerMapper.ownership(empty, playerID: "101", teams: [], availabilityFranchiseID: "0001") == nil)
        let omitted = try decodeStatus(#"{"playerStatus":{"id":"101"}}"#)
        let value = try #require(TeamPlayerMapper.ownership(omitted, playerID: "101", teams: [], availabilityFranchiseID: "0001"))
        #expect(value.isFreeAgent == nil && value.assignments.isEmpty && value.acquisitionLocked == nil)
    }

    @Test("Bio accepts exact calendar dates and preserves absent measurements")
    func bioValidation() throws {
        #expect(PlayerBio.parseBirthDate("2000-02-29") != nil)
        #expect(PlayerBio.parseBirthDate("02/29/2000") == PlayerBio.parseBirthDate("2000-02-29"))
        for invalid in ["2001-02-29", "03/45/2000", "not a date", "2099-01-01", "0000-00-00", ""] {
            #expect(PlayerBio.parseBirthDate(invalid) == nil)
        }
        let player = try JSONDecoder().decode(MFLPlayer.self, from: Data(#"{"id":"101","name":"Test, Player","height":" ","weight":"","birthdate":"2001-02-29","draft_round":"0"}"#.utf8))
        #expect(TeamPlayerMapper.biography(player).isEmpty)
    }

    @Test("Roster membership is current, lineup assignments use a separate explicit week, and status reads are batched")
    func rosterReadScope() async throws {
        let transport = TeamPlayerFixtureTransport()
        let repository = try await connected(transport)
        let roster = try await repository.loadTeamRoster(franchiseID: "0001", lineupWeek: 12, refresh: false)
        #expect(roster.team.name == "Fixture One")
        #expect(roster.team.ownerName == "Avery & Morgan")
        #expect(roster.players.count == 3 && roster.lineupWeek == 12)
        #expect(roster.players.first { $0.id == "101" }?.group == .starters)
        #expect(roster.players.first { $0.id == "102" }?.group == .roster)
        #expect(roster.players.first { $0.id == "103" }?.group == .injuredReserve)
        let requests = await transport.requests
        let rosters = requests.filter { $0["TYPE"] == "rosters" }
        #expect(rosters.count == 1 && rosters[0]["W"] == nil)
        let statuses = requests.filter { $0["TYPE"] == "playerRosterStatus" }
        #expect(statuses.count == 1 && statuses[0]["W"] == "12")
        #expect(Set((statuses[0]["P"] ?? "").split(separator: ",").map(String.init)) == ["101", "102", "103"])
        #expect(await transport.postCount == 0)
    }

    @Test("Roster refresh bypasses volatile data only, retaining league metadata and the shared daily directory")
    func readCaching() async throws {
        let transport = TeamPlayerFixtureTransport()
        let repository = try await connected(transport)
        let first = try await repository.loadTeamRoster(franchiseID: "0001", lineupWeek: 2, refresh: false)
        _ = try await repository.loadTeamRoster(franchiseID: "0001", lineupWeek: 2, refresh: false)
        let refreshed = try await repository.loadTeamRoster(franchiseID: "0001", lineupWeek: 2, refresh: true)
        let requests = await transport.requests
        #expect(requests.filter { $0["TYPE"] == "league" }.count == 1)
        #expect(requests.filter { $0["TYPE"] == "players" }.count == 1)
        #expect(requests.filter { $0["TYPE"] == "rosters" }.count == 2)
        #expect(requests.filter { $0["TYPE"] == "playerRosterStatus" }.count == 2)
        #expect(first.rosterVerifiedAt == nil)
        #expect(refreshed.rosterVerifiedAt != nil)
    }

    @Test("Player refresh reloads ownership only; explicit team refresh still reloads league identity")
    func detailReadCaching() async throws {
        let transport = TeamPlayerFixtureTransport()
        let repository = try await connected(transport)
        let first = try await repository.loadPlayerDetail(playerID: "101", refresh: false)
        _ = try await repository.loadPlayerDetail(playerID: "101", refresh: false)
        let refreshed = try await repository.loadPlayerDetail(playerID: "101", refresh: true)
        let requests = await transport.requests
        #expect(requests.filter { $0["TYPE"] == "league" }.count == 1)
        #expect(requests.filter { $0["TYPE"] == "players" && $0["DETAILS"] != "1" }.count == 1)
        #expect(requests.filter { $0["TYPE"] == "players" && $0["DETAILS"] == "1" }.count == 1)
        #expect(requests.filter { $0["TYPE"] == "playerRosterStatus" }.count == 2)
        #expect(first.ownershipVerifiedAt == nil)
        #expect(refreshed.ownershipVerifiedAt != nil)

        _ = try await repository.loadTeams(refresh: false)
        #expect(await transport.requests.filter { $0["TYPE"] == "league" }.count == 1)
        _ = try await repository.loadTeams(refresh: true)
        #expect(await transport.requests.filter { $0["TYPE"] == "league" }.count == 2)
        #expect(await transport.postCount == 0)
    }

    @Test("Missing or duplicate franchise rosters fail instead of reporting an empty team", arguments: ["missing", "duplicate"])
    func invalidRoster(mode: String) async throws {
        let transport = TeamPlayerFixtureTransport()
        await transport.configure(rosterMode: mode)
        let repository = try await connected(transport)
        await #expect(throws: (any Error).self) {
            try await repository.loadTeamRoster(franchiseID: "0001", lineupWeek: nil, refresh: false)
        }
    }

    @Test("Empty confirmed roster skips the forbidden empty player-status request")
    func emptyRoster() async throws {
        let transport = TeamPlayerFixtureTransport()
        await transport.configure(rosterMode: "empty")
        let repository = try await connected(transport)
        let roster = try await repository.loadTeamRoster(franchiseID: "0001", lineupWeek: 2, refresh: false)
        #expect(roster.players.isEmpty)
        #expect(await transport.requests.filter { $0["TYPE"] == "playerRosterStatus" }.isEmpty)
    }

    @Test("Optional catalog and assignment failures preserve membership without invented names or bench states")
    func partialRoster() async throws {
        let transport = TeamPlayerFixtureTransport()
        await transport.configure(failCatalog: true, failStatus: true)
        let repository = try await connected(transport)
        let roster = try await repository.loadTeamRoster(franchiseID: "0001", lineupWeek: 2, refresh: false)
        #expect(roster.players.map(\.id) == ["101", "102", "103"])
        #expect(roster.players.first?.identity.name == "Player 101")
        #expect(roster.players(in: .bench).isEmpty)
        #expect(roster.issues.contains(.playerNames) && roster.issues.contains(.lineupAssignments))
    }

    @Test("Player detail adds targeted bio while ownership stays in the current signed-in franchise context")
    func detailRead() async throws {
        let transport = TeamPlayerFixtureTransport()
        let repository = try await connected(transport)
        let detail = try await repository.loadPlayerDetail(playerID: "101", refresh: true)
        #expect(detail.identity.name == "Riley Receiver")
        #expect(detail.bio?.birthDate != nil && detail.bio?.draftRound == 2)
        #expect(detail.ownership?.assignments.map(\.team.id) == ["0001", "0002"])
        #expect(detail.ownershipVerifiedAt != nil)
        let requests = await transport.requests
        #expect(requests.contains { $0["TYPE"] == "players" && $0["DETAILS"] == "1" && $0["PLAYERS"] == "101" })
        let status = try #require(requests.first { $0["TYPE"] == "playerRosterStatus" })
        #expect(status["W"] == nil && status["F"] == "0001")
        #expect(!requests.contains { ["liveScoring", "weeklyResults", "projectedScores"].contains($0["TYPE"] ?? "") })
        #expect(await transport.postCount == 0)
    }

    @Test("Unavailable biography does not hide readable ownership")
    func partialDetail() async throws {
        let transport = TeamPlayerFixtureTransport()
        await transport.configure(failBio: true)
        let repository = try await connected(transport)
        let detail = try await repository.loadPlayerDetail(playerID: "101", refresh: false)
        #expect(detail.identity.name == "Riley Receiver")
        #expect(detail.bio == nil && detail.issues.contains(.biography))
        #expect(detail.ownership != nil)
    }

    @Test("Authentication and cancellation propagate through optional enrichment")
    func controlFlowErrors() async {
        await #expect(throws: MFLCoreError.unauthorized("Fixture expiry")) {
            let _: Int? = try await TeamPlayerMapper.optionalRead { throw MFLCoreError.unauthorized("Fixture expiry") }
        }
        await #expect(throws: CancellationError.self) {
            let _: Int? = try await TeamPlayerMapper.optionalRead { throw CancellationError() }
        }
        await #expect(throws: URLError(.cancelled)) {
            let _: Int? = try await TeamPlayerMapper.optionalRead { throw URLError(.cancelled) }
        }
    }

    @Test("Every preview scoring player resolves with exact identity and ownership without replacing canonical lineup IDs")
    func demoScoringPlayerDetails() async throws {
        let repository = DemoLeagueRepository()
        let scoringTeams = SampleData.scores.matchups.flatMap { [$0.away, $0.home] }
        #expect(!scoringTeams.isEmpty)
        for team in scoringTeams {
            #expect(!team.players.isEmpty)
            for player in team.players {
                let detail = try await repository.loadPlayerDetail(playerID: player.id, refresh: false)
                #expect(detail.identity == PlayerIdentity(id: player.id, name: player.name,
                    position: player.position, nflTeam: player.nflTeam))
                let ownership = try #require(detail.ownership)
                let assignment = try #require(ownership.assignments.first { $0.team.id == team.id })
                let expectedStatus: PlayerLineupAssignment = switch player.lineupStatus {
                case .starter: .starter
                case .bench: .nonstarter
                case .unknown: .rostered
                }
                #expect(assignment.status == expectedStatus)
                #expect(ownership.isFreeAgent == false)
            }
        }

        let roster = try await repository.loadTeamRoster(franchiseID: SampleData.workspace.franchiseID,
            lineupWeek: SampleData.lineup.week, refresh: false)
        #expect(roster.players.map(\.id) == SampleData.lineup.players.map(\.id))
        for player in SampleData.lineup.players {
            let detail = try await repository.loadPlayerDetail(playerID: player.id, refresh: false)
            #expect(detail.identity.id == player.id && detail.identity.name == player.name)
            #expect(detail.ownership?.assignments.contains { $0.team.id == SampleData.workspace.franchiseID } == true)
        }
    }

    @Test("A real zero survives, while wrong-week metrics and placeholder season totals remain absent")
    func metrics() {
        var scores = SampleData.scores
        var lineup = SampleData.lineup
        var waivers = SampleData.waivers
        scores.matchups = []
        lineup.players[0].projectedPoints = 0
        lineup.players[0].seasonPoints = 999
        waivers.candidates = []
        let zero = PlayerWeekMetrics.matching(playerID: lineup.players[0].id, week: lineup.week,
            scores: scores, lineup: lineup, waivers: waivers)
        #expect(zero?.projection == 0 && zero?.points == nil)
        #expect(PlayerWeekMetrics.matching(playerID: lineup.players[0].id, week: lineup.week + 1,
            scores: scores, lineup: lineup, waivers: waivers) == nil)
        lineup.players[0].projectedPoints = nil
        #expect(PlayerWeekMetrics.matching(playerID: lineup.players[0].id, week: lineup.week,
            scores: scores, lineup: lineup, waivers: waivers) == nil)
    }

    @MainActor
    @Test("Late player requests cannot overwrite a newer selection or a reset session")
    func latePlayerResult() async {
        let model = PlayerDetailModel()
        let gate = TestGate()
        let old = PlayerDetailSnapshot(scope: "scope", identity: PlayerIdentity(id: "101", name: "Old"))
        let new = PlayerDetailSnapshot(scope: "scope", identity: PlayerIdentity(id: "102", name: "New"))
        let task = Task { await model.load(scope: "scope", playerID: "101") { await gate.wait(); return old } }
        while !model.isLoading { await Task.yield() }
        await model.load(scope: "scope", playerID: "102") { new }
        await gate.open()
        await task.value
        #expect(model.detail?.identity.id == "102")
        let secondGate = TestGate()
        let second = Task { await model.load(scope: "scope", playerID: "101") { await secondGate.wait(); return old } }
        while !model.isLoading { await Task.yield() }
        model.invalidate()
        await secondGate.open()
        await second.value
        #expect(model.detail == nil && !model.isLoading)
    }

    @MainActor
    @Test("Team model rejects a mismatched week and keeps a readable snapshot when refresh fails")
    func teamModelIsolation() async {
        let model = TeamDetailModel()
        let snapshot = TeamRosterSnapshot(scope: "scope", team: TeamSummary(id: "0001", name: "One", abbreviation: "ONE"),
            players: [], lineupWeek: 2)
        await model.loadRoster(scope: "scope", franchiseID: "0001", lineupWeek: 3) { snapshot }
        #expect(model.roster == nil && model.errorMessage != nil)
        await model.loadRoster(scope: "scope", franchiseID: "0001", lineupWeek: 2) { snapshot }
        await model.loadRoster(scope: "scope", franchiseID: "0001", lineupWeek: 2, force: true) {
            throw RepositoryError.server("Fixture offline")
        }
        #expect(model.roster == snapshot && model.errorMessage == "Fixture offline")
    }

    private func decodeStatus(_ json: String) throws -> MFLPlayerRosterStatusCollection {
        try JSONDecoder().decode(MFLPlayerRosterStatusCollection.self, from: Data(json.utf8))
    }

    private func connected(_ transport: TeamPlayerFixtureTransport) async throws -> LiveMFLRepository {
        let store = MemoryPrivateStore()
        try store.encode(SavedSession(cookie: "synthetic-cookie", season: 2026, leagueID: "41333", franchiseID: "0001"), key: "session")
        let repository = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero)
        _ = try await repository.restoreSession()
        return repository
    }
}

private actor TeamPlayerFixtureTransport: MFLHTTPTransport {
    private let fallback = MutationFixtureTransport()
    private(set) var requests: [[String: String]] = []
    private(set) var postCount = 0
    private var rosterMode = "normal"
    private var failCatalog = false
    private var failStatus = false
    private var failBio = false

    func configure(rosterMode: String = "normal", failCatalog: Bool = false, failStatus: Bool = false, failBio: Bool = false) {
        self.rosterMode = rosterMode
        self.failCatalog = failCatalog
        self.failStatus = failStatus
        self.failBio = failBio
    }

    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        requests.append(query)
        if request.httpMethod == "POST" { postCount += 1; throw MFLCoreError.invalidRequest("Unexpected write") }
        func response(_ value: [String: Any]) throws -> MFLHTTPResponse {
            MFLHTTPResponse(data: try JSONSerialization.data(withJSONObject: value), statusCode: 200, url: request.url)
        }
        switch query["TYPE"] {
        case "players":
            if query["DETAILS"] == "1" {
                if failBio { throw MFLCoreError.transport("Fixture bio offline") }
                return try response(["players": ["player": ["id": "101", "name": "Receiver, Riley", "position": "WR", "team": "CHI",
                    "birthdate": "2000-02-29", "draft_year": "2022", "draft_round": "2"]]])
            }
            if failCatalog { throw MFLCoreError.transport("Fixture catalog offline") }
            return try response(["players": ["player": [
                ["id": "101", "name": "Receiver, Riley", "position": "WR", "team": "CHI"],
                ["id": "102", "name": "Runner, Robin", "position": "RB", "team": "GB"],
                ["id": "103", "name": "Reserve, Reese", "position": "TE", "team": "DAL"]]]])
        case "rosters":
            let players: [[String: String]] = rosterMode == "empty" ? [] : [
                ["id": "101", "status": "ROSTER", "salary": "0", "contractYear": "2"],
                ["id": "102", "status": "ROSTER"], ["id": "103", "status": "INJURED_RESERVE"]]
            let roster: [String: Any] = ["id": "0001", "player": players]
            if rosterMode == "missing" { return try response(["rosters": ["franchise": []]]) }
            if rosterMode == "duplicate" { return try response(["rosters": ["franchise": [roster, roster]]]) }
            return try response(["rosters": ["franchise": roster]])
        case "playerRosterStatus":
            if failStatus { throw MFLCoreError.transport("Fixture status offline") }
            let ids = (query["P"] ?? "").split(separator: ",").map(String.init)
            let rows: [[String: Any]] = ids.map { id in
                let assignments = id == "101" ? [["franchise_id": "0001", "status": "S"], ["franchise_id": "0002", "status": "R"]]
                    : [["franchise_id": "0001", "status": id == "103" ? "IR" : "R"]]
                return ["id": id, "is_fa": "0", "roster_franchise": assignments]
            }
            return try response(["playerRosterStatuses": ["playerStatus": rows]])
        default: return try await fallback.send(request)
        }
    }
}
