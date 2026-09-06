import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MFLCore

struct PersistentCacheTests {
    private func client(_ transport: CatalogCacheTransport, cache: any MFLPersistentResponseCache, season: Int = 2026) throws -> MFLClient {
        MFLClient(configuration: MFLClientConfiguration(
            league: try MFLLeagueReference(season: season, leagueID: "41333", host: MFLAPIHost("www45.myfantasyleague.com")),
            userAgent: "Synthetic cache tests", minimumRequestInterval: .zero), transport: transport, playerCache: cache)
    }

    @Test("A full player directory survives client and disk-store recreation without another download")
    func relaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mfl-cache-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "players.json")
        let transport = CatalogCacheTransport()
        let firstStore = MFLDiskResponseCache(fileURL: url)
        let first = try await client(transport, cache: firstStore).players()
        let originalDate = try #require(await firstStore.read()?.fetchedAt)
        let reopenedStore = MFLDiskResponseCache(fileURL: url)
        let second = try await client(transport, cache: reopenedStore).players()
        #expect(first == second)
        #expect(await transport.count("players") == 1)
        #expect(await reopenedStore.read()?.fetchedAt == originalDate)
    }

    @Test("Expired, future-dated, wrong-season and malformed cached payloads are replaced", arguments: ["expired", "future", "season", "malformed"])
    func invalidCache(kind: String) async throws {
        let age: TimeInterval = kind == "expired" ? -86_401 : kind == "future" ? 600 : -100
        let stored = MFLStoredResponse(key: kind == "season" ? "players-v1:2025" : "players-v1:2026",
            data: kind == "malformed" ? Data("not JSON".utf8) : CatalogCacheTransport.players,
            fetchedAt: Date().addingTimeInterval(age))
        let cache = MemoryResponseCache(stored)
        let transport = CatalogCacheTransport()
        _ = try await client(transport, cache: cache).players()
        #expect(await transport.count("players") == 1)
        #expect(await cache.read()?.key == "players-v1:2026")
        #expect(await cache.read()?.isFresh(key: "players-v1:2026", ttl: 60) == true)
    }

    @Test("A valid 23-hour-old cache retains its original expiration")
    func retainsAge() async throws {
        let date = Date().addingTimeInterval(-23 * 3_600)
        let cache = MemoryResponseCache(MFLStoredResponse(key: "players-v1:2026", data: CatalogCacheTransport.players, fetchedAt: date))
        let transport = CatalogCacheTransport()
        _ = try await client(transport, cache: cache).players()
        #expect(await transport.count("players") == 0)
        #expect(await cache.read()?.fetchedAt == date)
    }

    @Test("A corrupt cache file recovers by downloading and atomically replacing it")
    func corruptFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mfl-cache-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "players.json")
        try Data("corrupt envelope".utf8).write(to: url)
        let cache = MFLDiskResponseCache(fileURL: url)
        let transport = CatalogCacheTransport()
        _ = try await client(transport, cache: cache).players()
        #expect(await cache.read()?.key == "players-v1:2026")
        #expect(await transport.count("players") == 1)
    }

    @Test("Private league data, selected players and incremental responses never use the public disk cache")
    func endpointIsolation() async throws {
        let cache = MemoryResponseCache()
        let transport = CatalogCacheTransport()
        let client = try client(transport, cache: cache)
        _ = try await client.league()
        _ = try await client.players(ids: ["101"])
        _ = try await client.players(details: true)
        _ = try await client.players(changedSince: Date())
        #expect(await cache.readCount == 0)
        #expect(await cache.writeCount == 0)
    }

    @Test("A forced player refresh bypasses persisted data and an invalid server payload is not saved")
    func forcedAndMalformed() async throws {
        let cache = MemoryResponseCache(MFLStoredResponse(key: "players-v1:2026", data: CatalogCacheTransport.players))
        let transport = CatalogCacheTransport()
        let client = try client(transport, cache: cache)
        _ = try await client.players(refreshPolicy: .reloadIgnoringCache)
        #expect(await transport.count("players") == 1)
        let previous = await cache.read()?.fetchedAt
        await transport.returnMalformedPlayers()
        await #expect(throws: (any Error).self) { try await client.players(refreshPolicy: .reloadIgnoringCache) }
        #expect(await cache.read()?.fetchedAt == previous)
    }

    @Test("Stable league reads reuse data while balance freshness and write preflight can bypass it")
    func leagueFreshness() async throws {
        let transport = CatalogCacheTransport()
        let client = try client(transport, cache: MemoryResponseCache())
        _ = try await client.league()
        _ = try await client.league()
        _ = try await client.league(maximumAge: 60)
        #expect(await transport.count("league") == 1)
        _ = try await client.league(maximumAge: 0)
        #expect(await transport.count("league") == 2)
        _ = try await client.league(refreshPolicy: .reloadIgnoringCache)
        #expect(await transport.count("league") == 3)
        #expect(MFLCacheDurations.standard.league == 86_400)
    }
}

private actor MemoryResponseCache: MFLPersistentResponseCache {
    var value: MFLStoredResponse?
    var readCount = 0
    var writeCount = 0
    init(_ value: MFLStoredResponse? = nil) { self.value = value }
    func read() -> MFLStoredResponse? { readCount += 1; return value }
    func write(_ value: MFLStoredResponse) { writeCount += 1; self.value = value }
    func remove() { value = nil }
}

private actor CatalogCacheTransport: MFLHTTPTransport {
    static let players = Data(#"{"players":{"player":[{"id":"101","name":"One, Player","position":"WR"}]}}"#.utf8)
    private var counts: [String: Int] = [:]
    private var malformedPlayers = false
    func count(_ type: String) -> Int { counts[type, default: 0] }
    func returnMalformedPlayers() { malformedPlayers = true }
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        let type = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "TYPE" }?.value ?? ""
        counts[type, default: 0] += 1
        let data: Data
        switch type {
        case "players": data = malformedPlayers ? Data(#"{"players":42}"#.utf8) : Self.players
        case "league": data = Data(#"{"league":{"id":"41333","name":"Synthetic league"}}"#.utf8)
        default: throw MFLCoreError.invalidRequest("Unexpected synthetic endpoint")
        }
        return MFLHTTPResponse(data: data, statusCode: 200, url: request.url)
    }
}
