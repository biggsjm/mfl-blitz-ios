import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MFLCore

struct RefreshCoordinationTests {
    private func client(_ transport: any MFLHTTPTransport, interval: Duration = .zero) throws -> MFLClient {
        MFLClient(configuration: MFLClientConfiguration(
            league: try MFLLeagueReference(season: 2026, leagueID: "41333", host: MFLAPIHost("www45.myfantasyleague.com")),
            userAgent: "Synthetic refresh tests", minimumRequestInterval: interval), transport: transport)
    }

    @Test("Concurrent cacheable reads share one network request")
    func coalescing() async throws {
        let transport = RefreshTransport()
        let client = try client(transport)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 { group.addTask { _ = try await client.projectedScores(week: 1) } }
            try await group.waitForAll()
        }
        _ = try await client.projectedScores(week: 1)
        #expect(await transport.calls == 1)
    }

    @Test("Forced readback never joins an older read and its cache cannot be overwritten by that read")
    func forcedReadIsFresh() async throws {
        let transport = RefreshTransport()
        let client = try client(transport)
        let oldRead = Task { try await client.projectedScores(week: 1) }
        while await transport.calls == 0 { await Task.yield() }
        let fresh = try await client.projectedScores(week: 1, refreshPolicy: .reloadIgnoringCache)
        #expect(fresh.scoresByPlayerID["101"] == 2)
        _ = try await oldRead.value
        #expect(try await client.projectedScores(week: 1).scoresByPlayerID["101"] == 2)
        #expect(await transport.calls == 2)
    }

    @Test("Invalidating an endpoint prevents an in-flight result repopulating its cache")
    func invalidation() async throws {
        let transport = RefreshTransport()
        let client = try client(transport)
        let oldRead = Task { try await client.projectedScores(week: 1) }
        while await transport.calls == 0 { await Task.yield() }
        await client.clearCache(for: .projectedScores)
        _ = try await oldRead.value
        #expect(try await client.projectedScores(week: 1).scoresByPlayerID["101"] == 2)
        #expect(await transport.calls == 2)
    }

    @Test("Concurrent requests respect the minimum spacing")
    func pacing() async throws {
        let transport = RefreshTransport()
        let client = try client(transport, interval: .milliseconds(40))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for week in 1...8 { group.addTask { _ = try await client.projectedScores(week: week) } }
            try await group.waitForAll()
        }
        let dates = await transport.starts
        #expect(dates.count == 8)
        for (first, second) in zip(dates, dates.dropFirst()) { #expect(second.timeIntervalSince(first) >= 0.035) }
    }

    @Test("Retry-After expires at the advertised time and does not retry automatically")
    func rateLimitExpiry() async throws {
        let transport = RefreshTransport(rateLimitFirst: true)
        let client = try client(transport)
        await #expect(throws: (any Error).self) { try await client.projectedScores(week: 1) }
        await #expect(throws: (any Error).self) { try await client.projectedScores(week: 1) }
        #expect(await transport.calls == 1)
        try await Task.sleep(for: .milliseconds(1_100))
        _ = try await client.projectedScores(week: 1)
        #expect(await transport.calls == 2)
    }
}

private actor RefreshTransport: MFLHTTPTransport {
    var calls = 0
    var starts: [Date] = []
    let rateLimitFirst: Bool
    init(rateLimitFirst: Bool = false) { self.rateLimitFirst = rateLimitFirst }
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        calls += 1
        let number = calls
        starts.append(Date())
        if number == 1 && rateLimitFirst { return MFLHTTPResponse(data: Data(), statusCode: 429, headers: ["Retry-After": "1"]) }
        try await Task.sleep(for: .milliseconds(number == 1 ? 300 : 5))
        let week = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "W" }?.value ?? "1"
        let json = "{\"projectedScores\":{\"week\":\"\(week)\",\"playerScore\":{\"id\":\"101\",\"score\":\"\(number)\"}}}"
        return MFLHTTPResponse(data: Data(json.utf8), statusCode: 200)
    }
}
