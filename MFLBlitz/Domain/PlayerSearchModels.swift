import Foundation
import MFLCore

/// A daily, local index. No query text is sent to MFL.
struct PlayerSearchIndex: Sendable {
    private struct Entry: Sendable {
        let player: PlayerIdentity
        let name: String
        let nameTokens: [String]
        let terms: String
        let teamCode: String?
        let position: String?
        let isTeamUnit: Bool
    }
    private let entries: [Entry]
    let playersByID: [String: PlayerIdentity]

    init(players: [PlayerIdentity], eligiblePositions: Set<String>? = nil) {
        var unique: [String: PlayerIdentity] = [:]
        for player in players where !player.id.isEmpty {
            // Keep missing positions discoverable; don't invent eligibility.
            if let eligiblePositions, let position = player.position, !position.isEmpty,
               !eligiblePositions.contains(PlayerSearchPositions.canonical(position)) { continue }
            unique[player.id] = player
        }
        playersByID = unique
        entries = unique.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }.map { player in
            let name = Self.normalize(player.name)
            var nameParts = name.split(separator: " ").map(String.init)
            if nameParts.count > 1, let suffix = nameParts.last,
               ["jr", "sr", "ii", "iii", "iv", "v"].contains(suffix) { nameParts.removeLast() }
            return Entry(player: player, name: name, nameTokens: nameParts,
                  terms: Self.normalize("\(player.name) \(player.metadata) \(PlayerSearchTeams.team(for: player.nflTeam)?.searchTerms ?? "")"),
                  teamCode: PlayerSearchTeams.canonicalCode(player.nflTeam),
                  position: player.position.map(PlayerSearchPositions.canonical),
                  isTeamUnit: PlayerSearchPositions.isTeamUnit(player.position))
        }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    func search(_ query: String, limit: Int = 60,
                ranking: PlayerSearchRankingContext = .init()) -> PlayerSearchResults {
        let normalized = Self.normalize(query)
        let exactPosition = PlayerSearchPositions.canonical(query)
        let tokens = PlayerSearchPositions.known.contains(exactPosition)
            ? [exactPosition.lowercased()] : normalized.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return PlayerSearchResults(players: [], total: 0) }
        var matches: [(entry: Entry, nameRank: Int, alphabeticRank: Int)] = []
        // A recognized NFL code/position is a field match, not a substring of
        // someone's name (NE must not include every player named Jones).
        let teamCodes = tokens.compactMap(PlayerSearchTeams.canonicalCode)
        let positionTokens = tokens.filter { PlayerSearchPositions.known.contains(PlayerSearchPositions.canonical($0)) }
        let otherTokens = tokens.filter {
            PlayerSearchTeams.canonicalCode($0) == nil && !positionTokens.contains($0)
        }
        for (offset, entry) in entries.enumerated() where teamCodes.allSatisfy({ entry.teamCode == $0 })
            && positionTokens.allSatisfy({ PlayerSearchPositions.expanded($0).contains(entry.position ?? "") }) {
            let nameRank: Int
            if otherTokens.isEmpty {
                nameRank = 3
            } else if entry.name == normalized || otherTokens.sorted() == entry.nameTokens.sorted() {
                // Also recognize MFL's last, first order and omitted suffixes.
                nameRank = 0
            } else if otherTokens.allSatisfy({ entry.nameTokens.contains($0) }) {
                // First and last names are equally strong: both Hunter Henry
                // and Travis Hunter qualify before ownership breaks the tie.
                nameRank = 1
            } else if otherTokens.allSatisfy({ token in entry.nameTokens.contains { $0.hasPrefix(token) } }) {
                nameRank = 2
            } else if otherTokens.allSatisfy({ entry.terms.contains($0) }) {
                nameRank = 3
            } else if otherTokens.allSatisfy({ token in
                entry.terms.contains(token) || (token.count >= 4 && entry.nameTokens.contains {
                    $0.count >= 4 && Self.isOneEditAway(token, from: $0)
                })
            }) {
                nameRank = 4
            } else { continue }
            matches.append((entry, nameRank, offset))
        }
        let sorted = matches.sorted { left, right in
            if left.entry.isTeamUnit != right.entry.isTeamUnit { return !left.entry.isTeamUnit }
            if left.nameRank != right.nameRank { return left.nameRank < right.nameRank }
            let leftID = left.entry.player.id, rightID = right.entry.player.id
            let leftOwner = ranking.ownershipRank(leftID), rightOwner = ranking.ownershipRank(rightID)
            if leftOwner != rightOwner { return leftOwner < rightOwner }
            let leftValue = ranking.fantasyValues[leftID], rightValue = ranking.fantasyValues[rightID]
            if let leftValue, let rightValue, leftValue != rightValue { return leftValue > rightValue }
            if (leftValue != nil) != (rightValue != nil) { return leftValue != nil }
            return left.alphabeticRank < right.alphabeticRank
        }
        return PlayerSearchResults(players: sorted.prefix(max(0, limit)).map(\.entry.player), total: matches.count)
    }

    /// One insertion, deletion, substitution or adjacent transposition. Applied
    /// only to name tokens of at least four characters, never codes/positions.
    private static func isOneEditAway(_ query: String, from name: String) -> Bool {
        let a = Array(query), b = Array(name)
        guard abs(a.count - b.count) <= 1 else { return false }
        let common = zip(a, b).prefix { $0 == $1 }.count
        if common == min(a.count, b.count) { return true }
        if a.count == b.count {
            if a.dropFirst(common + 1).elementsEqual(b.dropFirst(common + 1)) { return true }
            return common + 1 < a.count && a[common] == b[common + 1] && a[common + 1] == b[common]
                && a.dropFirst(common + 2).elementsEqual(b.dropFirst(common + 2))
        }
        if a.count > b.count { return a.dropFirst(common + 1).elementsEqual(b.dropFirst(common)) }
        return a.dropFirst(common).elementsEqual(b.dropFirst(common + 1))
    }
}

