import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MFLCore

struct RefreshCoordinationTests {
    @Test("Cancellation classification requires a cancellation type or URLSession domain and code")
    func cancellationClassification() {
        #expect(MFLCoreError.isCancellation(CancellationError()))
        #expect(MFLCoreError.isCancellation(URLError(.cancelled)))
        #expect(!MFLCoreError.isCancellation(URLError(.timedOut)))
        #expect(!MFLCoreError.isCancellation(NSError(domain: "SyntheticOtherDomain", code: NSURLErrorCancelled)))
        #expect(!MFLCoreError.isCancellation(MFLCoreError.transport("cancelled NSURLErrorDomain -999")))
    }

    @Test("Swift and URLSession cancellations stay cancellations, never raw transport errors", arguments: ["swift", "url", "ns"])
    func transportCancellation(kind: String) async throws {
        let transport = CancellationTransport(kind: kind)
        let client = try client(transport)
        await #expect(throws: CancellationError.self) {
            try await client.liveScoring(week: 1, refreshPolicy: .reloadIgnoringCache)
        }
        #expect(await transport.calls == 1)
    }

    @Test("Network errors never expose URLSession diagnostics in user-facing copy")
    func safeTransportMessage() async throws {
        let transport = CancellationTransport(kind: "offline")
        let client = try client(transport)
        do {
            _ = try await client.liveScoring(week: 1, refreshPolicy: .reloadIgnoringCache)
            Issue.record("Expected the genuine network error")
        } catch let error as MFLCoreError {
            guard case .transport = error else { Issue.record("Expected a transport error"); return }
            #expect(!String(describing: error).contains("private-test-url"))
            #expect(error.localizedDescription == "Couldn’t complete the MFL request. Please try again.")
        }
        #expect(MFLCoreError.transport("private-test-url UserInfo raw diagnostics").localizedDescription ==
                "Couldn’t complete the MFL request. Please try again.")
        #expect(await transport.calls == 1)
    }

    @Test("A cancelled import is not acknowledged or automatically replayed")
    func cancelledImport() async throws {
        let transport = CancellationTransport(kind: "ns")
        let client = MFLClient(configuration: MFLClientConfiguration(
            league: try MFLLeagueReference(season: 2026, leagueID: "41333", host: MFLAPIHost("www45.myfantasyleague.com")),
            userAgent: "Synthetic cancellation tests", minimumRequestInterval: .zero),
            transport: transport, authenticationCookie: try MFLAuthenticationCookie(value: "synthetic-cookie"))
        await #expect(throws: CancellationError.self) {
            try await client.submitLineup(MFLLineupSubmission(week: 1, starterPlayerIDs: ["101"]))
        }
        #expect(await transport.calls == 1)
    }

    @Test("A public-feed cooldown does not block a different league server; neither host is retried")
    func hostScopedCooldown() async throws {
        let transport = RefreshTransport(rateLimitFirst: true, retryHeader: "65")
        let client = try client(transport)
        await #expect(throws: (any Error).self) { try await client.injuries(week: 1) }
        await #expect(throws: (any Error).self) { try await client.injuries(week: 1) }
        #expect(await transport.calls == 1)
        #expect(try await client.projectedScores(week: 1).scoresByPlayerID["101"] == 2)
        #expect(await transport.calls == 2)
        await #expect(throws: (any Error).self) { try await client.nflByeWeeks() }
        #expect(await transport.calls == 2)
    }

    @Test("Malformed Retry-After values use a finite cooldown without automatic retries", arguments: ["inf", "nan", "-10", "1e100"])
    func malformedCooldown(header: String) async throws {
        let transport = RefreshTransport(rateLimitFirst: true, retryHeader: header)
        let client = try client(transport)
        do {
            _ = try await client.projectedScores(week: 1)
            Issue.record("Expected a rate limit")
        } catch MFLCoreError.rateLimited(let seconds) { #expect(seconds == nil) }
        do {
            _ = try await client.projectedScores(week: 1)
            Issue.record("Expected the fallback cooldown")
        } catch MFLCoreError.rateLimited(let seconds) {
            let remaining = try #require(seconds)
            #expect(remaining.isFinite && remaining > 0 && remaining <= 90)
        }
        #expect(await transport.calls == 1)
    }

    @Test("Canceling the first caller does not discard a completed shared read or force another download")
    func canceledOriginator() async throws {
        let transport = RefreshTransport()
        let client = try client(transport)
        let first = Task { try await client.projectedScores(week: 1) }
        while await transport.calls == 0 { await Task.yield() }
        let second = Task { try await client.projectedScores(week: 1) }
        try await Task.sleep(for: .milliseconds(30))
        first.cancel()
        _ = try await second.value
        await #expect(throws: CancellationError.self) { try await first.value }
        _ = try await client.projectedScores(week: 1)
        #expect(await transport.calls == 1)
    }

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

private actor CancellationTransport: MFLHTTPTransport {
    let kind: String
    var calls = 0
    init(kind: String) { self.kind = kind }
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        calls += 1
        if kind == "swift" { throw CancellationError() }
        if kind == "url" { throw URLError(.cancelled) }
        throw NSError(domain: NSURLErrorDomain,
                      code: kind == "offline" ? NSURLErrorNotConnectedToInternet : NSURLErrorCancelled,
                      userInfo: [NSURLErrorFailingURLStringErrorKey: "https://private-test-url/export?synthetic=1",
                                 NSLocalizedDescriptionKey: "private-test-url UserInfo raw diagnostics"])
    }
}

private actor RefreshTransport: MFLHTTPTransport {
    var calls = 0
    var starts: [Date] = []
    let rateLimitFirst: Bool
    let retryHeader: String
    init(rateLimitFirst: Bool = false, retryHeader: String = "1") { self.rateLimitFirst = rateLimitFirst; self.retryHeader = retryHeader }
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        calls += 1
        let number = calls
        starts.append(Date())
        if number == 1 && rateLimitFirst { return MFLHTTPResponse(data: Data(), statusCode: 429, headers: ["Retry-After": retryHeader]) }
        try await Task.sleep(for: .milliseconds(number == 1 ? 300 : 5))
        let week = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "W" }?.value ?? "1"
        let json = "{\"projectedScores\":{\"week\":\"\(week)\",\"playerScore\":{\"id\":\"101\",\"score\":\"\(number)\"}}}"
        return MFLHTTPResponse(data: Data(json.utf8), statusCode: 200)
    }
}
