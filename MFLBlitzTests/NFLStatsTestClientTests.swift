#if DEBUG
import Foundation
import Testing
@testable import MFLBlitz

private final class NFLTestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var failure: URLError?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        if let error = Self.failure { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@Suite(.serialized) struct NFLStatsTestClientTests {
    static let address = "https://test.example.ts.net:8443"
    static var game: [String: Any] { ["id": 11, "season": 2024, "stage": "Regular Season", "week": "Week 1",
        "kickoff": 1725583200, "status": "FT", "homeID": 1, "home": "Home Team", "awayID": 2,
        "away": "Away Team", "homeScore": 21, "awayScore": 7] }

    private func client(body: [String: Any], status: Int = 200) throws -> NFLStatsTestClient {
        NFLTestURLProtocol.body = try JSONSerialization.data(withJSONObject: body)
        NFLTestURLProtocol.status = status; NFLTestURLProtocol.requests = []; NFLTestURLProtocol.failure = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NFLTestURLProtocol.self]
        return try NFLStatsTestClient(address: Self.address, session: URLSession(configuration: config))
    }

    @Test func rejectsUnsafeAddresses() throws {
        for address in ["http://test.example.ts.net", "https://api-sports.io", "https://user:key@test.example.ts.net",
                        "https://test.example.ts.net?key=secret", "https://test.example.ts.net/path",
                        "https://test.example.ts.net#secret", "https://test.example.ts.net.evil.com"] {
            #expect(throws: (any Error).self) { try NFLStatsTestClient.serverURL(address) }
        }
        #expect(try NFLStatsTestClient.serverURL(Self.address).port == 8443)
    }

    @Test func validatesSeasonBeforeNetwork() async throws {
        let client = try client(body: [:])
        await #expect(throws: (any Error).self) { try await client.games(season: 2026) }
        #expect(NFLTestURLProtocol.requests.isEmpty)
    }

    @Test func historicalGamesHaveNoMFLCredentials() async throws {
        let client = try client(body: ["provider": "API-NFL", "testOnly": true, "season": 2024,
                                      "fetchedAt": 1725583200, "stale": false, "games": [Self.game]])
        let value = try await client.games(season: 2024)
        #expect(value.games.first?.isFinal == true)
        #expect(NFLTestURLProtocol.requests.count == 1)
        let request = try #require(NFLTestURLProtocol.requests.first)
        #expect(request.url?.path == "/v1/seasons/2024/games")
        #expect(request.url?.absoluteString == "https://test.example.ts.net:8443/v1/seasons/2024/games")
        #expect(request.value(forHTTPHeaderField: "X-Blitz-NFL-Test") == "1")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "x-apisports-key") == nil)
    }

    @Test func refusesWrongSeasonAndDuplicateIDs() async throws {
        for games in [[Self.game.merging(["season": 2026]) { _, new in new }], [Self.game, Self.game]] {
            let client = try client(body: ["provider": "API-NFL", "testOnly": true, "season": 2024,
                                          "fetchedAt": 1725583200, "stale": false, "games": games])
            await #expect(throws: (any Error).self) { try await client.games(season: 2024) }
        }
    }

    @Test func missingIsNotZeroAndUsesNoSecondPlayerRequest() async throws {
        let client = try client(body: ["provider": "API-NFL", "testOnly": true, "season": 2024,
            "fetchedAt": 1725583200, "stale": true, "game": Self.game, "players": [
                ["id": "1-10", "providerID": 10, "name": "Example Player", "team": "Home Team", "groups": [
                    ["name": "Passing", "stats": [["name": "yards", "value": "0"],
                                                     ["name": "sacks", "value": NSNull()]]]]]]])
        let value = try await client.players(game: NFLTestPreview.game)
        #expect(value.stale)
        #expect(value.players.first?.groups.first?.stats.first?.displayValue == "0")
        #expect(value.players.first?.groups.first?.stats.last?.displayValue == "—")
        #expect(NFLTestURLProtocol.requests.count == 1)
    }

    @Test func rejectsCrossGameStatResponse() async throws {
        let client = try client(body: ["provider": "API-NFL", "testOnly": true, "season": 2024,
            "fetchedAt": 1725583200, "stale": false, "game": Self.game.merging(["id": 12]) { _, new in new }, "players": []])
        await #expect(throws: (any Error).self) { try await client.players(game: NFLTestPreview.game) }
    }

    @Test func profileUsesOnlyHistoricalProviderIDsAndRejectsMismatches() async throws {
        let player = NFLTestPreview.box.players[0]
        for id in [10, 99] {
            let client = try client(body: ["provider": "API-NFL", "testOnly": true, "season": 2024,
                "gameID": 11, "fetchedAt": 1725583200, "stale": false,
                "profile": ["providerID": id, "name": "Example Quarterback", "position": "QB"]])
            if id == 10 {
                let result = try await client.profile(player: player, game: NFLTestPreview.game)
                #expect(result.profile.providerID == 10)
            } else {
                await #expect(throws: (any Error).self) { try await client.profile(player: player, game: NFLTestPreview.game) }
            }
            let request = try #require(NFLTestURLProtocol.requests.first)
            #expect(request.url?.absoluteString == Self.address + "/v1/seasons/2024/games/11/players/10/profile")
            #expect(request.httpBody == nil && request.value(forHTTPHeaderField: "Cookie") == nil)
        }
    }

    @Test func sanitizedErrorsAndCancellation() async throws {
        let client = try client(body: ["error": "budget", "message": "DO NOT DISPLAY RAW DIAGNOSTICS"], status: 429)
        do {
            _ = try await client.games(season: 2024)
            Issue.record("Expected a budget error")
        } catch {
            #expect(error.localizedDescription == NFLTestError.budget.localizedDescription)
        }
        NFLTestURLProtocol.failure = URLError(.cancelled)
        await #expect(throws: CancellationError.self) { try await client.games(season: 2024) }
    }

    @Test func networkHTTPAndDecodeFailuresStayDistinctAndPrivate() async throws {
        let client = try client(body: ["error": "access", "message": "do not echo raw content"], status: 403)
        do { _ = try await client.games(season: 2024); Issue.record("Expected HTTP failure") }
        catch { #expect(error.localizedDescription == NFLTestError.httpStatus(403).localizedDescription) }
        NFLTestURLProtocol.status = 200
        do { _ = try await client.games(season: 2024); Issue.record("Expected decoding failure") }
        catch { #expect(error.localizedDescription == NFLTestError.decoding.localizedDescription) }
        for code: URLError.Code in [.cannotFindHost, .timedOut, .serverCertificateUntrusted, .notConnectedToInternet] {
            NFLTestURLProtocol.failure = URLError(code, userInfo: [NSLocalizedDescriptionKey: "sensitive raw details"])
            do { _ = try await client.games(season: 2024); Issue.record("Expected transport failure") }
            catch { #expect(error.localizedDescription == NFLTestError.transport(code.rawValue).localizedDescription) }
        }
    }
}
#endif
