import Foundation
import MFLCore

extension LiveMFLRepository {
    func loadTeams(refresh: Bool) async throws -> [TeamSummary] {
        let (client, _, workspace) = try requireSession()
        let league = try await client.league(refreshPolicy: refresh ? .reloadIgnoringCache : .useCache)
        try validateTeamPlayerSession(client: client, scope: workspace.storageScope)
        return try TeamPlayerMapper.teams(in: league)
    }

    func loadTeamRoster(franchiseID: String, lineupWeek: Int?, refresh: Bool) async throws -> TeamRosterSnapshot {
        let (client, _, workspace) = try requireSession()
        let policy: MFLRefreshPolicy = refresh ? .reloadIgnoringCache : .useCache
        let (league, rosters, catalog) = try await Self.teamRosterSources(
            client: client, franchiseID: franchiseID, policy: policy)
        try validateTeamPlayerSession(client: client, scope: workspace.storageScope)
        let teams = try TeamPlayerMapper.teams(in: league)
        guard let team = teams.first(where: { $0.id == franchiseID }) else {
            throw RepositoryError.server("That team is no longer in this league.")
        }
        let matches = rosters.rosters.filter { $0.franchiseID == franchiseID }
        guard matches.count == 1, let roster = matches.first,
              Set(roster.players.map(\.id)).count == roster.players.count else {
            throw RepositoryError.server("MFL did not return a complete, unique roster for this team.")
        }
        let verifiedAt = refresh ? Date() : nil
        var issues: [DetailReadIssue] = []
        let catalogByID = catalog?.playersByID ?? [:]
        if roster.players.contains(where: { catalogByID[$0.id] == nil }) { issues.append(.playerNames) }

        var assignments: [String: PlayerLineupAssignment] = [:]
        if let lineupWeek, !roster.players.isEmpty {
            let statuses = try await TeamPlayerMapper.optionalRead {
                try await client.playerRosterStatus(playerIDs: roster.players.map(\.id), week: lineupWeek,
                    franchiseID: franchiseID, refreshPolicy: policy)
            }
            if let statuses {
                assignments = TeamPlayerMapper.lineupAssignments(statuses, franchiseID: franchiseID)
            }
            if roster.players.contains(where: { assignments[$0.id] == nil }) { issues.append(.lineupAssignments) }
        }
        var seasonPoints: [String: Double] = [:]
        if franchiseID == workspace.franchiseID, lineupWeek == nil, !roster.players.isEmpty {
            // My Team shows positions/YTD, not submitted lineup assignments.
            // One batched read replaces its former playerRosterStatus request.
            let totals = try await TeamPlayerMapper.optionalRead {
                try await client.playerScores(playerIDs: roster.players.map(\.id),
                    period: .yearToDate, refreshPolicy: policy)
            }
            if let totals {
                seasonPoints = totals.scoresByPlayerID.compactMapValues {
                    let points = NSDecimalNumber(decimal: $0).doubleValue
                    return points.isFinite ? points : nil
                }
            } else { issues.append(.seasonPoints) }
        }
        try validateTeamPlayerSession(client: client, scope: workspace.storageScope)
        return TeamRosterSnapshot(scope: workspace.storageScope, team: team, players: roster.players.map { player in
            RosterPlayerSummary(identity: TeamPlayerMapper.identity(catalogByID[player.id], id: player.id),
                membership: RosterMembership(rawValue: player.status.rawValue),
                lineupAssignment: assignments[player.id], salary: player.salary,
                contractYear: player.contractYear, contractStatus: TeamPlayerMapper.text(player.contractStatus),
                seasonPoints: seasonPoints[player.id])
        }, lineupWeek: lineupWeek, issues: issues, rosterVerifiedAt: verifiedAt)
    }

    private enum RosterSource: Sendable {
        case league(MFLLeague)
        case rosters(MFLRosterCollection)
        case catalog(MFLPlayerCatalog?)
    }

