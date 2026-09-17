import Foundation
import MFLCore

extension LiveMFLRepository {
    func loadPlayerSearchCatalog() async throws -> PlayerSearchCatalog {
        let (client, league, workspace) = try requireSession()
        // Reuse the decoded, disk-backed daily catalog used by lineup/scoring.
        let catalog = try await client.players()
        try validatePlayerToolsSession(client, workspace.storageScope)
        return PlayerSearchCatalog(scope: workspace.storageScope,
            index: PlayerSearchIndex(players: catalog.players.map { TeamPlayerMapper.identity($0, id: $0.id) },
                eligiblePositions: PlayerSearchPositions.eligible(in: league)))
    }

    func loadPlayerSearchOwnership(refresh: Bool) async throws -> PlayerSearchOwnership {
        let (client, _, workspace) = try requireSession()
        let policy: MFLRefreshPolicy = refresh ? .reloadIgnoringCache : .useCache
        // One complete current-roster read, not one request per result. No W:
        // historical lineup snapshots do not establish current ownership.
        let league = try await client.league()
        let rosters = try await client.rosters(refreshPolicy: policy)
        let freeAgents = try await TeamPlayerMapper.optionalRead {
            try await client.freeAgents(refreshPolicy: policy)
        }
        try validatePlayerToolsSession(client, workspace.storageScope)
        return try PlayerSearchMapper.ownership(scope: workspace.storageScope, league: league,
            rosters: rosters, freeAgents: freeAgents)
    }
}

extension DemoLeagueRepository {
    func loadPlayerSearchCatalog() async throws -> PlayerSearchCatalog {
        var players = SampleTeamPlayers.teams.flatMap {
            previewRoster(franchiseID: $0.id, week: SampleData.workspace.week).map(\.identity)
        }
        players += SampleData.waivers.candidates.map {
            PlayerIdentity(id: $0.id, name: $0.name, position: $0.position, nflTeam: $0.nflTeam)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--synthetic-search-names") {
            players += [
                .init(id: "15972", name: "Jordan Mason", position: "RB", nflTeam: "MIN"),
                .init(id: "13595", name: "Mason Rudolph", position: "QB", nflTeam: "PIT"),
                .init(id: "15535", name: "Mason Kinsey", position: "WR", nflTeam: "FA"),
                .init(id: "16838", name: "Mason Pline", position: "TE", nflTeam: "FA"),
                .init(id: "16858", name: "Mason Tipton", position: "WR", nflTeam: "NOS"),
                .init(id: "17106", name: "Mason Taylor", position: "TE", nflTeam: "NYJ"),
                .init(id: "search-henry", name: "Hunter Henry", position: "TE", nflTeam: "NEP"),
                .init(id: "search-travis", name: "Travis Hunter", position: "WR", nflTeam: "JAC")]
        }
        if ProcessInfo.processInfo.arguments.contains("--synthetic-search-teams") {
            // Reproduce the source shape in the owner's screenshot, without
            // using a real account or giving the individual's name a team hint.
            players = [
                .init(id: "search-ne-wr", name: "Riley Receiver", position: "WR", nflTeam: "NEP"),
                .init(id: "search-ne-qb", name: "Quinn Quarterback", position: "QB", nflTeam: "NEP"),
                .init(id: "search-sea-wr", name: "Sam Receiver", position: "WR", nflTeam: "SEA"),
                .init(id: "search-ne-team-wr", name: "New England Patriots", position: "TMWR", nflTeam: "NEP"),
                .init(id: "search-ne-team-rb", name: "New England Patriots", position: "TMRB", nflTeam: "NEP"),
                .init(id: "search-ne-def", name: "New England Patriots", position: "DEF", nflTeam: "NEP")]
        }
        #endif
        return PlayerSearchCatalog(scope: SampleData.workspace.storageScope,
            index: PlayerSearchIndex(players: players, eligiblePositions: ["QB", "RB", "WR", "TE"]))
    }

    func loadPlayerSearchOwnership(refresh: Bool) async throws -> PlayerSearchOwnership {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--synthetic-slow-search-ownership") {
            try await Task.sleep(for: .seconds(20))
        }
        if ProcessInfo.processInfo.arguments.contains("--synthetic-search-ownership-offline") {
            throw RepositoryError.server("Synthetic ownership connection unavailable.")
        }
        #endif
        var assignments: [String: [PlayerOwnershipAssignment]] = [:]
        for team in SampleTeamPlayers.teams {
            for player in previewRoster(franchiseID: team.id, week: SampleData.workspace.week) {
                let status: PlayerLineupAssignment = switch player.membership {
                case .injuredReserve: .injuredReserve
                case .taxiSquad: .taxiSquad
                default: player.lineupAssignment ?? .rostered
                }
                assignments[player.id, default: []].append(.init(team: team, status: status))
            }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--synthetic-search-names"),
           let team = SampleTeamPlayers.teams.first(where: { $0.id == SampleData.workspace.franchiseID }) {
            assignments["15972"] = [.init(team: team, status: .rostered)]
            assignments["search-travis"] = [.init(team: team, status: .rostered)]
        }
        #endif
        return PlayerSearchOwnership(scope: SampleData.workspace.storageScope, assignments: assignments,
            freeAgentIDs: Set(SampleData.waivers.candidates.map(\.id)).subtracting(assignments.keys))
    }
}
