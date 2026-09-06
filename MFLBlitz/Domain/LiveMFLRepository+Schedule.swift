import Foundation
import MFLCore

extension LiveMFLRepository {
    /// The shared display model owns schedule freshness and only calls this
    /// method when its one session-scoped snapshot needs a network refresh.
    func loadSeasonSchedule() async throws -> SeasonScheduleSnapshot {
        let (client, _, workspace) = try requireSession()
        async let schedule = client.schedule(refreshPolicy: .reloadIgnoringCache)
        async let settings = client.league()
        async let status = confirmedScheduleStatus(from: client)
        let (source, league, clock) = try await (schedule, settings, status)
        try Task.checkCancellation()
        return SeasonScheduleSnapshot(source: source, season: workspace.season,
            leagueID: workspace.leagueID, startWeek: league.startWeek, endWeek: league.endWeek,
            lastRegularSeasonWeek: league.lastRegularSeasonWeek,
            currentWeek: clock?.currentWeek, completedWeek: clock?.completedWeek,
            fetchedAt: Date())
    }

    private func confirmedScheduleStatus(from client: MFLClient) async -> MFLSeasonStatus? {
        try? await client.seasonStatus()
    }
}
