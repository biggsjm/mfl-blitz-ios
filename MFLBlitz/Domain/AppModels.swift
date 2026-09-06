import Foundation

struct LoginCredentials: Sendable {
    var username = ""
    var password = ""
    var leagueID = "41333"
    var season = 2026
}

struct LeagueWorkspace: Equatable, Sendable {
    let leagueID: String
    let season: Int
    let leagueName: String
    let franchiseID: String
    let franchiseName: String
    let baseURL: URL
    let week: Int
}

struct ScoresSnapshot: Equatable, Sendable {
    var week: Int
    var matchups: [Matchup]
    var lastUpdated: Date
    var isLive: Bool

    var featuredMatchup: Matchup? {
        matchups.first(where: { $0.isUserMatchup }) ?? matchups.first
    }
}

struct Matchup: Identifiable, Equatable, Sendable {
    let id: String
    var away: MatchupTeam
    var home: MatchupTeam
    var isUserMatchup: Bool
    var status: GameStatus

    var leaderID: String? {
        guard away.score != home.score else { return nil }
        return away.score > home.score ? away.id : home.id
    }
}

struct MatchupTeam: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var abbreviation: String
    var score: Double
    var projectedScore: Double?
    var playersRemaining: Int
    var accentSeed: Int
}

enum GameStatus: Equatable, Sendable {
    case pregame(Date?)
    case live(String)
    case final

    var label: String {
        switch self {
        case .pregame(let date):
            date?.formatted(date: .omitted, time: .shortened) ?? "Upcoming"
        case .live(let detail):
            detail
        case .final:
            "Final"
        }
    }

    var isLive: Bool {
        if case .live = self { return true }
        return false
    }
}

struct LineupSnapshot: Equatable, Sendable {
    var week: Int
    var players: [LineupPlayer]
    var requiredStarterCount: Int
    var positionRequirements: [LineupPositionRequirement]
    var requiredTiebreakerCount: Int
    var tiebreakerPlayerIDs: [String]
    var deadline: Date?
    var lastSubmitted: Date?

    var starters: [LineupPlayer] { players.filter(\.isStarter) }
    var bench: [LineupPlayer] { players.filter { !$0.isStarter } }
    var projectedTotal: Double? {
        let projections = starters.compactMap(\.projectedPoints)
        guard projections.count == starters.count else { return nil }
        return projections.reduce(0, +)
    }
    var hasLockedPlayers: Bool { players.contains(where: \.isLocked) }
}

struct LineupPositionRequirement: Identifiable, Equatable, Sendable {
    var id: String { position }
    var position: String
    var minimum: Int
    var maximum: Int
}

struct LineupPlayer: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var position: String
    var nflTeam: String
    var opponent: String
    var projectedPoints: Double?
    var seasonPoints: Double
    var isStarter: Bool
    var isLocked: Bool
    var injuryStatus: InjuryStatus?
    var gameTime: Date
}

enum InjuryStatus: String, Equatable, Sendable {
    case questionable = "Q"
    case doubtful = "D"
    case out = "OUT"
    case injuredReserve = "IR"

    var label: String {
        switch self {
        case .questionable: "Questionable"
        case .doubtful: "Doubtful"
        case .out: "Out"
        case .injuredReserve: "Injured reserve"
        }
    }
}

struct WaiverSnapshot: Equatable, Sendable {
    var availableBudget: Decimal
    var increment: Decimal
    var maxRounds: Int
    var candidates: [WaiverCandidate]
    var claims: [WaiverClaim]
    var processesAt: Date?
}

struct WaiverCandidate: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var position: String
    var nflTeam: String
    var rosteredPercent: Int
    var projectedPoints: Double?
    var seasonPoints: Double
    var trend: Int
    var injuryStatus: InjuryStatus?
}

struct WaiverClaim: Identifiable, Equatable, Sendable {
    let id: UUID
    var player: WaiverCandidate
    var bid: Decimal
    var dropPlayerID: String?
    var dropPlayerName: String?
    var round: Int
    var priority: Int

    init(
        id: UUID = UUID(),
        player: WaiverCandidate,
        bid: Decimal,
        dropPlayerID: String?,
        dropPlayerName: String?,
        round: Int,
        priority: Int = 1
    ) {
        self.id = id
        self.player = player
        self.bid = bid
        self.dropPlayerID = dropPlayerID
        self.dropPlayerName = dropPlayerName
        self.round = round
        self.priority = priority
    }
}

struct StandingRow: Identifiable, Equatable, Sendable {
    let id: String
    var rank: Int
    var name: String
    var abbreviation: String
    var division: String
    var wins: Int
    var losses: Int
    var ties: Int
    var pointsFor: Double
    var pointsAgainst: Double
    var streak: String
    var isUser: Bool
    var accentSeed: Int
}

struct BoardThread: Identifiable, Equatable, Sendable {
    let id: String
    var subject: String
    var author: String
    var preview: String
    var lastActivity: Date
    var replyCount: Int
    var isUnread: Bool
    var posts: [BoardPost]
}

struct BoardPost: Identifiable, Equatable, Sendable {
    let id: String
    var author: String
    var body: String
    var postedAt: Date
    var isUser: Bool
}

enum AppNotice: Equatable, Sendable {
    case success(String)
    case error(String)

    var message: String {
        switch self {
        case .success(let value), .error(let value): value
        }
    }
}

extension Optional where Wrapped == Double {
    var pointsText: String {
        guard let self else { return "—" }
        return self.formatted(.number.precision(.fractionLength(1)))
    }
}

extension Decimal {
    func isWholeMultiple(of increment: Decimal) -> Bool {
        guard increment > 0 else { return false }
        var quotient = self / increment
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, 0, .plain)
        return quotient == rounded
    }
}
