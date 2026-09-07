import Foundation
import Testing

@testable import MFLCore

struct StandingsRankingTests {
    private func row(
        _ id: String, _ wins: Int, _ losses: Int, _ ties: Int = 0,
        points: String = "100", division: String = "0-0-0"
    ) throws -> MFLStanding {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id, "h2hw": String(wins),
            "h2hl": String(losses), "h2ht": String(ties), "pf": points, "divwlt": division,
        ])
        return try JSONDecoder().decode(MFLStanding.self, from: data)
    }
    private func game(_ winner: String, _ loser: String) -> MFLScheduleMatchup {
        .init(franchises: [
            .init(franchiseID: winner, score: 100, result: "W"),
            .init(franchiseID: loser, score: 90, result: "L"),
        ])
    }

    @Test("Rank follows configured metrics, not API array order or franchise ID")
    func metricOrder() throws {
        let rows = try [row("0001", 1, 2), row("0002", 3, 0), row("0003", 2, 1)]
        for order in [rows, Array(rows.reversed())] {
            let result = MFLStandingsRanking.resolve(order, criteria: "PCT,PTS,", hasResults: true)
            #expect(result.issue == nil)
            #expect(result.places["0002"]?.position == 1)
            #expect(result.places["0003"]?.position == 2)
            #expect(result.places["0001"]?.position == 3)
        }
    }

    @Test("Identical records are separated by points before declaring a tie")
    func pointsBreakRecordTie() throws {
        let rows = try [row("a", 1, 1, points: "200.5"), row("b", 1, 1, points: "201")]
        let result = MFLStandingsRanking.resolve(rows, criteria: "PCT,PTS", hasResults: true)
        #expect(result.places["b"] == .init(position: 1))
        #expect(result.places["a"] == .init(position: 2))
    }

    @Test("True exhausted ties use competition ranks, including the skipped place")
    func confirmedTie() throws {
        let rows = try [row("a", 2, 0), row("b", 2, 0), row("c", 0, 2)]
        let result = MFLStandingsRanking.resolve(rows, criteria: "PCT,PTS", hasResults: true)
        #expect(result.places["a"] == .init(position: 1, isTied: true))
        #expect(result.places["b"] == .init(position: 1, isTied: true))
        #expect(result.places["c"] == .init(position: 3))
    }

    @Test("Game ties count as half wins, not ranking ties")
    func halfWins() throws {
        let rows = try [row("a", 7, 2, 2, points: "200"), row("b", 8, 3, points: "201")]
        let result = MFLStandingsRanking.resolve(rows, criteria: "PCT,PTS", hasResults: true)
        #expect(result.places["b"] == .init(position: 1))
    }

    @Test("H2H uses the pair's confirmed result even when tied scores were manually broken")
    func pairwiseHeadToHead() throws {
        let rows = try [row("a", 1, 1, points: "500"), row("b", 1, 1, points: "100")]
        let schedule = MFLSchedule(weeks: [
            .init(
                week: 1,
                matchups: [
                    .init(franchises: [
                        .init(franchiseID: "a", score: 100, result: "L"),
                        .init(franchiseID: "b", score: 100, result: "W"),
                    ])
                ]),
            .init(week: 2, matchups: [game("a", "c"), game("d", "b")]),
        ])
        let result = MFLStandingsRanking.resolve(
            rows, criteria: "PCT,H2H,PTS", hasResults: true,
            schedule: schedule, completedWeek: 2)
        #expect(result.places["b"] == .init(position: 1))
    }

    @Test("Circular head-to-head results never create a fabricated winner")
    func headToHeadCycle() throws {
        let rows = try [row("a", 1, 1), row("b", 1, 1), row("c", 1, 1)]
        let bye: (String) -> MFLScheduleMatchup = { .init(franchises: [.init(franchiseID: $0)]) }
        let schedule = MFLSchedule(weeks: [
            .init(week: 1, matchups: [game("a", "b"), bye("c")]),
            .init(week: 2, matchups: [game("b", "c"), bye("a")]),
            .init(week: 3, matchups: [game("c", "a"), bye("b")]),
        ])
        let result = MFLStandingsRanking.resolve(
            rows, criteria: "PCT,H2H,PTS", hasResults: true,
            schedule: schedule, completedWeek: 3)
        #expect(result.issue == .ambiguous && result.places.isEmpty)
    }

    @Test("Missing, partial, preliminary, duplicate or wrong-horizon H2H results are not guesses")
    func missingHeadToHead() throws {
        let rows = try [row("a", 1, 1), row("b", 1, 1)]
        let schedules: [MFLSchedule?] = [
            nil, .init(weeks: []),
            .init(weeks: [.init(week: 1, matchups: [game("a", "b")])]),
            .init(weeks: [.init(week: 1, matchups: [game("a", "b"), game("a", "b")])]),
        ]
        for schedule in schedules {
            let result = MFLStandingsRanking.resolve(
                rows, criteria: "PCT,H2H,PTS", hasResults: true,
                schedule: schedule, completedWeek: 1)
            #expect(result.issue == .headToHeadUnavailable && result.places.isEmpty)
        }
    }

    @Test("Future placeholder ties never become completed H2H results")
    func futureTie() throws {
        let rows = try [row("a", 0, 0, 1), row("b", 0, 0, 1)]
        let schedule = MFLSchedule(weeks: [
            .init(
                week: 1,
                matchups: [
                    .init(franchises: [
                        .init(franchiseID: "a", result: "T"), .init(franchiseID: "b", result: "T"),
                    ])
                ])
        ])
        #expect(
            MFLStandingsRanking.resolve(
                rows, criteria: "PCT,H2H", hasResults: true,
                schedule: schedule, completedWeek: 1
            ).issue == .headToHeadUnavailable)
    }

    @Test("Preseason does not assign first place, but a zero-record team can be ranked after others play")
    func resultsState() throws {
        let zeros = try [row("a", 0, 0), row("b", 0, 0)]
        #expect(!MFLStandingsRanking.hasReportedResults(zeros, headToHead: true, completedWeek: 0, startWeek: 1))
        #expect(MFLStandingsRanking.resolve(zeros, criteria: "PCT,PTS", hasResults: false).places.isEmpty)
        let played = try [row("a", 1, 0), row("b", 0, 0)]
        #expect(MFLStandingsRanking.hasReportedResults(played, headToHead: true, completedWeek: 0, startWeek: 1))
        #expect(MFLStandingsRanking.resolve(played, criteria: "PCT,PTS", hasResults: true).places["b"]?.position == 2)
    }

    @Test("Points-only leagues do not depend on win-loss records")
    func pointsOnly() throws {
        let rows = try [row("a", 0, 0, points: "0"), row("b", 0, 0, points: "-2")]
        #expect(MFLStandingsRanking.hasReportedResults(rows, headToHead: false, completedWeek: 1, startWeek: 1))
        #expect(MFLStandingsRanking.resolve(rows, criteria: "PTS", hasResults: true).places["a"]?.position == 1)
    }

    @Test("Unknown/custom criteria, duplicate IDs and missing numeric data stay unranked")
    func invalidInputs() throws {
        let a = try row("a", 1, 1)
        #expect(MFLStandingsRanking.resolve([a, a], criteria: "PCT", hasResults: true).issue == .unavailable)
        let b = try row("b", 1, 1, points: "")
        #expect(MFLStandingsRanking.resolve([a, b], criteria: "PCT,PTS", hasResults: true).issue == .unavailable)
        for criteria: String? in [nil, "", "CUSTOM", "PCT,VICTORY_POINTS"] {
            #expect(MFLStandingsRanking.resolve([a, b], criteria: criteria, hasResults: true).issue == .unsupported)
        }
    }

    @Test("Division percentage breaks remaining ties with exact division records")
    func divisionPercentage() throws {
        let rows = try [row("a", 2, 2, division: "1-1-0"), row("b", 2, 2, division: "2-0-0")]
        #expect(
            MFLStandingsRanking.resolve(rows, criteria: "PCT,PTS,DIVPCT", hasResults: true).places["b"]?.position == 1)
        for malformed in ["-1-1-0", "1-0", "1-1-0-0", "unknown"] {
            let invalid = try row("c", 2, 2, division: malformed)
            #expect(
                MFLStandingsRanking.resolve([rows[0], invalid], criteria: "DIVPCT", hasResults: true).issue
                    == .unavailable)
        }
    }
}
