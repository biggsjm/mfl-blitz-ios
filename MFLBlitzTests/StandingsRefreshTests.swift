import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

struct StandingsRefreshTests {
    @Test("Preliminary standings use league results while global CompletedWeek is zero")
    func preliminaryRecordsAndCache() async throws {
        let transport = StandingsTransport()
        let repository = try await connected(transport)
        let rows = try await repository.loadStandings()
        for division in [true, false] {
            let sorted = StandingRow.sorted(rows, withinDivision: division)
            #expect(sorted.map(\.id) == ["0005", "0006", "0001", "0008"])
            #expect(sorted.map { division ? $0.divisionPlace?.position : $0.overallPlace?.position } == [1, 2, 3, 4])
        }
        #expect(rows.allSatisfy { $0.overallRankIssue == nil && $0.divisionRankIssue == nil })
        #expect(rows.first(where: { $0.id == "0001" })?.summary(leagueName: "Fixture") == "0–1 · 3rd in Warner")
        let counts = await transport.counts
        _ = try await repository.loadStandings()
        #expect(await transport.counts == counts)
        #expect(counts["schedule"] == 1 && counts["leagueStandings"] == 1)
    }

    @Test("Missing H2H does not scramble winning percentages or create ranks")
    func missingSchedule() async throws {
        let transport = StandingsTransport(missingSchedule: true)
        let repository = try await connected(transport)
        let rows = try await repository.loadStandings()
        #expect(StandingRow.sorted(rows, withinDivision: true).map(\.wins) == [1, 1, 0, 0])
        #expect(rows.allSatisfy { $0.divisionPlace == nil && $0.divisionRankIssue == .headToHeadUnavailable })
    }

    private func connected(_ transport: StandingsTransport) async throws -> LiveMFLRepository {
        let store = MemoryPrivateStore()
        try store.encode(SavedSession(cookie: "synthetic-cookie", season: 2026,
            leagueID: "41333", franchiseID: "0001"), key: "session")
        let repository = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero)
        _ = try await repository.restoreSession()
        return repository
    }
}

/// Synthetic wire responses reproduce the reported division without live account access.
private actor StandingsTransport: MFLHTTPTransport {
    let missingSchedule: Bool
    var counts: [String: Int] = [:]
    init(missingSchedule: Bool = false) { self.missingSchedule = missingSchedule }

    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        let url = try #require(request.url)
        let type = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "TYPE" }?.value ?? "status"
        counts[type, default: 0] += 1
        #expect(request.httpMethod != "POST")
        let object: [String: Any]
        switch type {
        case "myleagues":
            object = ["leagues": ["league": ["league_id": "41333", "franchise_id": "0001",
                "url": "https://www45.myfantasyleague.com/2026/home/41333"]]]
        case "league":
            object = ["league": ["id": "41333", "name": "Fixture", "startWeek": "1",
                "endWeek": "17", "lastRegularSeasonWeek": "14", "standingsSort": "PCT,H2H,PTS,DIVPCT,",
                "divisions": ["division": ["id": "01", "name": "Warner"]],
                "franchises": ["franchise": zip(["0001", "0005", "0006", "0008"],
                    ["Uber Beasts", "Bears Sausage Ditka", "Two Bad Neighbors", "GPT 5.0 now available"]).map {
                        ["id": $0.0, "name": $0.1, "division": "01"]
                    }]]]
        case "leagueStandings":
            object = ["leagueStandings": ["franchise": [
                standing("0001", 0, "93"), standing("0005", 1, "154.5"),
                standing("0006", 1, "87"), standing("0008", 0, "77.5")]]]
        case "schedule":
            if missingSchedule { throw URLError(.timedOut) }
            object = ["schedule": ["weeklySchedule": [
                ["week": "1", "matchup": [game("0005", "154.5", "0001", "93"),
                                           game("0006", "87", "0008", "77.5")]],
                ["week": "2", "matchup": [["franchise": [["id": "0001", "result": "T"],
                                                          ["id": "0006", "result": "T"]]]]]]]]
        case "status":
            object = ["mfl_status": ["year": "2026", "weeks": ["CurrentWeek": "1",
                "LiveScoringWeek": "1", "LineupWeek": "2", "CompletedWeek": "0"]]]
        default: throw MFLCoreError.invalidResponse
        }
        return MFLHTTPResponse(data: try JSONSerialization.data(withJSONObject: object), statusCode: 200, url: url)
    }

    private func standing(_ id: String, _ wins: Int, _ points: String) -> [String: String] {
        ["id": id, "h2hw": String(wins), "h2hl": String(1 - wins), "h2ht": "0", "pf": points]
    }
    private func game(_ winner: String, _ winnerScore: String, _ loser: String, _ loserScore: String) -> [String: Any] {
        ["franchise": [["id": winner, "score": winnerScore, "result": "W"],
                       ["id": loser, "score": loserScore, "result": "L"]]]
    }
}