/// An immutable snapshot for a deliberate query. Relevance affects ordering
/// only; it never implies ownership, eligibility or a permission to transact.
struct PlayerSearchRankingContext: Sendable {
    private let ownPlayerIDs: Set<String>
    private let rosteredPlayerIDs: Set<String>
    let fantasyValues: [String: Double]

    init(franchiseID: String? = nil, ownership: PlayerSearchOwnership? = nil,
         fantasyValues: [String: Double] = [:]) {
        ownPlayerIDs = Set(ownership?.assignments.compactMap { id, owners in
            guard let franchiseID, owners.contains(where: { $0.team.id == franchiseID }) else { return nil }
            return id
        } ?? [])
        rosteredPlayerIDs = Set(ownership?.assignments.compactMap { $0.value.isEmpty ? nil : $0.key } ?? [])
        self.fantasyValues = fantasyValues.filter { $0.value.isFinite }
    }

    func ownershipRank(_ playerID: String) -> Int {
        ownPlayerIDs.contains(playerID) ? 0 : rosteredPlayerIDs.contains(playerID) ? 1 : 2
    }

    /// Uses the current week's already-loaded projections, falling back to
    /// observed fantasy points. Unknown values stay unknown, not zero.
    static func cachedFantasyValues(week: Int, scores: ScoresSnapshot, lineup: LineupSnapshot,
                                    waivers: WaiverSnapshot) -> [String: Double] {
        var values: [String: Double] = [:]
        var points: [String: Double] = [:]
        if scores.week == week, scores.lastUpdated != .distantPast {
            let groups = Dictionary(grouping: scores.matchups.flatMap { $0.away.players + $0.home.players }, by: \.id)
            for (id, players) in groups {
                let projections = Set(players.compactMap(\.projectedPoints).filter(\.isFinite))
                let actuals = Set(players.compactMap(\.livePoints).filter(\.isFinite))
                if projections.count == 1 { values[id] = projections.first }
                if actuals.count == 1 { points[id] = actuals.first }
            }
        }
        if lineup.week == week {
            for player in lineup.players where values[player.id] == nil {
                if let value = player.projectedPoints, value.isFinite { values[player.id] = value }
            }
        }
        if waivers.projectionWeek == week {
            for player in waivers.candidates where values[player.id] == nil {
                if let value = player.projectedPoints, value.isFinite { values[player.id] = value }
            }
        }
        return values.merging(points) { projection, _ in projection }
    }
}

