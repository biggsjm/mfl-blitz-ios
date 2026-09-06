import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

struct ScoringAndCacheTests {
    @Test("Player clocks distinguish live, pregame, final and unknown when team-level live counts are absent", arguments: [1_800, 3_600, 0, -1])
    func playerClockFallback(seconds: Int) throws {
        let clock = seconds < 0 ? "" : ",\"gameSecondsRemaining\":\"\(seconds)\""
        let json = "{\"id\":\"0001\",\"players\":{\"player\":[{\"id\":\"101\",\"status\":\"starter\"\(clock)},{\"id\":\"102\",\"status\":\"nonstarter\",\"gameSecondsRemaining\":\"1800\"}]}}"
        let team = try JSONDecoder().decode(MFLLiveFranchise.self, from: Data(json.utf8))
        let status = LiveMFLRepository.gameStatus(for: [team])
        #expect(status.isLive == (seconds == 1_800))
        if seconds == 0 { #expect(status == .final) }
        if seconds == 3_600 || seconds < 0 { #expect(status == .pregame(nil)) }
    }

    @Test("Scoring and editing share stable FLEX assignments regardless of response ordering")
    func consistentFlex() {
        let lineup = SampleData.lineup
        let players = lineup.starters.map { ($0.id, $0.position) }
        let expected = Set(lineup.startingSlots.filter(\.isFlex).map(\.id))
        #expect(expected.count == 2)
        #expect(LineupSlotAllocation.flexPlayerIDs(players.reversed(), requirements: lineup.positionRequirements,
            starterCount: lineup.requiredStarterCount) == expected)
        #expect(LineupSlotAllocation.flexPlayerIDs(players, requirements: [], starterCount: 9).isEmpty)
    }

    @Test("Live scoring labels qualifying extra starters FLEX without changing NFL positions or points")
    func liveFlex() async throws {
        let store = MemoryPrivateStore()
        try store.encode(SavedSession(cookie: "synthetic-cookie", season: 2026, leagueID: "41333", franchiseID: "0001"), key: "session")
        let transport = MutationFixtureTransport()
        await transport.enableFlexScoring()
        let repository = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero)
        _ = try await repository.restoreSession()
        let scores = try await repository.refreshScores(week: 2)
        let matchup = try #require(scores.matchups.first)
        let flex = try #require(matchup.away.starters.first { $0.id == "101" })
        #expect(flex.lineupSlot == "FLEX" && flex.position == "WR")
        #expect(flex.livePoints == 0 && flex.projectedPoints == 13.25)
        #expect(matchup.away.starters.filter { $0.lineupSlot == "FLEX" }.count == 1)
        #expect(matchup.home.starters.allSatisfy { $0.lineupSlot == nil }) // Incomplete lineup: do not guess.
        #expect(matchup.away.score == 0 && matchup.home.score == 0)
    }

    @Test("All tabs and a reconnected repository share one daily player download")
    func repositoryCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mfl-repository-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemoryPrivateStore()
        try store.encode(SavedSession(cookie: "synthetic-cookie", season: 2026, leagueID: "41333", franchiseID: "0001"), key: "session")
        let transport = MutationFixtureTransport()
        let first = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero, playerCacheDirectory: directory)
        _ = try await first.restoreSession()
        _ = try await first.refreshScores(week: 2)
        _ = try await first.loadLineup(week: 2)
        _ = try await first.loadWaivers()
        _ = try await first.loadTrades()
        _ = try await first.loadTransactionActivity()
        #expect(await transport.requestCounts["players"] == 1)
        #expect(await transport.requestCounts["league"] == 1)
        let second = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero, playerCacheDirectory: directory)
        _ = try await second.restoreSession()
        _ = try await second.loadLineup(week: 2)
        _ = try await second.loadWaivers()
        #expect(await transport.requestCounts["players"] == 1)
        // Reconnection still verifies membership and private league data fresh.
        #expect(await transport.requestCounts["myleagues"] == 2)
        #expect(await transport.requestCounts["league"] == 2)
    }
}
