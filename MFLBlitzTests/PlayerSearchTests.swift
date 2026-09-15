import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

@Suite("Global player search")
struct PlayerSearchTests {
    private let scope = "2026.41333.0001"

    @Test("NFL names, nicknames and common/MFL abbreviations find individual players")
    func nflTeamNames() {
        let index = PlayerSearchIndex(players: [
            .init(id: "ne", name: "Riley Receiver", position: "WR", nflTeam: "NEP"),
            .init(id: "sea", name: "Kenneth Runner", position: "RB", nflTeam: "SEA"),
            .init(id: "gb", name: "Taylor Receiver", position: "WR", nflTeam: "GBP")])
        for query in ["patriots", "New England", "Pats", "NE", "NEP", "patriots WR", "NE WR", "riley patriots"] {
            #expect(index.search(query).players.map(\.id) == ["ne"], "Query: \(query)")
        }
        #expect(index.search("Seahawks").players.map(\.id) == ["sea"])
        #expect(index.search("Green Bay").players.map(\.id) == ["gb"])
        #expect(index.search("GB").players.map(\.id) == ["gb"])
        #expect(index.search("NE RB").players.isEmpty)
    }

    @Test("All 32 NFL teams map names and code aliases without changing identities")
    func everyNFLTeam() {
        #expect(PlayerSearchTeams.all.count == 32)
        let players = PlayerSearchTeams.all.enumerated().map { index, team in
            PlayerIdentity(id: String(index), name: "Fixture \(index)", position: "WR", nflTeam: team.codes[0])
        }
        let index = PlayerSearchIndex(players: players)
        for (offset, team) in PlayerSearchTeams.all.enumerated() {
            for code in team.codes {
                #expect(index.search(code).players.map(\.id) == [String(offset)])
            }
            #expect(index.search(team.name).players.map(\.id) == [String(offset)])
        }
    }

