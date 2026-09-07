import Foundation

struct PlayerHealth: Equatable, Sendable {
    let status: String
    var details: String?
    var shortLabel: String {
        switch status.uppercased() {
        case "QUESTIONABLE": "Q"
        case "DOUBTFUL": "D"
        case "OUT": "Out"
        case "INACTIVE": "Inactive"
        case "RETIRED": "Retired"
        default: status
        }
    }
    var needsAttention: Bool { ["OUT", "INACTIVE", "IR", "RETIRED", "SUSPENDED"].contains(status.uppercased()) }
    /// Conservative native IR scope, verified for Champion Hall. MFL still
    /// enforces league rules on submission; other injury tags do not qualify.
    var qualifiesForNativeIR: Bool {
        ["OUT", "IR"].contains(status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }
}

struct NFLGameContext: Equatable, Sendable {
    let opponent: String
    let isHome: Bool?
    let kickoff: Date?
    var opponentLabel: String { isHome.map { "\($0 ? "vs" : "@") \(opponent)" } ?? opponent }
}

struct PlayerAvailabilitySnapshot: Equatable, Sendable {
    let scope: String
    let week: Int
    var injuries: [String: PlayerHealth] = [:]
    var games: [String: NFLGameContext] = [:]
    var byeWeeks: [String: Int] = [:]
    var injuryUpdatedAt: Date?
    var issues: [String] = []
    var fetchedAt = Date()
}

struct PlayerHistoryWeek: Identifiable, Equatable, Sendable {
    let week: Int
    var points: Double?
    var unavailable = false
    var opponentLabel: String?
    var id: Int { week }
}

/// Independent of paged game history so the primary player card never waits
/// for older weeks. Values use this league's scoring; nil is not a zero.
struct PlayerSeasonSummary: Equatable, Sendable {
    let scope: String
    let playerID: String
    var total: Double?
    var average: Double?
    var issues: [String] = []
}

struct PlayerResearchPage: Equatable, Sendable {
    let scope: String
    let playerID: String
    let completedWeek: Int
    var total: Double?
    var average: Double?
    var weeks: [PlayerHistoryWeek]
    var nextBeforeWeek: Int?
    var opponentPointsAllowed: Double?
    var opponentName: String?
    /// Opponents intentionally follow the current NFL team's schedule, not a
    /// historical player-team assignment. Surface that limitation in the UI.
    var scheduleTeam: String?
    var issues: [String] = []
}

struct WatchListSnapshot: Equatable, Sendable {
    let scope: String
    var players: [PlayerIdentity]
    var checkedAt = Date()
    var pending: PendingWatchAction?
    var playerIDs: Set<String> { Set(players.map(\.id)) }
}

struct PendingWatchAction: Codable, Equatable, Sendable {
    let playerID: String
    let isWatched: Bool
    let startedAt: Date
}
