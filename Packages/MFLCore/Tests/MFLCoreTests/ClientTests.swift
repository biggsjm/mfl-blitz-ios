import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MFLCore

@Suite("MFL actor client")
struct ClientTests {
    @Test("League projections send the selected week and cookie and reuse cached results")
    func projectedScores() async throws {
        let data = Data(#"{"projectedScores":{"week":"1","playerScore":{"id":"001","score":"17.5"}}}"#.utf8)
        let transport = StubTransport(responses: [.json(data)])
        let client = MFLClient(configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport, authenticationCookie: try MFLAuthenticationCookie(value: "synthetic-cookie"))
        _ = try await client.projectedScores(week: 1)
        _ = try await client.projectedScores(week: 1)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].url?.query?.contains("W=1") == true)
        #expect(requests[0].url?.query?.contains("TYPE=projectedScores") == true)
        #expect(requests[0].url?.query?.contains("L=41366") == true)
        #expect(requests[0].value(forHTTPHeaderField: "Cookie") == "MFL_USER_ID=synthetic-cookie")
    }

    @Test("Projections from a different week are rejected")
    func wrongProjectionWeek() async throws {
        let transport = StubTransport(responses: [.json(Data(#"{"projectedScores":{"week":"2","playerScore":[]}}"#.utf8))])
        let client = MFLClient(configuration: try configuration(host: "www45.myfantasyleague.com"), transport: transport)
        await #expect(throws: (any Error).self) { try await client.projectedScores(week: 1) }
    }

    @Test("Authenticated league discovery maps account to franchise and host")
    func myLeagues() async throws {
        let transport = StubTransport(responses: [
            .json(try fixtureData("my-leagues"), url: "https://api.myfantasyleague.com/2026/export")
        ])
        let client = MFLClient(
            configuration: try configuration(host: nil),
            transport: transport,
            authenticationCookie: try MFLAuthenticationCookie(value: "saved-cookie")
        )

        let memberships = try await client.myLeagues(refreshPolicy: .reloadIgnoringCache)
        let membership = try #require(memberships.leagues.first)
        let request = try #require(await transport.recordedRequests().first)

        #expect(membership.leagueID == "41366")
        #expect(membership.franchiseID == "0008")
        #expect(membership.franchiseName == "Route Runners")
        #expect(membership.serverHost?.name == "www45.myfantasyleague.com")
        #expect(request.url?.host == "api.myfantasyleague.com")
        #expect(request.url?.query?.contains("TYPE=myleagues") == true)
        #expect(request.url?.query?.contains("YEAR=2026") == true)
        #expect(request.url?.query?.contains("FRANCHISE_NAMES=1") == true)
        #expect(request.url?.query?.contains("L=") == false)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "MFL_USER_ID=saved-cookie")
    }

    @Test("Host discovery runs once and read responses are cached")
    func discoveryAndCaching() async throws {
        let redirectedLeagueURL = "https://www42.myfantasyleague.com/2026/export?JSON=1&L=41366&TYPE=league"
        let transport = StubTransport(responses: [
            MFLHTTPResponse(
                data: Data(),
                statusCode: 302,
                headers: ["Location": redirectedLeagueURL],
                url: URL(string: "https://api.myfantasyleague.com/2026/export?JSON=1&L=41366&TYPE=league")
            ),
            .json(try fixtureData("league"), url: "https://www42.myfantasyleague.com/2026/export"),
            .json(try fixtureData("rosters"), url: "https://www42.myfantasyleague.com/2026/export"),
        ])
        let client = MFLClient(
            configuration: try configuration(host: nil),
            transport: transport,
            authenticationCookie: try MFLAuthenticationCookie(value: "saved-cookie")
        )

        let first = try await client.rosters()
        let second = try await client.rosters()
        let requests = await transport.recordedRequests()

        #expect(first == second)
        #expect(requests.count == 3)
        #expect(requests[0].url?.host == "api.myfantasyleague.com")
        #expect(requests[0].value(forHTTPHeaderField: "Cookie") == "MFL_USER_ID=saved-cookie")
        #expect(requests[1].url?.absoluteString == redirectedLeagueURL)
        #expect(requests[1].value(forHTTPHeaderField: "Cookie") == nil)
        #expect(requests[2].url?.host == "www42.myfantasyleague.com")
        #expect(requests[2].url?.query?.contains("TYPE=rosters") == true)
        #expect(requests[2].value(forHTTPHeaderField: "Cookie") == "MFL_USER_ID=saved-cookie")
    }

    @Test("Export redirects reject non-MFL destinations")
    func unsafeExportRedirect() async throws {
        let transport = StubTransport(responses: [
            MFLHTTPResponse(
                data: Data(),
                statusCode: 302,
                headers: [
                    "Location": "https://example.com/2026/export?JSON=1&L=41366&TYPE=league"
                ]
            )
        ])
        let client = MFLClient(
            configuration: try configuration(host: nil),
            transport: transport,
            authenticationCookie: try MFLAuthenticationCookie(value: "saved-cookie")
        )

        do {
            _ = try await client.discoverLeagueHost()
            Issue.record("Expected the untrusted export redirect to be rejected")
        } catch let error as MFLCoreError {
            guard case .invalidHost = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
        #expect(await transport.recordedRequests().count == 1)
    }

    @Test("User-league URLs reject insecure hosts")
    func unsafeUserLeagueURL() throws {
        let data = Data("""
        {"leagues":{"league":{"league_id":"41366","franchise_id":"0008","name":"Unsafe","url":"http://www45.myfantasyleague.com/2026/home/41366"}}}
        """.utf8)

        do {
            _ = try MFLResponseDecoder().decode(MFLMyLeaguesResponse.self, from: data)
            Issue.record("Expected the insecure league URL to be rejected")
        } catch let error as MFLCoreError {
            guard case .decoding = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
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

    @Test("Player roster status uses the resolved league host and is cached")
    func playerRosterStatus() async throws {
        let transport = StubTransport(responses: [
            .json(try fixtureData("player-roster-status")),
        ])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport
        )
        let playerIDs = ["12620", "14056", "15001", "15002", "17001"]

        let first = try await client.playerRosterStatus(
            playerIDs: playerIDs,
            week: 7,
            franchiseID: "0001"
        )
        let second = try await client.playerRosterStatus(
            playerIDs: playerIDs,
            week: 7,
            franchiseID: "0001"
        )
        let requests = await transport.recordedRequests()
        let request = try #require(requests.first)
        let requestURL = try #require(request.url)
        let items = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(first == second)
        #expect(first.statuses.count == playerIDs.count)
        #expect(requests.count == 1)
        #expect(request.url?.host == "www45.myfantasyleague.com")
        #expect(query["TYPE"] == "playerRosterStatus")
        #expect(query["JSON"] == "1")
        #expect(query["L"] == "41366")
        #expect(query["P"] == playerIDs.joined(separator: ","))
        #expect(query["W"] == "7")
        #expect(query["F"] == "0001")
        #expect(MFLCacheDurations.standard.playerRosterStatus == 15)
    }

    @Test("Player roster status validates required ids, week, and franchise")
    func playerRosterStatusValidation() async throws {
        let transport = StubTransport(responses: [])
        let client = MFLClient(
            configuration: try configuration(host: "www45.myfantasyleague.com"),
            transport: transport
        )
        let invalidArguments: [([String], Int?, String?)] = [
            ([], nil, nil),
            (["12620,14056"], nil, nil),
            (["12620", "12620"], nil, nil),
            (["12620"], 22, nil),
            (["12620"], nil, "0001,0002"),
        ]

        var invalidRequestCount = 0
        for (playerIDs, week, franchiseID) in invalidArguments {
            do {
                _ = try await client.playerRosterStatus(
                    playerIDs: playerIDs,
                    week: week,
                    franchiseID: franchiseID
                )
                Issue.record("Expected invalid player roster status arguments to fail")
            } catch let error as MFLCoreError {
                if case .invalidRequest = error {
                    invalidRequestCount += 1
                } else {
                    Issue.record("Unexpected error: \(error)")
                }
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }

        #expect(invalidRequestCount == invalidArguments.count)
        #expect(await transport.recordedRequests().isEmpty)
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
        // A new caller/poller during the cooldown must not hit MFL again.
        await #expect(throws: (any Error).self) {
            try await client.liveScoring(week: 7, refreshPolicy: .reloadIgnoringCache)
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
