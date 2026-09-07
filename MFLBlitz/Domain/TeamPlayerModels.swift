import Foundation

enum TeamDetailSection: String, CaseIterable, Hashable, Sendable, Identifiable {
    case roster = "Roster"
    case schedule = "Schedule"
    case watchlist = "Watchlist"
    var id: Self { self }
}

struct TeamSummary: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var abbreviation: String
    var ownerName: String? = nil
    var artworkURLs: [URL] = []
    var accentSeed: Int = 0
}

struct PlayerIdentity: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var position: String? = nil
    var nflTeam: String? = nil

    var metadata: String {
        [position, nflTeam].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum DetailReadIssue: String, Codable, Identifiable, Equatable, Sendable {
    case playerNames
    case biography
    case ownership
    case lineupAssignments
    case seasonPoints

    var id: Self { self }

    var message: String {
        switch self {
        case .playerNames: "Some player information could not be loaded."
        case .biography: "Player biography could not be loaded."
        case .ownership: "Current ownership could not be confirmed."
        case .lineupAssignments: "Starting and bench assignments could not be confirmed."
        case .seasonPoints: "Season points could not be refreshed."
        }
    }
}

/// Membership describes the current roster, independently of a submitted lineup.
enum RosterMembership: Codable, Equatable, Sendable {
    case active
    case injuredReserve
    case taxiSquad
    case unknown(String)

    init(rawValue: String) {
        switch rawValue.uppercased() {
        case "ROSTER", "R": self = .active
        case "INJURED_RESERVE", "IR": self = .injuredReserve
        case "TAXI_SQUAD", "TS": self = .taxiSquad
        default: self = .unknown(rawValue)
        }
    }
}

enum PlayerLineupAssignment: Codable, Equatable, Sendable {
    case starter
    case nonstarter
    case rostered
    case injuredReserve
    case taxiSquad
    case unknown(String)

    init(rawValue: String) {
        switch rawValue.uppercased() {
        case "S": self = .starter
        case "NS": self = .nonstarter
        case "R": self = .rostered
        case "IR": self = .injuredReserve
        case "TS": self = .taxiSquad
        default: self = .unknown(rawValue)
        }
    }

    var label: String {
        switch self {
        case .starter: "Starting"
        case .nonstarter: "Bench"
        case .rostered: "Rostered"
        case .injuredReserve: "Injured reserve"
        case .taxiSquad: "Taxi squad"
        case .unknown: "Roster status unavailable"
        }
    }
}

enum TeamRosterGroup: String, CaseIterable, Identifiable, Sendable {
    case starters = "Starting"
    case bench = "Bench"
    case roster = "Roster"
    case injuredReserve = "Injured reserve"
    case taxiSquad = "Taxi squad"
    var id: Self { self }
}

struct RosterPlayerSummary: Codable, Identifiable, Equatable, Sendable {
    var identity: PlayerIdentity
    var membership: RosterMembership
    var lineupAssignment: PlayerLineupAssignment? = nil
    var salary: Decimal? = nil
    var contractYear: Int? = nil
    var contractStatus: String? = nil
    var seasonPoints: Double? = nil

    var id: String { identity.id }
    var positionGroup: String {
        let value = identity.position?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return value.isEmpty ? "Other" : value
    }

    var group: TeamRosterGroup {
        switch membership {
        case .injuredReserve: return .injuredReserve
        case .taxiSquad: return .taxiSquad
        case .unknown: return .roster
        case .active:
            switch lineupAssignment {
            case .starter: return .starters
            case .nonstarter: return .bench
            // Reserve membership remains authoritative over week-specific assignments.
            default: return .roster
            }
        }
    }
}

struct TeamRosterSnapshot: Codable, Equatable, Sendable {
    let scope: String
    var team: TeamSummary
    var players: [RosterPlayerSummary]
    var lineupWeek: Int?
    var issues: [DetailReadIssue] = []
    /// When this aggregate was assembled; NOT the freshness of its cached sources.
    var assembledAt: Date = Date()
    /// Only set after an explicit uncached roster request succeeds.
    var rosterVerifiedAt: Date? = nil

    func players(in group: TeamRosterGroup) -> [RosterPlayerSummary] {
        players.filter { $0.group == group }.sorted {
            let left = $0.identity.position ?? ""
            let right = $1.identity.position ?? ""
            if left != right { return left.localizedStandardCompare(right) == .orderedAscending }
            return $0.identity.name.localizedStandardCompare($1.identity.name) == .orderedAscending
        }
    }

    var positionGroups: [String] {
        let order = ["QB", "RB", "WR", "TE", "K", "PK", "DEF", "DT", "DE", "DL", "LB", "CB", "S", "DB"]
        return Set(players.map(\.positionGroup)).sorted {
            let left = order.firstIndex(of: $0) ?? order.count
            let right = order.firstIndex(of: $1) ?? order.count
            return left != right ? left < right : $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    func players(at position: String) -> [RosterPlayerSummary] {
        players.filter { $0.positionGroup == position }.sorted {
            let left = $0.seasonPoints.flatMap { $0.isFinite ? $0 : nil }
            let right = $1.seasonPoints.flatMap { $0.isFinite ? $0 : nil }
            if let left, let right, left != right { return left > right }
            if (left == nil) != (right == nil) { return left != nil }
            let names = $0.identity.name.localizedStandardCompare($1.identity.name)
            return names == .orderedSame ? $0.id < $1.id : names == .orderedAscending
        }
    }
}

struct PlayerOwnershipAssignment: Identifiable, Equatable, Sendable {
    var team: TeamSummary
    var status: PlayerLineupAssignment
    var id: String { team.id }
}

struct PlayerOwnership: Equatable, Sendable {
    var assignments: [PlayerOwnershipAssignment]
    /// Availability is for this franchise's acquisition context. In duplicate-player
    /// leagues, it can coexist with ownership by other franchises.
    var availabilityFranchiseID: String
    var isFreeAgent: Bool?
    var cannotAdd: Bool?
    /// This is an acquisition lock, never a lineup lock.
    var acquisitionLocked: Bool?
    /// Preserve the decoder's strict decision, including missing vs malformed
    /// restriction flags. This is not a substitute for fresh write preflight.
    var canAddImmediately: Bool

    func allowsImmediateAdd(for franchiseID: String) -> Bool {
        availabilityFranchiseID == franchiseID && isFreeAgent == true
            && assignments.isEmpty && cannotAdd != true && acquisitionLocked != true
            && canAddImmediately
    }

    var acquisitionRestriction: String? {
        guard isFreeAgent == true else { return nil }
        // MFL's generic acquisition flags do not identify the reason or unlock
        // time. Do not label every restriction as a waiver or kickoff lock.
        if acquisitionLocked == true { return "Locked for adds" }
        if cannotAdd == true { return "Adding unavailable" }
        if !canAddImmediately { return "Add availability unconfirmed" }
        return nil
    }
}

struct PlayerBio: Equatable, Sendable {
    var jerseyNumber: String? = nil
    var birthDate: Date? = nil
    var height: String? = nil
    var weight: String? = nil
    var draftYear: Int? = nil
    var draftRound: Int? = nil

    var isEmpty: Bool {
        jerseyNumber == nil && birthDate == nil && height == nil && weight == nil
            && draftYear == nil && draftRound == nil
    }

    static func parseBirthDate(_ raw: String?, now: Date = Date()) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for format in ["yyyy-MM-dd", "MM/dd/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw), formatter.string(from: date) == raw, date <= now,
               formatter.calendar.component(.year, from: date) >= 1900 { return date }
        }
        return nil
    }
}

struct PlayerDetailSnapshot: Equatable, Sendable {
    let scope: String
    var identity: PlayerIdentity
    var bio: PlayerBio? = nil
    var ownership: PlayerOwnership? = nil
    var issues: [DetailReadIssue] = []
    var assembledAt: Date = Date()
    /// Only set after an explicit uncached ownership request succeeds.
    var ownershipVerifiedAt: Date? = nil
}

/// A displayed week's metrics must have a real source and an exact matching week.
struct PlayerWeekMetrics: Equatable, Sendable {
    let week: Int
    var points: Double?
    var projection: Double?
    var statLine: String?

    static func matching(playerID: String, week: Int, scores: ScoresSnapshot,
                         lineup: LineupSnapshot, waivers: WaiverSnapshot,
                         history: PlayerResearchPage? = nil, scope: String? = nil) -> Self? {
        var points: Double?
        var pointsConflict = false
        var projection: Double?
        var statLine: String?
        if scores.week == week, scores.lastUpdated != .distantPast {
            let players = scores.matchups.flatMap { $0.away.players + $0.home.players }.filter { $0.id == playerID }
            // Doubleheaders/duplicate leagues can repeat a player. Conflicting
            // points stay unavailable; never select an arbitrary team's score.
            let knownPoints = Set(players.compactMap(\.livePoints).filter(\.isFinite))
            pointsConflict = knownPoints.count > 1
            if knownPoints.count == 1 { points = knownPoints.first }
            let knownProjections = Set(players.compactMap(\.projectedPoints).filter(\.isFinite))
            if knownProjections.count == 1 { projection = knownProjections.first }
            let lines = Set(players.compactMap(\.statLine).filter { !$0.isEmpty })
            if lines.count == 1 { statLine = lines.first }
        }
        if projection == nil, lineup.week == week,
           let value = lineup.players.first(where: { $0.id == playerID })?.projectedPoints, value.isFinite {
            projection = value
        }
        if projection == nil, waivers.projectionWeek == week,
           let value = waivers.candidates.first(where: { $0.id == playerID })?.projectedPoints, value.isFinite {
            projection = value
        }
        if points == nil, !pointsConflict, let scope, let history, history.scope == scope, history.playerID == playerID {
            let rows = history.weeks.filter { $0.week == week }
            if rows.count == 1, !rows[0].unavailable, let value = rows[0].points, value.isFinite {
                points = value
            }
        }
        guard points != nil || projection != nil || statLine != nil else { return nil }
        return Self(week: week, points: points, projection: projection, statLine: statLine)
    }
}
