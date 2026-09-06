import Foundation

enum LiveWritePolicy {
    // Lineups have a review step and exact saved-starter verification.
    // MFL accepts tiebreakers but does not expose their saved state for readback.
    // Live writes require review and authoritative readback; unsupported league
    // waiver formats remain unavailable. Imports are never automatically retried.
    static let lineupsEnabled = true
    static let waiversEnabled = true
    static let boardEnabled = true
}

protocol LeagueRepository: Sendable {
    func signIn(with credentials: LoginCredentials) async throws -> LeagueWorkspace
    func loadWorkspace() async throws -> LeagueWorkspace
    func restoreSession() async throws -> LeagueWorkspace?
    func currentWeek() async throws -> Int
    func loadScores(week: Int) async throws -> ScoresSnapshot
    func refreshScores(week: Int) async throws -> ScoresSnapshot
    func loadLineup(week: Int) async throws -> LineupSnapshot
    func submitLineup(_ lineup: LineupSnapshot) async throws
    func loadWaivers() async throws -> WaiverSnapshot
    func submitWaivers(_ claims: [WaiverClaim], replacing baseline: [WaiverClaim]) async throws
    func loadStandings() async throws -> [StandingRow]
    func loadBoard() async throws -> [BoardThread]
    func loadThread(id: String) async throws -> BoardThread
    func postMessage(subject: String?, body: String, threadID: String?) async throws
    func pendingBoardPost() async throws -> PendingBoardPost?
    func reconcileBoardPost() async throws -> Bool
    func acknowledgeUnconfirmedPost() async throws
    func loadTrades() async throws -> TradeSnapshot
    func performTrade(_ command: TradeCommand) async throws -> TradeReceipt
    func pendingTradeAction() async throws -> PendingTradeAction?
    func reconcileTradeAction() async throws -> TradeReceipt
    func acknowledgeUnconfirmedTrade() async throws
    func loadTransactionActivity() async throws -> [TransactionActivity]
    func loadTeams(refresh: Bool) async throws -> [TeamSummary]
    func loadTeamRoster(franchiseID: String, lineupWeek: Int?, refresh: Bool) async throws -> TeamRosterSnapshot
    func loadPlayerDetail(playerID: String, refresh: Bool) async throws -> PlayerDetailSnapshot
    func loadSeasonSchedule() async throws -> SeasonScheduleSnapshot
    func loadPlayerAvailability(week: Int, refresh: Bool) async throws -> PlayerAvailabilitySnapshot
    func loadPlayerResearch(playerID: String, beforeWeek: Int?, contextWeek: Int) async throws -> PlayerResearchPage
    func loadWatchList(refresh: Bool) async throws -> WatchListSnapshot
    func setWatched(playerID: String, isWatched: Bool) async throws -> WatchListSnapshot
    func reconcileWatchList() async throws -> WatchListSnapshot
    func acknowledgeWatchList() async throws
    func loadRosterActionContext() async throws -> RosterActionContext
    func performRosterAction(_ request: RosterActionRequest, reviewed: RosterActionContext) async throws -> RosterActionReceipt
    func reconcileRosterAction() async throws -> RosterActionReceipt
    func acknowledgeRosterAction() async throws
    func pendingRosterAction() async throws -> PendingRosterAction?
    func signOut() async
}

extension LeagueRepository {
    func loadRosterActionContext() async throws -> RosterActionContext { throw RepositoryError.server("Roster actions are unavailable.") }
    func performRosterAction(_ request: RosterActionRequest, reviewed: RosterActionContext) async throws -> RosterActionReceipt { throw RepositoryError.server("Roster actions are unavailable.") }
    func reconcileRosterAction() async throws -> RosterActionReceipt { throw RepositoryError.server("Check your roster on MFL.") }
    func acknowledgeRosterAction() async throws { throw RepositoryError.server("Check your roster on MFL.") }
    func pendingRosterAction() async throws -> PendingRosterAction? { nil }
    func loadPlayerAvailability(week: Int, refresh: Bool) async throws -> PlayerAvailabilitySnapshot {
        throw RepositoryError.server("Player availability is unavailable.")
    }
    func loadPlayerResearch(playerID: String, beforeWeek: Int?, contextWeek: Int) async throws -> PlayerResearchPage {
        throw RepositoryError.server("Player research is unavailable.")
    }
    func loadWatchList(refresh: Bool) async throws -> WatchListSnapshot { throw RepositoryError.server("Watchlist unavailable.") }
    func setWatched(playerID: String, isWatched: Bool) async throws -> WatchListSnapshot { throw RepositoryError.server("Watchlist changes are unavailable.") }
    func reconcileWatchList() async throws -> WatchListSnapshot { try await loadWatchList(refresh: true) }
    func acknowledgeWatchList() async throws { throw RepositoryError.server("Watchlist changes are unavailable.") }
    func loadTeams(refresh: Bool) async throws -> [TeamSummary] {
        throw RepositoryError.server("Team details are unavailable in this session.")
    }
    func loadTeamRoster(franchiseID: String, lineupWeek: Int?, refresh: Bool) async throws -> TeamRosterSnapshot {
        throw RepositoryError.server("This roster is unavailable in this session.")
    }
    func loadPlayerDetail(playerID: String, refresh: Bool) async throws -> PlayerDetailSnapshot {
        throw RepositoryError.server("Player details are unavailable in this session.")
    }
    func loadSeasonSchedule() async throws -> SeasonScheduleSnapshot {
        throw RepositoryError.server("The season schedule is unavailable in this session.")
    }
    func loadTrades() async throws -> TradeSnapshot { TradeSnapshot() }
    func performTrade(_ command: TradeCommand) async throws -> TradeReceipt { throw RepositoryError.server("Trades are unavailable in this session.") }
    func pendingTradeAction() async throws -> PendingTradeAction? { nil }
    func reconcileTradeAction() async throws -> TradeReceipt { TradeReceipt(confirmed: false, message: "Check this trade on MFL.") }
    func acknowledgeUnconfirmedTrade() async throws {}
    func loadTransactionActivity() async throws -> [TransactionActivity] { [] }
    func restoreSession() async throws -> LeagueWorkspace? { nil }
    func currentWeek() async throws -> Int { try await loadWorkspace().week }
    func pendingBoardPost() async throws -> PendingBoardPost? { nil }
    func reconcileBoardPost() async throws -> Bool { false }
    func acknowledgeUnconfirmedPost() async throws {}
    func refreshScores(week: Int) async throws -> ScoresSnapshot {
        try await loadScores(week: week)
    }
}

enum RepositoryError: LocalizedError {
    case invalidCredentials
    case missingSession
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "MFL did not recognize that username and password."
        case .missingSession:
            "Your MFL session has expired. Sign in again to continue."
        case .server(let message):
            message
        }
    }
}
