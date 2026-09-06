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
    var lineupWeek: Int? = nil
    var weekIsConfirmed: Bool = true
}

struct ScoresSnapshot: Equatable, Sendable {
    var week: Int
    var matchups: [Matchup]
    var lastUpdated: Date
    var isLive: Bool
    var scorePrecision: Int = 1

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
    var starters: [MatchupPlayer] = []
    var bench: [MatchupPlayer] = []
    var unclassifiedPlayers: [MatchupPlayer] = []
    var artworkURLs: [URL] = []

    var players: [MatchupPlayer] { starters + bench + unclassifiedPlayers }
}

struct MatchupPlayer: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var position: String
    var nflTeam: String
    /// Nil when MFL omitted the player's scoring value from a partial response.
    var livePoints: Double?
    var lineupStatus: MatchupLineupStatus
    /// MFL reports 3,600 before kickoff, counts down during regulation, and
    /// reaches zero when the player's NFL game is complete. Nil means MFL did
    /// not include a clock for this player.
    var gameSecondsRemaining: Int?
    var statLine: String?
    var projectedPoints: Double? = nil
    /// A derived league slot, distinct from the player's actual NFL position.
    var lineupSlot: String? = nil

    var gameState: MatchupPlayerGameState {
        guard let gameSecondsRemaining else { return .unknown }
        return switch gameSecondsRemaining {
        case 3_600:
            .pregame
        case 1 ..< 3_600:
            .live
        case 0:
            .final
        default:
            .unknown
        }
    }
}

enum MatchupLineupStatus: Equatable, Sendable {
    case starter
    case bench
    case unknown
}

enum MatchupPlayerGameState: Equatable, Sendable {
    case pregame
    case live
    case final
    case unknown
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
    var serverStarterPlayerIDs: Set<String> = []
    var projectionNote: String? = nil
    var editState: LineupEditState = .unavailable(
        "MFL hasn’t returned a complete saved lineup for this week."
    )

    var starters: [LineupPlayer] { players.filter(\.isStarter) }
    var bench: [LineupPlayer] { players.filter { !$0.isStarter } }
    var projectedTotal: Double? {
        let projections = starters.compactMap(\.projectedPoints)
        guard !starters.isEmpty, projections.count == starters.count else { return nil }
        return projections.reduce(0, +)
    }
    var hasLockedPlayers: Bool { players.contains(where: \.isLocked) }

    /// MFL returns starter IDs, not named FLEX assignments. Reserve each
    /// position's required minimum first; the remaining starters fill flex.
    /// These are presentation slots only—the submitted payload stays player IDs.
    var startingSlots: [LineupStartingSlot] {
        guard hasUsablePositionLimits else { return starters.map { LineupStartingSlot(player: $0, isFlex: false) } }
        let flexIDs = LineupSlotAllocation.flexPlayerIDs(starters.map { ($0.id, $0.position) },
            requirements: positionRequirements, starterCount: requiredStarterCount)
        let required = positionRequirements.flatMap { rule in
            starters.filter { $0.position == rule.position && !flexIDs.contains($0.id) }
        }
        let requiredIDs = Set(required.map(\.id))
        let remaining = starters.filter { !requiredIDs.contains($0.id) }
        return required.map { LineupStartingSlot(player: $0, isFlex: false) }
            + remaining.map { LineupStartingSlot(player: $0, isFlex: flexPositions.contains($0.position)) }
    }

    var flexPositions: [String] {
        guard hasUsablePositionLimits,
              positionRequirements.map(\.minimum).reduce(0, +) < requiredStarterCount else { return [] }
        return positionRequirements.filter { $0.maximum > $0.minimum }.map(\.position)
    }

    func replacementPositions(for starterID: String) -> [String] {
        guard let slot = startingSlots.first(where: { $0.id == starterID }) else { return [] }
        guard slot.isFlex else { return [slot.player.position] }
        // A FLEX replacement must satisfy *all* position limits, not just the
        // incoming position's maximum. Never hard-code RB/WR/TE or permit a QB
        // unless this league explicitly allows an additional quarterback.
        guard starters.count == requiredStarterCount else { return [] }
        let others = starters.filter { $0.id != starterID }
        return flexPositions.filter { position in
            positionRequirements.allSatisfy { rule in
                let count = others.count { $0.position == rule.position } + (position == rule.position ? 1 : 0)
                return (rule.minimum...rule.maximum).contains(count)
            }
        }
    }

    private var hasUsablePositionLimits: Bool {
        guard !positionRequirements.isEmpty,
              Set(positionRequirements.map(\.position)).count == positionRequirements.count,
              positionRequirements.allSatisfy({ !$0.position.isEmpty && $0.minimum >= 0 && $0.maximum >= $0.minimum }),
              starters.allSatisfy({ player in positionRequirements.contains { $0.position == player.position } }) else { return false }
        let minimum = positionRequirements.map(\.minimum).reduce(0, +)
        let maximum = positionRequirements.map(\.maximum).reduce(0, +)
        return (minimum...maximum).contains(requiredStarterCount)
    }
}

struct LineupStartingSlot: Identifiable, Equatable, Sendable {
    var id: String { player.id }
    let player: LineupPlayer
    let isFlex: Bool
    var label: String { isFlex ? "FLEX" : player.position }
}

enum LineupEditState: Equatable, Sendable {
    case editable
    case unavailable(String)

    var allowsEditing: Bool {
        if case .editable = self { return true }
        return false
    }

    var unavailableMessage: String? {
        guard case .unavailable(let message) = self else { return nil }
        return message
    }
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

enum InjuryStatus: String, Codable, Equatable, Sendable {
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
    var minimumBid: Decimal = 0
    var unavailableReason: String? = "Refresh waivers to check availability."
    var results: [WaiverResult] = []
    var resultsUnavailable = false
    var projectionWeek: Int? = nil
    var projectionNote: String? = nil
}

struct WaiverResult: Identifiable, Equatable, Sendable {
    var id: String
    var franchise: String
    var description: String
    var date: Date?
}

struct WaiverCandidate: Identifiable, Codable, Equatable, Sendable {
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

struct WaiverClaim: Identifiable, Codable, Equatable, Sendable {
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
    var artworkURLs: [URL] = []
    var ownerName: String? = nil
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

extension Double {
    var pointsText: String {
        pointsText(precision: 1)
    }

    func pointsText(precision: Int) -> String {
        let safePrecision = min(max(precision, 0), 4)
        return formatted(.number.precision(.fractionLength(safePrecision)))
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
