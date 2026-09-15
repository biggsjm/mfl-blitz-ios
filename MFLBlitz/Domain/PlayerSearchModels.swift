import Foundation
import MFLCore

/// A daily, local index. No query text is sent to MFL.
struct PlayerSearchIndex: Sendable {
    private struct Entry: Sendable {
        let player: PlayerIdentity
        let name: String
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
            Entry(player: player, name: Self.normalize(player.name),
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

    func search(_ query: String, limit: Int = 60) -> PlayerSearchResults {
        let normalized = Self.normalize(query)
        let exactPosition = PlayerSearchPositions.canonical(query)
        let tokens = PlayerSearchPositions.known.contains(exactPosition)
            ? [exactPosition.lowercased()] : normalized.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return PlayerSearchResults(players: [], total: 0) }
        var matches: [(Entry, Int)] = []
        // A recognized NFL code/position is a field match, not a substring of
        // someone's name (NE must not include every player named Jones).
        let teamCodes = tokens.compactMap(PlayerSearchTeams.canonicalCode)
        let positionTokens = tokens.filter { PlayerSearchPositions.known.contains(PlayerSearchPositions.canonical($0)) }
        let otherTokens = tokens.filter {
            PlayerSearchTeams.canonicalCode($0) == nil && !positionTokens.contains($0)
        }
        for entry in entries where teamCodes.allSatisfy({ entry.teamCode == $0 })
            && positionTokens.allSatisfy({ PlayerSearchPositions.expanded($0).contains(entry.position ?? "") })
            && otherTokens.allSatisfy({ entry.terms.contains($0) }) {
            let rank = (entry.name == normalized ? 0 : entry.name.hasPrefix(normalized) ? 1 : 2)
                + (entry.isTeamUnit ? 3 : 0)
            matches.append((entry, rank))
        }
        // Preserve the index's name order within each relevance tier.
        let sorted = (0...5).flatMap { rank in matches.filter { $0.1 == rank }.map { $0.0.player } }
        return PlayerSearchResults(players: Array(sorted.prefix(max(0, limit))), total: matches.count)
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
