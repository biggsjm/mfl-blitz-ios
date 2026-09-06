import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MFLCore

@Suite("MFL actor client")
struct ClientTests {
    @Test("Host discovery runs once and read responses are cached")
    func discoveryAndCaching() async throws {
        let transport = StubTransport(responses: [
            .json(try fixtureData("league"), url: "https://www42.myfantasyleague.com/2026/export"),
            .json(try fixtureData("rosters"), url: "https://www42.myfantasyleague.com/2026/export"),
        ])
        let client = MFLClient(
            configuration: try configuration(host: nil),
            transport: transport
        )

        let first = try await client.rosters()
        let second = try await client.rosters()
        let requests = await transport.recordedRequests()

        #expect(first == second)
        #expect(requests.count == 2)
        #expect(requests[0].url?.host == "api.myfantasyleague.com")
        #expect(requests[1].url?.host == "www42.myfantasyleague.com")
        #expect(requests[1].url?.query?.contains("TYPE=rosters") == true)
    }

    @Test("Login cookie is manually sent on the next mutation")
    func loginAndLineup() async throws {
        let loginXML = Data("<status MFL_USER_ID=\"base64+/==\" />".utf8)
        let successJSON = Data("{\"status\":{\"$t\":\"Lineup submitted\"}}".utf8)
        let transport = StubTransport(responses: [
            MFLHTTPResponse(data: loginXML, statusCode: 200),
            .json(successJSON, url: "https://www45.myfantasyleague.com/2026/import"),
        ])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport
        )

        let cookie = try await client.authenticate(username: "sample-user", password: "sample-password")
        let result = try await client.submitLineup(
            MFLLineupSubmission(
                week: 7,
                starterPlayerIDs: ["14836", "16001"],
                comments: "Set from iPhone"
            )
        )
        let requests = await transport.recordedRequests()
        let mutationBody = try #require(requests[1].httpBody.flatMap { String(data: $0, encoding: .utf8) })

