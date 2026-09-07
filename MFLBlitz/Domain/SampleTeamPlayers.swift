import Foundation

extension DemoLeagueRepository {
    func loadTeams(refresh: Bool) async throws -> [TeamSummary] {
        try Task.checkCancellation()
        return SampleTeamPlayers.teams
    }

    func loadTeamRoster(franchiseID: String, lineupWeek: Int?, refresh: Bool) async throws -> TeamRosterSnapshot {
        try Task.checkCancellation()
        guard let team = SampleTeamPlayers.teams.first(where: { $0.id == franchiseID }) else {
            throw RepositoryError.server("That preview team is unavailable.")
        }
        var players = previewRoster(franchiseID: franchiseID, week: lineupWeek)
        if franchiseID == SampleData.workspace.franchiseID, lineupWeek == nil {
            // Explicitly synthetic YTD values; never substitute projections.
            for index in players.indices {
                players[index].seasonPoints = index.isMultiple(of: 5) ? nil : Double((index * 17) % 83)
            }
        }
        return TeamRosterSnapshot(scope: SampleData.workspace.storageScope, team: team,
            players: players,
            lineupWeek: lineupWeek, rosterVerifiedAt: refresh ? Date() : nil)
    }

    func loadPlayerDetail(playerID: String, refresh: Bool) async throws -> PlayerDetailSnapshot {
        try Task.checkCancellation()
        #if DEBUG
        // Offline-only native regression: prove the tapped row's identity is
        // visible while ownership is still pending, with no enabled actions.
        if ProcessInfo.processInfo.arguments.contains("--synthetic-slow-player") {
            try await Task.sleep(for: .seconds(20))
        }
        #endif
        let rosters = SampleTeamPlayers.teams.map { team in
            (team, previewRoster(franchiseID: team.id, week: SampleData.workspace.week))
        }
        var assignments = rosters.compactMap { team, players -> PlayerOwnershipAssignment? in
            guard let player = players.first(where: { $0.id == playerID }) else { return nil }
            let status: PlayerLineupAssignment = switch player.membership {
            case .injuredReserve: .injuredReserve
            case .taxiSquad: .taxiSquad
            default: player.lineupAssignment ?? .rostered
            }
            return PlayerOwnershipAssignment(team: team, status: status)
        }
        var identity = rosters.lazy.flatMap { $0.1 }.first { $0.id == playerID }?.identity
            ?? SampleData.waivers.candidates.first(where: { $0.id == playerID }).map {
                PlayerIdentity(id: $0.id, name: $0.name, position: $0.position, nflTeam: $0.nflTeam)
            }
        // Preview scoring rows have synthetic IDs, including the user's team.
        // Resolve those exact IDs without replacing canonical lineup or trade IDs.
        if identity == nil {
            for scoringTeam in SampleData.scores.matchups.flatMap({ [$0.away, $0.home] }) {
                guard let player = scoringTeam.players.first(where: { $0.id == playerID }),
                      !assignments.contains(where: { $0.team.id == scoringTeam.id }) else { continue }
                identity = identity ?? PlayerIdentity(id: player.id, name: player.name,
                    position: player.position, nflTeam: player.nflTeam)
                let team = SampleTeamPlayers.teams.first { $0.id == scoringTeam.id }
                    ?? TeamSummary(id: scoringTeam.id, name: scoringTeam.name,
                        abbreviation: scoringTeam.abbreviation, artworkURLs: scoringTeam.artworkURLs,
                        accentSeed: scoringTeam.accentSeed)
                let status: PlayerLineupAssignment = switch player.lineupStatus {
                case .starter: .starter
                case .bench: .nonstarter
                case .unknown: .rostered
                }
                assignments.append(PlayerOwnershipAssignment(team: team, status: status))
            }
        }
        guard let identity else { throw RepositoryError.server("That preview player is unavailable.") }
        // A deterministic locked free agent exercises the same browse gate as
        // MFL without borrowing a real player's private acquisition status.
        let locked = assignments.isEmpty && playerID == "w2"
        return PlayerDetailSnapshot(scope: SampleData.workspace.storageScope, identity: identity,
            ownership: PlayerOwnership(assignments: assignments, availabilityFranchiseID: SampleData.workspace.franchiseID,
                isFreeAgent: assignments.isEmpty, cannotAdd: nil, acquisitionLocked: locked,
                canAddImmediately: assignments.isEmpty && !locked),
            ownershipVerifiedAt: refresh ? Date() : nil)
    }

    func loadPlayerBiography(playerID: String) async throws -> PlayerBio? {
        _ = try await loadPlayerDetail(playerID: playerID, refresh: false)
        return playerID == "12620" ? PlayerBio(jerseyNumber: "4", height: "6′ 2″", weight: "238 lb") : nil
    }
}

enum SampleTeamPlayers {
    static var teams: [TeamSummary] {
        SampleData.standings.map {
            TeamSummary(id: $0.id, name: $0.name, abbreviation: $0.abbreviation,
                ownerName: $0.ownerName, artworkURLs: $0.artworkURLs, accentSeed: $0.accentSeed)
        }
    }

    static func roster(franchiseID: String, lineupWeek: Int?) -> [RosterPlayerSummary] {
        if franchiseID == SampleData.workspace.franchiseID {
            return SampleData.lineup.players.map {
                RosterPlayerSummary(identity: PlayerIdentity(id: $0.id, name: $0.name,
                    position: $0.position, nflTeam: $0.nflTeam),
                    membership: $0.injuryStatus == .injuredReserve ? .injuredReserve : .active,
                    lineupAssignment: lineupWeek == nil ? nil : ($0.isStarter ? .starter : .nonstarter))
            }
        }
        let scoringTeam = SampleData.scores.matchups.flatMap { [$0.away, $0.home] }.first { $0.id == franchiseID }
        var result = (scoringTeam?.players ?? []).map { player in
            let assignment: PlayerLineupAssignment = switch player.lineupStatus {
            case .starter: .starter
            case .bench: .nonstarter
            case .unknown: .rostered
            }
            return RosterPlayerSummary(identity: PlayerIdentity(id: player.id, name: player.name,
                position: player.position, nflTeam: player.nflTeam), membership: .active,
                lineupAssignment: lineupWeek == nil ? nil : assignment)
        }
        // Include canonical preview trade-asset IDs without parsing player names
        // or assuming a fantasy pick/FAAB token is a player.
        for asset in SampleData.trades.teams.first(where: { $0.id == franchiseID })?.assets ?? []
            where asset.kind == .player && !result.contains(where: { $0.id == asset.id }) {
            result.append(RosterPlayerSummary(identity: PlayerIdentity(id: asset.id, name: asset.name), membership: .active))
        }
        return result
    }
}
