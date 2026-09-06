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
    func signOut() async
}

extension LeagueRepository {
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
