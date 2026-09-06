import Foundation
import MFLCore

extension SampleData {
    /// Deterministic synthetic pairings for preview mode. These are not the
    /// connected league's actual season schedule.
    static var seasonSchedule: SeasonScheduleSnapshot {
        let ids = standings.map(\.id).sorted()
        guard ids.count >= 2 else {
            return SeasonScheduleSnapshot(source: MFLSchedule(weeks: []),
                season: workspace.season, leagueID: workspace.leagueID)
        }
        var rotation = ids
        if rotation.count % 2 != 0 { rotation.append("BYE") }
        var weeks: [MFLScheduleWeek] = []
        for week in 1...14 {
            var matchups = (0..<(rotation.count / 2)).map { pair in
                MFLScheduleMatchup(franchises: [
                    MFLScheduleFranchise(franchiseID: rotation[pair], isHome: false, result: "T"),
                    MFLScheduleFranchise(franchiseID: rotation[rotation.count - 1 - pair], isHome: true, result: "T")
                ])
            }
            if week == workspace.week {
                matchups = scores.matchups.map { matchup in
                    MFLScheduleMatchup(franchises: [
                        MFLScheduleFranchise(franchiseID: matchup.away.id, isHome: false),
                        MFLScheduleFranchise(franchiseID: matchup.home.id, isHome: true)
                    ])
                }
            }
            weeks.append(MFLScheduleWeek(week: week, matchups: matchups))
            let last = rotation.removeLast()
            rotation.insert(last, at: 1)
        }
        weeks += (15...17).map { MFLScheduleWeek(week: $0, matchups: []) }
        return SeasonScheduleSnapshot(source: MFLSchedule(weeks: weeks),
            season: workspace.season, leagueID: workspace.leagueID,
            startWeek: 1, endWeek: 17, lastRegularSeasonWeek: 14,
            currentWeek: 1, completedWeek: 0, fetchedAt: Date())
    }
}

extension DemoLeagueRepository {
    func loadSeasonSchedule() async throws -> SeasonScheduleSnapshot {
        try Task.checkCancellation()
        return SampleData.seasonSchedule
    }
}