    /// Finish child-task lifetimes before mapping or awaiting assignment reads.
    /// Avoids Swift 6.1 async-let teardown corruption (swiftlang/swift#81771)
    /// while retaining parallel requests and the same cache/cancellation policy.
    private static func teamRosterSources(client: MFLClient, franchiseID: String,
                                         policy: MFLRefreshPolicy) async throws
        -> (MFLLeague, MFLRosterCollection, MFLPlayerCatalog?) {
        try await withThrowingTaskGroup(of: RosterSource.self) { group in
            // Refresh membership, not daily metadata; do not pass a week to rosters.
            group.addTask { .league(try await client.league(refreshPolicy: .useCache)) }
            group.addTask { .rosters(try await client.rosters(franchiseID: franchiseID, refreshPolicy: policy)) }
            group.addTask { .catalog(try await TeamPlayerMapper.optionalRead { try await client.players() }) }
            var league: MFLLeague?
            var rosters: MFLRosterCollection?
            var catalog: MFLPlayerCatalog?
            for try await source in group {
                switch source {
                case .league(let value): league = value
                case .rosters(let value): rosters = value
                case .catalog(let value): catalog = value
                }
            }
            guard let league, let rosters else { throw CancellationError() }
            return (league, rosters, catalog)
        }
    }

    func loadPlayerDetail(playerID: String, refresh: Bool) async throws -> PlayerDetailSnapshot {
        let (client, _, workspace) = try requireSession()
        let policy: MFLRefreshPolicy = refresh ? .reloadIgnoringCache : .useCache
        // Ownership refreshes reuse league identity; loadTeams(refresh:) can explicitly refresh it.
        async let leagueRead = client.league(refreshPolicy: .useCache)
        async let catalogRead = TeamPlayerMapper.optionalRead { try await client.players() }
        async let ownershipRead = TeamPlayerMapper.optionalRead {
            try await client.playerRosterStatus(playerIDs: [playerID], franchiseID: workspace.franchiseID,
                refreshPolicy: policy)
        }
        let (league, catalog, statuses) = try await (leagueRead, catalogRead, ownershipRead)
        try validateTeamPlayerSession(client: client, scope: workspace.storageScope)
        let teams = try TeamPlayerMapper.teams(in: league)
        let basic = catalog?.playersByID[playerID]
        // Biography is secondary and loads only when disclosed. A targeted
        // detailed read is needed here only if the directory cannot name this
        // player; ordinary identity/ownership must never wait for optional bio.
        var detailed: MFLPlayer?
        if TeamPlayerMapper.text(basic?.name) == nil {
            let fallback = try await TeamPlayerMapper.optionalRead {
                try await client.players(ids: [playerID], details: true)
            }
            try validateTeamPlayerSession(client: client, scope: workspace.storageScope)
            detailed = fallback?.playersByID[playerID]
        }
        var issues: [DetailReadIssue] = []
        if basic == nil && detailed == nil { issues.append(.playerNames) }
        let ownership = statuses.flatMap {
            TeamPlayerMapper.ownership($0, playerID: playerID, teams: teams,
                availabilityFranchiseID: workspace.franchiseID)
        }
        if ownership == nil { issues.append(.ownership) }
        var identity = TeamPlayerMapper.identity(detailed ?? basic, id: playerID)
        // Detailed responses sometimes omit fields present in the basic directory.
        if let basic {
            let fallback = TeamPlayerMapper.identity(basic, id: playerID)
            if detailed.flatMap({ TeamPlayerMapper.text($0.name) }) == nil || identity.name == "Player \(playerID)" {
                identity.name = fallback.name
            }
            identity.position = identity.position ?? fallback.position
            identity.nflTeam = identity.nflTeam ?? fallback.nflTeam
        }
        return PlayerDetailSnapshot(scope: workspace.storageScope, identity: identity,
            bio: detailed.map(TeamPlayerMapper.biography), ownership: ownership, issues: issues,
            ownershipVerifiedAt: refresh && ownership != nil ? Date() : nil)
    }

    func loadPlayerBiography(playerID: String) async throws -> PlayerBio? {
        let (client, _, workspace) = try requireSession()
        // Separate targeted daily cache. Failures stay local to the disclosure
        // and cannot hide or authorize current ownership/action controls.
        let details = try await client.players(ids: [playerID], details: true)
        try validateTeamPlayerSession(client: client, scope: workspace.storageScope)
        return details.playersByID[playerID].map(TeamPlayerMapper.biography)
    }

