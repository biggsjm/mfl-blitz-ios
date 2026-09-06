import Foundation
import Testing
@testable import MFLCore

@Suite("Fantasy season schedule")
struct ScheduleTests {
    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test("Full schedule preserves absent scores and unscheduled week entries")
    func futureSchedule() throws {
        let response = try JSONDecoder().decode(MFLScheduleResponse.self, from: fixtureData("schedule-future"))
        #expect(response.schedule.weeks.map(\.week) == [3, 4, 5])
        let games = try #require(response.schedule.weeks.first).matchups
        #expect(games.count == 2)
        #expect(games[0].id == nil)
        #expect(games[0].franchises[0].franchiseID == "0007")
        #expect(games[0].franchises[0].score == nil)
        #expect(games[0].franchises[0].result == "T")
        #expect(games[0].franchises[0].isHome == false)
        #expect(response.schedule.weeks[1].matchups.isEmpty)
        #expect(response.schedule.weeks[2].matchups.isEmpty)
    }

    @Test("Single week and matchup objects retain an actual zero score")
    func singletonSchedule() throws {
        let response = try JSONDecoder().decode(MFLScheduleResponse.self, from: fixtureData("schedule-singleton"))
        #expect(response.schedule.weeks.count == 1)
        let week = try #require(response.schedule.weeks.first)
        #expect(week.week == 2 && week.matchups.count == 1)
        #expect(week.matchups[0].franchises[0].score == Decimal.zero)
        #expect(week.matchups[0].franchises[1].score == Decimal(string: "101.25"))
    }

    @Test("A singleton participant is retained rather than fabricated into a pair")
    func partialParticipant() throws {
        let data = Data(#"{"schedule":{"weeklySchedule":{"week":3,"matchup":{"franchise":{"id":"0007"}}}}}"#.utf8)
        let response = try JSONDecoder().decode(MFLScheduleResponse.self, from: data)
        #expect(response.schedule.weeks[0].matchups[0].franchises.count == 1)
    }

    @Test("Invalid roots, weeks, and participant identities do not become empty schedules", arguments: [
        #"{"error":{"$t":"Requires logged in user"}}"#,
        #"{"schedule":{"weeklySchedule":{"week":"bad"}}}"#,
        #"{"schedule":{"weeklySchedule":{"week":"0"}}}"#,
        #"{"schedule":{"weeklySchedule":{"week":"3","matchup":{"franchise":{"score":"0"}}}}}"#
    ])
    func invalidSchedule(json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(MFLScheduleResponse.self, from: Data(json.utf8))
        }
    }

    @Test("Season reads omit week/team filters, preserve authentication, and reuse cached data")
    func seasonRequest() async throws {
        let data = try fixtureData("schedule-future")
        let transport = ScheduleFixtureTransport(responses: [data, data])
        let client = try makeClient(transport)
        let first = try await client.schedule()
        let second = try await client.schedule()
        #expect(first == second)
        #expect(await transport.requests.count == 1)
        _ = try await client.schedule(refreshPolicy: .reloadIgnoringCache)
        let requests = await transport.requests
        #expect(requests.count == 2)
        let request = try #require(requests.first)
        let url = try #require(request.url)
        let queryItems = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        #expect(url.path == "/2026/export")
        #expect(query["TYPE"] == "schedule" && query["L"] == "12345" && query["JSON"] == "1")
        #expect(query["W"] == nil && query["F"] == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "MFL_USER_ID=synthetic-schedule-cookie")
    }

    @Test("HTTP 200 authentication errors remain failures rather than an empty season")
    func bodyLevelError() async throws {
        let transport = ScheduleFixtureTransport(responses: [Data(#"{"error":{"$t":"API requires logged in user"}}"#.utf8)])
        let client = try makeClient(transport)
        await #expect(throws: (any Error).self) { try await client.schedule() }
        #expect(await transport.requests.count == 1)
    }

    private func makeClient(_ transport: ScheduleFixtureTransport) throws -> MFLClient {
        MFLClient(configuration: MFLClientConfiguration(
            league: try MFLLeagueReference(season: 2026, leagueID: "12345", host: MFLAPIHost("www45.myfantasyleague.com")),
            userAgent: "Synthetic schedule tests", minimumRequestInterval: .zero),
            transport: transport, authenticationCookie: try MFLAuthenticationCookie(value: "synthetic-schedule-cookie"))
    }
}

private actor ScheduleFixtureTransport: MFLHTTPTransport {
    private var responses: [Data]
    private(set) var requests: [URLRequest] = []

    init(responses: [Data]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw MFLCoreError.invalidResponse }
        return MFLHTTPResponse(data: responses.removeFirst(), statusCode: 200,
                               headers: ["Content-Type": "application/json"], url: request.url)
    }
}