        #expect(cookie.value == "base64+/==")
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[1].value(forHTTPHeaderField: "Cookie") == "MFL_USER_ID=base64+/==")
        #expect(mutationBody.contains("STARTERS=14836%2C16001"))
        #expect(mutationBody.contains("W=7"))
        #expect(result.message == "Lineup submitted")
    }

    @Test("Blind bid uses documented add-amount-drop encoding")
    func blindBid() async throws {
        let transport = StubTransport(responses: [
            .json(Data("{\"status\":\"OK\"}".utf8), url: "https://www45.myfantasyleague.com/2026/import"),
        ])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport,
            authenticationCookie: try MFLAuthenticationCookie(value: "saved-cookie")
        )

        _ = try await client.submitBlindBidWaiverRequest(
            MFLBlindBidWaiverRequest(
                round: 1,
                bids: [
                    MFLBlindBid(playerID: "17001", amount: 17, dropPlayerID: "16001"),
                    MFLBlindBid(playerID: "17002", amount: 8),
                ]
            )
        )
        let request = try #require(await transport.recordedRequests().first)
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        #expect(request.url?.query?.contains("TYPE=blindBidWaiverRequest") == true)
        #expect(body.contains("PICKS=17001_17_16001%2C17002_8_0000"))
        #expect(body.contains("REPLACE=1"))
        #expect(body.contains("ROUND=1"))
    }

    @Test("Free-agent read exposes ids for player-catalog mapping")
    func freeAgents() async throws {
        let transport = StubTransport(responses: [
            .json(try fixtureData("free-agents")),
        ])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport
        )

        let pool = try await client.freeAgents(position: "WR")
        let request = try #require(await transport.recordedRequests().first)

        #expect(pool.players.map(\.id) == ["17001", "17002"])
        #expect(request.url?.query?.contains("TYPE=freeAgents") == true)
        #expect(request.url?.query?.contains("POSITION=WR") == true)
    }

    @Test("Message-board writer distinguishes a new thread from a reply")
    func messageBoardWrites() async throws {
        let success = Data("{\"status\":\"OK\"}".utf8)
        let transport = StubTransport(responses: [.json(success), .json(success)])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport,
            authenticationCookie: try MFLAuthenticationCookie(value: "saved-cookie")
        )

        _ = try await client.postMessageBoard(
            MFLMessageBoardPost(subject: "Week 7", body: "Good luck & have fun")
        )
        _ = try await client.postMessageBoard(
            MFLMessageBoardPost(threadID: "9001", body: "Thanks!")
        )
        let requests = await transport.recordedRequests()
        let newThreadBody = try #require(requests[0].httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let replyBody = try #require(requests[1].httpBody.flatMap { String(data: $0, encoding: .utf8) })

        #expect(newThreadBody.contains("SUBJECT=Week+7"))
        #expect(newThreadBody.contains("BODY=Good+luck+%26+have+fun"))
        #expect(replyBody.contains("THREAD=9001"))
        #expect(!replyBody.contains("SUBJECT="))
    }

    @Test("A 429 is surfaced with Retry-After and is never retried")
    func rateLimit() async throws {
        let transport = StubTransport(responses: [
            MFLHTTPResponse(data: Data(), statusCode: 429, headers: ["Retry-After": "7"]),
        ])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport
        )

        do {
            _ = try await client.liveScoring(week: 7, refreshPolicy: .reloadIgnoringCache)
            Issue.record("Expected the request to be rate limited")
        } catch let error as MFLCoreError {
            #expect(error == .rateLimited(retryAfter: 7))
        }
        #expect(await transport.recordedRequests().count == 1)
    }

    @Test("MFL JSON error payloads map to authorization errors")
    func authorizationError() async throws {
        let data = Data("""
        {"error":{"$t":"API requires logged in user - pass the proper MFL_USER_ID cookie"}}
        """.utf8)
        let transport = StubTransport(responses: [.json(data)])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport
        )

        do {
            _ = try await client.standings(refreshPolicy: .reloadIgnoringCache)
            Issue.record("Expected an authorization error")
        } catch let error as MFLCoreError {
            guard case .unauthorized = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test("XML import errors are never mistaken for mutation success")
    func importXMLError() async throws {
        let response = MFLHTTPResponse(
            data: Data("<error>API requires logged in user</error>".utf8),
            statusCode: 200
        )
        let transport = StubTransport(responses: [response])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport,
            authenticationCookie: try MFLAuthenticationCookie(value: "saved-cookie")
        )

        do {
            _ = try await client.submitLineup(
                MFLLineupSubmission(week: 7, starterPlayerIDs: ["14836"])
            )
            Issue.record("Expected the XML error to fail the mutation")
        } catch let error as MFLCoreError {
            guard case .unauthorized = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test("A known XML status is accepted but arbitrary HTML is rejected")
    func strictImportResponseValidation() async throws {
        let transport = StubTransport(responses: [
            MFLHTTPResponse(
                data: Data("<status>Lineup submitted</status>".utf8),
                statusCode: 200
            ),
            MFLHTTPResponse(
                data: Data("<html><body>OK</body></html>".utf8),
                statusCode: 200
            ),
        ])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport,
            authenticationCookie: try MFLAuthenticationCookie(value: "saved-cookie")
        )

        let result = try await client.submitLineup(
            MFLLineupSubmission(week: 7, starterPlayerIDs: ["14836"])
        )
        #expect(result.message == "Lineup submitted")

        do {
            _ = try await client.submitLineup(
                MFLLineupSubmission(week: 7, starterPlayerIDs: ["14836"])
            )
            Issue.record("Expected arbitrary HTML to be rejected")
        } catch let error as MFLCoreError {
            #expect(error == .invalidResponse)
        }
    }

    @Test("Sensitive requests reject a response from another origin")
    func mutationRedirect() async throws {
        let transport = StubTransport(responses: [
            .json(
                Data("{\"status\":\"OK\"}".utf8),
                url: "https://example.com/2026/import"
            ),
        ])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport,
            authenticationCookie: try MFLAuthenticationCookie(value: "saved-cookie")
        )

        do {
            _ = try await client.submitLineup(
                MFLLineupSubmission(week: 7, starterPlayerIDs: ["14836"])
            )
            Issue.record("Expected the redirected response to be rejected")
        } catch let error as MFLCoreError {
            #expect(error == .unexpectedRedirect)
        }
    }

    @Test("A negative status cannot pass because it contains a success word")
    func negativeMutationStatus() async throws {
        let transport = StubTransport(responses: [
            .json(Data("{\"status\":\"Lineup not submitted\"}".utf8)),
        ])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport,
            authenticationCookie: try MFLAuthenticationCookie(value: "saved-cookie")
        )

        do {
            _ = try await client.submitLineup(
                MFLLineupSubmission(week: 7, starterPlayerIDs: ["14836"])
            )
            Issue.record("Expected the negative status to fail")
        } catch let error as MFLCoreError {
            #expect(error == .api("Lineup not submitted"))
        }
    }

    private func configuration(host: String?) throws -> MFLClientConfiguration {
        let parsedHost = try host.map(MFLAPIHost.init)
        return MFLClientConfiguration(
            league: try MFLLeagueReference(season: 2026, leagueID: "41366", host: parsedHost),
            userAgent: "MFL Blitz Tests/1.0",
            minimumRequestInterval: .zero,
            cacheDurations: .standard
        )
    }
}

private actor StubTransport: MFLHTTPTransport {
    private var responses: [MFLHTTPResponse]
    private var requests: [URLRequest] = []

    init(responses: [MFLHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw MFLCoreError.transport("No stub response remains")
        }
        return responses.removeFirst()
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private extension MFLHTTPResponse {
    static func json(_ data: Data, status: Int = 200, url: String? = nil) -> Self {
        Self(
            data: data,
            statusCode: status,
            headers: ["Content-Type": "application/json"],
            url: url.flatMap(URL.init(string:))
        )
    }
}

private func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}