    private func validateTeamPlayerSession(client: MFLClient, scope: String) throws {
        try Task.checkCancellation()
        let active = try requireSession()
        guard active.0 === client, active.2.storageScope == scope else { throw CancellationError() }
    }
}

/// Pure normalization, shared by repository reads and synthetic fixture tests.
enum TeamPlayerMapper {
    static func text(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func teams(in league: MFLLeague) throws -> [TeamSummary] {
        guard Set(league.franchises.map(\.id)).count == league.franchises.count else {
            throw RepositoryError.server("MFL returned duplicate team identifiers.")
        }
        return league.franchises.map { franchise in
            TeamSummary(id: franchise.id, name: text(franchise.name) ?? "Team \(franchise.id)",
                abbreviation: text(franchise.abbreviation) ?? String(franchise.id.suffix(3)),
                ownerName: text(franchise.ownerName),
                artworkURLs: TeamArtworkURLPolicy.candidates(icon: franchise.iconURL, logo: franchise.logoURL),
                accentSeed: max(0, Int(franchise.id) ?? 0))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func identity(_ player: MFLPlayer?, id: String) -> PlayerIdentity {
        PlayerIdentity(id: id, name: text(player?.displayName) ?? "Player \(id)",
            position: text(player?.position), nflTeam: text(player?.nflTeam))
    }

    static func biography(_ player: MFLPlayer) -> PlayerBio {
        PlayerBio(jerseyNumber: text(player.jerseyNumber), birthDate: PlayerBio.parseBirthDate(player.birthDate),
            height: text(player.height), weight: text(player.weight),
            draftYear: player.draftYear.flatMap { $0 > 0 ? $0 : nil },
            draftRound: player.draftRound.flatMap { $0 > 0 ? $0 : nil })
    }

    static func lineupAssignments(_ response: MFLPlayerRosterStatusCollection,
                                  franchiseID: String) -> [String: PlayerLineupAssignment] {
        let byPlayer = Dictionary(grouping: response.statuses, by: \.id)
        return byPlayer.reduce(into: [:]) { result, entry in
            guard entry.value.count == 1, let status = entry.value.first else { return }
            let assignments = status.rosterFranchises.filter { $0.franchiseID == franchiseID }
            guard assignments.count == 1, let assignment = assignments.first else { return }
            result[entry.key] = PlayerLineupAssignment(rawValue: assignment.status.rawValue)
        }
    }

    static func ownership(_ response: MFLPlayerRosterStatusCollection, playerID: String,
                          teams: [TeamSummary], availabilityFranchiseID: String) -> PlayerOwnership? {
        let matches = response.statuses.filter { $0.id == playerID }
        guard matches.count == 1, let status = matches.first,
              Set(status.rosterFranchises.map(\.franchiseID)).count == status.rosterFranchises.count else { return nil }
        let assignments = status.rosterFranchises.map { assignment in
            let team = teams.first { $0.id == assignment.franchiseID }
                ?? TeamSummary(id: assignment.franchiseID, name: "Team \(assignment.franchiseID)",
                    abbreviation: String(assignment.franchiseID.suffix(3)))
            return PlayerOwnershipAssignment(team: team, status: .init(rawValue: assignment.status.rawValue))
        }
        return PlayerOwnership(assignments: assignments, availabilityFranchiseID: availabilityFranchiseID,
            isFreeAgent: status.isFreeAgent, cannotAdd: status.cannotAdd, acquisitionLocked: status.isLocked,
            canAddImmediately: status.canAddImmediately)
    }

    static func optionalRead<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async throws -> Value? {
        do {
            try Task.checkCancellation()
            let value = try await operation()
            try Task.checkCancellation()
            return value
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            if let urlError = error as? URLError, urlError.code == .cancelled { throw error }
            if case RepositoryError.missingSession = error { throw error }
            if let mflError = error as? MFLCoreError {
                switch mflError {
                case .unauthorized, .authenticationFailed: throw error
                default: break
                }
            }
            return nil
        }
    }
}