    @Test("League rules exclude team units while retaining rostered and free-agent positions")
    func leaguePositionFiltering() throws {
        let league = try decode(MFLLeague.self, #"{"id":"41333","name":"League","starters":{"position":[{"name":"QB","limit":"1"},{"name":"RB","limit":"2-4"},{"name":"WR","limit":"3-5"},{"name":"TE","limit":"1-3"},{"name":"DEF","limit":"0"}]}}"#)
        let allowed = try #require(PlayerSearchPositions.eligible(in: league))
        #expect(allowed == ["QB", "RB", "WR", "TE"])
        let players: [PlayerIdentity] = [
            .init(id: "wr", name: "Riley Receiver", position: "WR", nflTeam: "NEP"),
            .init(id: "qb", name: "Quinn Quarterback", position: "QB", nflTeam: "NEP"),
            .init(id: "tmwr", name: "New England Patriots", position: "TMWR", nflTeam: "NEP"),
            .init(id: "tmrb", name: "New England Patriots", position: "TMRB", nflTeam: "NEP"),
            .init(id: "def", name: "New England Patriots", position: "DEF", nflTeam: "NEP")]
        let index = PlayerSearchIndex(players: players, eligiblePositions: allowed)
        #expect(index.search("patriots").players.map(\.id) == ["qb", "wr"])
        #expect(index.search("WR").players.map(\.id) == ["wr"])
        // Other MFL formats can legitimately use a team defense or team units.
        let units = PlayerSearchIndex(players: players, eligiblePositions: ["DEF", "TMWR"])
        #expect(Set(units.search("patriots").players.map(\.id)) == ["def", "tmwr"])
        #expect(units.search("D/ST").players.map(\.id) == ["def"])
        // If rules are missing, individuals still precede team-wide entries.
        #expect(PlayerSearchIndex(players: players).search("patriots").players.prefix(2).map(\.id) == ["qb", "wr"])
    }

    @Test("Zero-minimum slots stay searchable and uncertain rules do not hide players")
    func positionScopeFallback() throws {
        let rules = try decode(MFLLeague.self, #"{"id":"1","name":"League","starters":{"position":[{"name":"WR","limit":"0-3"},{"name":"DL","limit":"1-2"},{"name":"K","limit":"1"}]}}"#)
        #expect(PlayerSearchPositions.eligible(in: rules) == ["WR", "DL", "DE", "DT", "PK"])
        let unknown = try decode(MFLLeague.self, #"{"id":"1","name":"League","starters":{"position":[{"name":"FLEX","limit":"1"}]}}"#)
        #expect(PlayerSearchPositions.eligible(in: unknown) == nil)
        #expect(try PlayerSearchPositions.eligible(in: league()) == nil)
    }

    @Test("Names, NFL teams, positions, multiple terms and punctuation search locally")
    func indexMatching() {
        let index = PlayerSearchIndex(players: [
            .init(id: "1", name: "Wan’Dale Robinson", position: "WR", nflTeam: "TEN"),
            .init(id: "2", name: "Rashid Shaheed", position: "WR", nflTeam: "SEA"),
            .init(id: "3", name: "José Receiver", position: "WR", nflTeam: "DAL")])
        #expect(index.search("wandale").players.map(\.id) == ["1"])
        #expect(index.search("SHAHEED").players.map(\.id) == ["2"])
        #expect(index.search("wr sea").players.map(\.id) == ["2"])
        #expect(index.search("jose").players.map(\.id) == ["3"])
        #expect(index.search("WR").total == 3)
        #expect(index.search("WR", limit: 1).players.count == 1)
        #expect(index.search("WR", limit: 1).total == 3)
        #expect(index.search("  ").total == 0)
        #expect(index.search("no-such-player").players.isEmpty)
    }

    @Test("Duplicate identifiers never duplicate results; exact names rank first")
    func uniqueRanking() {
        let index = PlayerSearchIndex(players: [.init(id: "1", name: "A Player"),
            .init(id: "2", name: "Player"), .init(id: "2", name: "Player")])
        #expect(index.search("Player").players.map(\.id) == ["2", "1"])
    }

    @Test("Full catalogs are filtered without networking and result lists are bounded")
    func fullCatalog() {
        let index = PlayerSearchIndex(players: (1...20_000).map {
            .init(id: String($0), name: "Player \($0)", position: "WR", nflTeam: "SEA")
        })
        #expect(index.search("SEA").total == 20_000)
        #expect(index.search("SEA").players.count == 60)
        #expect(index.search("Player 19999").players.first?.id == "19999")
    }

    @Test("Incomplete or duplicate roster feeds cannot imply free agency", arguments: ["missing", "duplicate", "duplicatePlayer"])
    func incompleteOwnership(mode: String) throws {
        let franchises = mode == "missing" ? #"[{"id":"0001","player":[]}]"#
            : mode == "duplicate" ? #"[{"id":"0001","player":[]},{"id":"0001","player":[]}]"#
            : #"[{"id":"0001","player":[{"id":"101"},{"id":"101"}]},{"id":"0002","player":[]}]"#
        let rosters = try decode(MFLRosterCollection.self, "{\"franchise\":\(franchises)}")
        #expect(throws: (any Error).self) {
            try PlayerSearchMapper.ownership(scope: scope, league: league(), rosters: rosters, freeAgents: nil)
        }
    }

    @Test("Every owner is retained, reserve status wins, absence is not free agency")
    func ownersAndFreeAgents() throws {
        let value = try PlayerSearchMapper.ownership(scope: scope, league: league(), rosters: rosters(),
            freeAgents: decode(MFLFreeAgentPool.self, #"{"player":[{"id":"101"},{"id":"999"}]}"#))
        #expect(value.assignments["101"]?.count == 2)
        #expect(value.assignments["102"]?.first?.status == .injuredReserve)
        #expect(value.freeAgentIDs == ["999"])
        #expect(value.summary(for: "101", scores: nil, currentWeek: 1).contains("Avery & Morgan"))
        #expect(value.summary(for: "999", scores: nil, currentWeek: 1) == "Free agent")
        #expect(value.summary(for: "123", scores: nil, currentWeek: 1) == "Not on a roster")
        let unknownPool = try PlayerSearchMapper.ownership(scope: scope, league: league(unit: "CONFERENCE"),
            rosters: rosters(), freeAgents: decode(MFLFreeAgentPool.self, #"{"player":{"id":"999"}}"#))
        #expect(unknownPool.freeAgentIDs.isEmpty)
    }

    @Test("Starting/bench labels use recent current-week scores, never another week's lineup")
    func assignments() {
        let player = SampleData.scores.matchups[0].away.players[0]
        let team = SampleData.scores.matchups[0].away
        let ownership = PlayerSearchOwnership(scope: scope, assignments: [player.id: [
            .init(team: .init(id: team.id, name: team.name, abbreviation: team.abbreviation), status: .rostered)]], freeAgentIDs: [])
        var scores = SampleData.scores
        let now = Date(); scores.lastUpdated = now
        #expect(ownership.summary(for: player.id, scores: scores, currentWeek: scores.week, now: now).contains("Starting"))
        #expect(ownership.summary(for: player.id, scores: scores, currentWeek: scores.week + 1, now: now).contains("Rostered"))
        #expect(ownership.summary(for: player.id, scores: scores, currentWeek: scores.week, now: now.addingTimeInterval(300)).contains("Rostered"))
    }

    @Test("Warm searches reuse catalog and ownership; roster changes force fresh membership")
    @MainActor func cachingAndRevision() async {
        let model = PlayerSearchModel(); let now = Date()
        var catalogReads = 0; var ownershipReads = 0; var forced: [Bool] = []
        for _ in 0..<2 {
            await model.loadCatalog(scope: scope, now: now) {
                catalogReads += 1
                return .init(scope: scope, index: .init(players: [.init(id: "1", name: "Rashid Shaheed")]))
            }
            await model.loadOwnership(scope: scope, revision: 1, now: now) { force in
                ownershipReads += 1; forced.append(force)
                return .init(scope: scope, assignments: [:], freeAgentIDs: [], checkedAt: now)
            }
        }
        for query in ["r", "ra", "rash", "rashid"] { model.query = query; await model.search() }
        #expect(catalogReads == 1 && ownershipReads == 1)
        #expect(model.results.players.first?.id == "1")
        await model.loadOwnership(scope: scope, revision: 2, now: now) { force in
            ownershipReads += 1; forced.append(force)
            return .init(scope: scope, assignments: [:], freeAgentIDs: ["1"], checkedAt: now)
        }
        #expect(forced == [false, true])
    }

    @Test("Ownership failures keep identities searchable and prior ownership explicitly stale")
    @MainActor func failedOwnership() async {
        let model = PlayerSearchModel()
        await model.loadCatalog(scope: scope) { .init(scope: scope, index: .init(players: [.init(id: "1", name: "Player")])) }
        await model.loadOwnership(scope: scope, revision: 0) { _ in .init(scope: scope, assignments: [:], freeAgentIDs: ["1"]) }
        await model.loadOwnership(scope: scope, revision: 0, force: true) { _ in throw URLError(.notConnectedToInternet) }
        model.query = "Player"; await model.search()
        #expect(model.results.players.count == 1)
        #expect(model.ownershipError == "Ownership may be out of date.")
        #expect(model.ownership?.freeAgentIDs == ["1"])
        #expect(!model.isLoadingOwnership && !model.isLoadingCatalog)
    }

    @Test("Recent players are bounded, de-duplicated and cleared with session scope")
    @MainActor func recents() {
        let model = PlayerSearchModel(); model.prepare(scope: scope)
        for id in 1...12 { model.remember(.init(id: String(id), name: "Player \(id)")) }
        model.remember(.init(id: "10", name: "Player 10"))
        #expect(model.recentPlayers.count == 8)
        #expect(model.recentPlayers.first?.id == "10")
        #expect(model.recentPlayers.filter { $0.id == "10" }.count == 1)
        model.query = "secret"; model.prepare(scope: "2026.other.0002")
        #expect(model.recentPlayers.isEmpty && model.query.isEmpty && !model.hasCatalog)
    }

    @Test("A late response after switching accounts cannot repopulate search")
    @MainActor func replacedSession() async {
        let model = PlayerSearchModel()
        var continuation: CheckedContinuation<PlayerSearchCatalog, Never>?
        let task = Task {
            await model.loadCatalog(scope: scope) { await withCheckedContinuation { continuation = $0 } }
        }
        while continuation == nil { await Task.yield() }
        model.reset(scope: "new")
        continuation?.resume(returning: .init(scope: scope, index: .init(players: [.init(id: "1", name: "Old player")])))
        await task.value
        #expect(!model.hasCatalog && !model.isLoadingCatalog)
        #expect(model.scope == "new")
    }

    @Test("Repository shares API caches and only reads full current rosters")
    func repositoryCache() async throws {
        let transport = SearchFixtureTransport()
        let store = MemoryPrivateStore()
        try store.encode(SavedSession(cookie: "synthetic", season: 2026, leagueID: "41333", franchiseID: "0001"), key: "session")
        let repository = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero)
        _ = try await repository.restoreSession()
        let catalog = try await repository.loadPlayerSearchCatalog()
        _ = try await repository.loadPlayerSearchCatalog()
        _ = try await repository.loadPlayerSearchOwnership(refresh: false)
        _ = try await repository.loadPlayerSearchOwnership(refresh: false)
        _ = catalog.index.search("Player")
        let requests = await transport.requests
        #expect(requests.filter { $0["TYPE"] == "players" }.count == 1)
        #expect(requests.filter { $0["TYPE"] == "rosters" }.count == 1)
        #expect(requests.filter { $0["TYPE"] == "freeAgents" }.count == 1)
        #expect(requests.filter { $0["TYPE"] == "rosters" }.allSatisfy { $0["W"] == nil && $0["FRANCHISE"] == nil })
        #expect(!requests.contains { $0["TYPE"] == "playerRosterStatus" })
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    private func league(unit: String = "LEAGUE") throws -> MFLLeague {
        try decode(MFLLeague.self, """
        {"id":"41333","name":"League","rostersPerPlayer":"1","playerLimitUnit":"\(unit)",
        "franchises":{"franchise":[{"id":"0001","name":"Team One","owner_name":"Avery &amp; Morgan"},{"id":"0002","name":"Team Two"}]}}
        """)
    }
    private func rosters() throws -> MFLRosterCollection {
        try decode(MFLRosterCollection.self, #"{"franchise":[{"id":"0001","player":[{"id":"101","status":"ROSTER"},{"id":"102","status":"INJURED_RESERVE"}]},{"id":"0002","player":{"id":"101","status":"ROSTER"}}]}"#)
    }
}

private actor SearchFixtureTransport: MFLHTTPTransport {
    private let fallback = MutationFixtureTransport()
    private(set) var requests: [[String: String]] = []
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        #expect(request.httpMethod != "POST")
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        requests.append(query)
        if query["TYPE"] == "rosters" {
            return MFLHTTPResponse(data: Data(#"{"rosters":{"franchise":[{"id":"0001","player":{"id":"201","status":"ROSTER"}},{"id":"0002","player":{"id":"101","status":"ROSTER"}}]}}"#.utf8), statusCode: 200, url: request.url)
        }
        return try await fallback.send(request)
    }
}
