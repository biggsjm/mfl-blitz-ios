import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MFLCore

struct PlayerToolsTests {
    @Test("Only explicit free agents with absent or false restriction flags can be added")
    func acquisitionFlags() throws {
        func allowed(_ json: String) throws -> Bool {
            try JSONDecoder().decode(MFLPlayerRosterStatus.self, from: Data(json.utf8)).canAddImmediately
        }
        #expect(try allowed(#"{"id":"301","is_fa":"1"}"#))
        #expect(try allowed(#"{"id":"301","is_fa":"1","cant_add":"0","locked":false}"#))
        for json in [
            #"{"id":"9431","roster_franchise":{"franchise_id":"0008","status":"S"}}"#,
            #"{"id":"301"}"#,
            #"{"id":"301","is_fa":"1","locked":"1"}"#,
            #"{"id":"301","is_fa":"1","cant_add":"1"}"#,
            #"{"id":"301","is_fa":"1","locked":"unknown"}"#,
            #"{"id":"301","is_fa":"1","locked":null}"#,
            #"{"id":"301","is_fa":"1","cant_add":"unknown"}"#,
            #"{"id":"301","is_fa":"1","isFA":"0"}"#,
            #"{"id":"301","is_fa":"1","locked":"0","isLocked":"1"}"#,
            #"{"id":"301","is_fa":"1","roster_franchise":{"franchise_id":"0008","status":"S"}}"#
        ] { #expect(try !allowed(json)) }
    }

    @Test("Availability handles singleton rows, unknown statuses, missing kickoffs and duplicate byes")
    func availabilityShapes() throws {
        let injuries = try JSONDecoder().decode(MFLInjuriesResponse.self,
            from: Data(#"{"injuries":{"week":"1","timestamp":"1788725222","injury":{"id":"101","status":"NEW","details":"Knee"}}}"#.utf8)).injuries
        #expect(injuries.week == 1 && injuries.byPlayerID["101"]?.status == "NEW" && injuries.timestamp != nil)
        let games = try JSONDecoder().decode(MFLNFLScheduleResponse.self,
            from: Data(#"{"nflSchedule":{"week":"2","matchup":{"team":[{"id":"CHI","isHome":"1"},{"id":"DET","isHome":"0"}]}}}"#.utf8)).nflSchedule
        #expect(games.matchups.count == 1 && games.matchups[0].kickoff == nil)
        #expect(games.matchups[0].teams.map(\.isHome) == [true, false])
        let byes = try JSONDecoder().decode(MFLByeWeeksResponse.self, from: Data(#"{"nflByeWeeks":{"year":"2026","team":[{"id":"CHI","bye_week":"8"},{"id":"CHI","bye_week":"9"},{"id":"DET","bye_week":"0"},{"id":"DAL","bye_week":"10"}]}}"#.utf8)).nflByeWeeks
        #expect(byes.byTeamID == ["DAL": 10])
    }

    @Test("Scores omit blank placeholders, preserve zero and reject ambiguous duplicate values")
    func scores() throws {
        let value = try JSONDecoder().decode(MFLPlayerScoresResponse.self, from: Data(#"{"playerScores":{"week":"AVG","playerScore":[{"id":"101","score":"0"},{"id":"","score":""},{"id":"102","score":""},{"id":"103","score":"5"},{"id":"103","score":"7"}]}}"#.utf8)).playerScores
        #expect(value.period == "AVG")
        #expect(value.players.count == 4)
        #expect(value.scoresByPlayerID == ["101": 0])
    }

    @Test("Whole-season NFL schedule reuses weekly shapes and rejects duplicate or unidentified weeks")
    func seasonScheduleShapes() throws {
        let decode = { (text: String) in
            try JSONDecoder().decode(MFLNFLSeasonScheduleResponse.self, from: Data(text.utf8)).fullNflSchedule
        }
        let value = try decode(#"{"fullNflSchedule":{"nflSchedule":[{"week":"1","matchup":{"kickoff":"1789345200","team":[{"id":"DAL","isHome":"0"},{"id":"NYG","isHome":"1"}]}},{"week":"2","matchup":[]}]}}"#)
        #expect(value.weeks.count == 2)
        #expect(value.byWeek[1]?.matchups.first?.teams.map(\.id) == ["DAL", "NYG"])
        #expect(value.byWeek[1]?.matchups.first?.teams.map(\.isHome) == [false, true])
        #expect(value.byWeek[1]?.matchups.first?.kickoff != nil)
        #expect(value.byWeek[2]?.matchups.isEmpty == true && value.byWeek[3] == nil)
        #expect(try decode(#"{"fullNflSchedule":{"nflSchedule":{"week":"1","matchup":[]}}}"#).weeks.count == 1)
        #expect(try decode(#"{"fullNflSchedule":{"nflSchedule":[]}}"#).weeks.isEmpty)
        for malformed in [
            #"{"fullNflSchedule":{}}"#,
            #"{"fullNflSchedule":{"nflSchedule":null}}"#,
            #"{"fullNflSchedule":{"nflSchedule":[{"week":"1"},{"week":"1"}]}}"#,
            #"{"fullNflSchedule":{"nflSchedule":{"matchup":[]}}}"#,
            #"{"fullNflSchedule":{"nflSchedule":{"week":"ALL","matchup":[]}}}"#,
            #"{"fullNflSchedule":{"nflSchedule":{"week":"0","matchup":[]}}}"#
        ] { #expect(throws: (any Error).self) { try decode(malformed) } }
    }

    @Test("Whole-season schedule is shared, cookie-free and keyed separately from one-week schedules")
    func seasonScheduleRequestCaching() async throws {
        let transport = PlayerToolsTransport()
        let client = try makeClient(transport)
        async let first = client.nflSeasonSchedule()
        async let joined = client.nflSeasonSchedule()
        let (firstValue, joinedValue) = try await (first, joined)
        #expect(firstValue == joinedValue)
        _ = try await client.nflSeasonSchedule()
        #expect(await transport.requests.count == 1)
        _ = try await client.nflSchedule(week: 2)
        _ = try await client.nflSchedule(week: 2)
        let requests = await transport.requests
        #expect(requests.count == 2)
        let queries = requests.map { request in
            Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        }
        #expect(queries.map { $0["W"] } == ["ALL", "2"])
        #expect(queries.allSatisfy { $0["TYPE"] == "nflSchedule" && $0["L"] == nil })
        #expect(requests.allSatisfy { $0.url?.host == "api.myfantasyleague.com" && $0.value(forHTTPHeaderField: "Cookie") == nil })
        _ = try await client.nflSeasonSchedule(refreshPolicy: .reloadIgnoringCache)
        #expect(await transport.requests.count == 3)
    }

    @Test("Watchlist accepts a known empty list and singleton; malformed and duplicate IDs fail closed")
    func watchShapes() throws {
        let decode = { (text: String) in try JSONDecoder().decode(MFLWatchList.self, from: Data(text.utf8)) }
        #expect(try decode(#"{"myWatchList":{}}"#).playerIDs.isEmpty)
        #expect(try decode(#"{"myWatchList":{"player":{"id":"101"}}}"#).playerIDs == ["101"])
        for text in [#"{"myWatchList":{"newField":"101"}}"#, #"{"myWatchList":{"player":{"id":""}}}"#,
                     #"{"myWatchList":{"player":[{"id":"101"},{"id":"101"}]}}"#] {
            #expect(throws: (any Error).self) { try decode(text) }
        }
    }

    @Test("Public availability is cookie-free and cached; private targeted scores keep exact league and period")
    func requestCaching() async throws {
        let transport = PlayerToolsTransport()
        let client = try makeClient(transport)
        _ = try await client.injuries(week: 1); _ = try await client.injuries(week: 1)
        _ = try await client.nflByeWeeks(); _ = try await client.nflByeWeeks()
        _ = try await client.playerScores(playerIDs: ["102", "101"], period: .week(2))
        _ = try await client.playerScores(playerIDs: ["101", "102"], period: .week(2))
        let reads = await transport.requests
        #expect(reads.count == 3)
        #expect(reads[0].value(forHTTPHeaderField: "Cookie") == nil)
        #expect(reads[1].value(forHTTPHeaderField: "Cookie") == nil)
        let score = try #require(reads.last)
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: score.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        #expect(query["L"] == "41333" && query["W"] == "2" && query["PLAYERS"] == "101,102")
        #expect(score.value(forHTTPHeaderField: "Cookie") == "MFL_USER_ID=fixture")
    }

    @Test("Mutations send only documented incremental fields and never retry a timeout")
    func writeContracts() async throws {
        let transport = PlayerToolsTransport()
        let client = try makeClient(transport)
        _ = try await client.updateWatchList(playerID: "101", isWatched: true)
        _ = try await client.updateWatchList(playerID: "102", isWatched: false)
        _ = try await client.addDrop(addPlayerID: "103", dropPlayerID: "104")
        _ = try await client.moveInjuredReserve(playerID: "105", activate: true, dropPlayerID: "106")
        let posts = await transport.requests
        let bodies = posts.map { String(data: $0.httpBody!, encoding: .utf8)! }
        #expect(bodies[0].contains("ADD=101") && !bodies[0].contains("REMOVE="))
        #expect(bodies[1].contains("REMOVE=102") && !bodies[1].contains("ADD="))
        #expect(posts[2].url?.query?.contains("TYPE=fcfsWaiver") == true && bodies[2].contains("DROP=104"))
        #expect(bodies[3].contains("ACTIVATE=105") && bodies[3].contains("DROP=106") && !bodies[3].contains("DEACTIVATE="))
        await transport.failWrites()
        await #expect(throws: (any Error).self) { try await client.addDrop(addPlayerID: "107", dropPlayerID: nil) }
        #expect(await transport.requests.count == 5)
        await #expect(throws: (any Error).self) { try await client.addDrop(addPlayerID: "101", dropPlayerID: "101") }
        await #expect(throws: (any Error).self) { try await client.moveInjuredReserve(playerID: "105", activate: false, dropPlayerID: "106") }
        #expect(await transport.requests.count == 5)
    }

    private func makeClient(_ transport: PlayerToolsTransport) throws -> MFLClient {
        MFLClient(configuration: MFLClientConfiguration(league: try MFLLeagueReference(season: 2026, leagueID: "41333",
            host: MFLAPIHost("www45.myfantasyleague.com")), userAgent: "Fixture", minimumRequestInterval: .zero),
            transport: transport, authenticationCookie: try MFLAuthenticationCookie(value: "fixture"))
    }
}

private actor PlayerToolsTransport: MFLHTTPTransport {
    var requests: [URLRequest] = []
    var timeout = false
    func failWrites() { timeout = true }
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        requests.append(request)
        if request.httpMethod == "POST", timeout { throw URLError(.timedOut) }
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
        let type = query.first { $0.name == "TYPE" }?.value
        let body = switch type {
        case "injuries": #"{"injuries":{"week":"1","injury":[]}}"#
        case "nflByeWeeks": #"{"nflByeWeeks":{"year":"2026","team":[]}}"#
        case "nflSchedule": query.first { $0.name == "W" }?.value == "ALL"
            ? #"{"fullNflSchedule":{"nflSchedule":[{"week":"1","matchup":[]},{"week":"2","matchup":[]}]}}"#
            : #"{"nflSchedule":{"week":"2","matchup":[]}}"#
        case "playerScores": #"{"playerScores":{"week":"2","playerScore":{"id":"101","score":"0"}}}"#
        default: #"{"status":"OK"}"#
        }
        return MFLHTTPResponse(data: Data(body.utf8), statusCode: 200, url: request.url)
    }
}