struct PlayerSearchResults: Equatable, Sendable {
    var players: [PlayerIdentity]
    var total: Int
}

struct PlayerSearchCatalog: Sendable {
    let scope: String
    let index: PlayerSearchIndex
}

/// Display-only membership. Never used to authorize an add, drop, or trade.
struct PlayerSearchOwnership: Sendable {
    let scope: String
    var assignments: [String: [PlayerOwnershipAssignment]]
    var freeAgentIDs: Set<String>
    var checkedAt = Date()

    func summary(for playerID: String, scores: ScoresSnapshot?, currentWeek: Int,
                 now: Date = Date()) -> String {
        let owners = assignments[playerID] ?? []
        guard !owners.isEmpty else {
            return freeAgentIDs.contains(playerID) ? "Free agent" : "Not on a roster"
        }
        return owners.map { owner in
            var status = owner.status
            // Use only a recent, current-week scoring assignment, and only after
            // current roster membership has established the same owner.
            if status == .rostered, let scores, scores.week == currentWeek,
               (0..<150).contains(now.timeIntervalSince(scores.lastUpdated)) {
                let matching = scores.matchups.flatMap { [$0.away, $0.home] }
                    .filter { $0.id == owner.team.id }.flatMap(\.players).filter { $0.id == playerID }
                if !matching.isEmpty, matching.allSatisfy({ $0.lineupStatus == .starter }) { status = .starter }
                else if !matching.isEmpty, matching.allSatisfy({ $0.lineupStatus == .bench }) { status = .nonstarter }
            }
            return [owner.team.name, owner.team.ownerName, status.label]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }.joined(separator: "\n")
    }
}

enum PlayerSearchMapper {
    static func ownership(scope: String, league: MFLLeague, rosters: MFLRosterCollection,
                          freeAgents: MFLFreeAgentPool?) throws -> PlayerSearchOwnership {
        let teams = try TeamPlayerMapper.teams(in: league)
        let teamIDs = Set(teams.map(\.id))
        guard !teamIDs.isEmpty, Set(rosters.rosters.map(\.id)) == teamIDs,
              rosters.rosters.count == teamIDs.count else {
            throw RepositoryError.server("MFL hasn’t returned every team’s roster. Try refreshing ownership.")
        }
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        var assignments: [String: [PlayerOwnershipAssignment]] = [:]
        for roster in rosters.rosters {
            guard let team = teamsByID[roster.id], Set(roster.players.map(\.id)).count == roster.players.count else {
                throw RepositoryError.server("MFL returned an inconsistent roster. Try refreshing ownership.")
            }
            for player in roster.players {
                let membership = RosterMembership(rawValue: player.status.rawValue)
                let status: PlayerLineupAssignment = switch membership {
                case .injuredReserve: .injuredReserve
                case .taxiSquad: .taxiSquad
                case .active: .rostered
                case .unknown(let value): .unknown(value)
                }
                assignments[player.id, default: []].append(.init(team: team, status: status))
            }
        }
        for id in assignments.keys { assignments[id]?.sort { $0.team.name < $1.team.name } }
        // Do not flatten conference/division pools into a claim that a player is
        // available to this franchise. Such leagues still get full ownership.
        let isSinglePool = league.playerLimitUnit == "LEAGUE" && league.rostersPerPlayer == 1
            && (freeAgents?.leagueUnits.count ?? 0) <= 1
        let freeIDs = isSinglePool ? Set(freeAgents?.players.map(\.id) ?? []) : []
        return PlayerSearchOwnership(scope: scope, assignments: assignments,
            freeAgentIDs: freeIDs.subtracting(assignments.keys))
    }
}
