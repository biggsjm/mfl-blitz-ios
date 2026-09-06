import Foundation

/// The public, season-specific clock. Never derive a week from a device date.
public struct MFLSeasonStatus: Decodable, Equatable, Sendable {
    public let year: Int
    public let currentWeek: Int
    public let lineupWeek: Int
    public let completedWeek: Int
    public let liveScoringWeek: Int

    public init(from decoder: any Decoder) throws {
        let root = try MFLJSONValue(from: decoder)
        guard let status = root.objectValue?["mfl_status"]?.objectValue,
              let year = status.mflInt("year"),
              let weeks = status["weeks"]?.objectValue,
              let current = weeks.mflInt("CurrentWeek"),
              let lineup = weeks.mflInt("LineupWeek"),
              let completed = weeks.mflInt("CompletedWeek"),
              let live = weeks.mflInt("LiveScoringWeek"),
              (0...21).contains(current), (0...21).contains(lineup),
              (0...21).contains(completed), (0...21).contains(live)
        else { throw MFLCoreError.invalidResponse }
        self.year = year
        currentWeek = max(1, current)
        lineupWeek = max(1, lineup)
        completedWeek = completed
        liveScoringWeek = live
    }
}

public struct MFLWeeklyResultsResponse: Decodable, Sendable {
    public let weeklyResults: MFLLiveScoring
}
