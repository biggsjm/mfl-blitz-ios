import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MFLCore

struct CatalogPerformanceTests {
    @Test("Duplicate player IDs fail decoding before dictionary construction can crash")
    func duplicatePlayers() {
        let data = Data(#"{"players":{"player":[{"id":"101","name":"One, Player"},{"id":"101","name":"Duplicate, Player"}]}}"#.utf8)
        #expect(throws: (any Error).self) { try MFLResponseDecoder().decode(MFLPlayersResponse.self, from: data) }
    }

    @Test("Repeated 10,000-player catalog reads reuse the validated snapshot and honor invalidation")
    func repeatedCatalogReads() async throws {
        let transport = LargeCatalogTransport()
        let client = MFLClient(configuration: MFLClientConfiguration(
            league: try MFLLeagueReference(season: 2026, leagueID: "41333", host: MFLAPIHost("www45.myfantasyleague.com")),
            userAgent: "Synthetic performance test", minimumRequestInterval: .zero), transport: transport)
        #expect(try await client.players().players.count == 10_000)
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<20 { #expect(try await client.players().players.count == 10_000) }
        let elapsed = start.duration(to: clock.now)
        print("[Synthetic benchmark] 20 warm reads of 10,000 players: \(elapsed)")
        #expect(await transport.calls == 1)
        await client.clearCache(for: .players)
        #expect(try await client.players().players.first?.name == "Revision 2")
        #expect(try await client.players(refreshPolicy: .reloadIgnoringCache).players.first?.name == "Revision 3")
        #expect(try await client.players().players.first?.name == "Revision 3")
        #expect(await transport.calls == 3)
    }
}

private actor LargeCatalogTransport: MFLHTTPTransport {
    var calls = 0
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        calls += 1
        let rows = (1...10_000).map { ["id": String($0), "name": "Revision \(calls)", "position": "WR", "team": "CHI"] }
        return MFLHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["players": ["player": rows]]), statusCode: 200)
    }
}
