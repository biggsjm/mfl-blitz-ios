import Foundation
import MFLCore

actor LiveMFLRepository: LeagueRepository {
    private var client: MFLClient?
    private var league: MFLLeague?
    private var workspace: LeagueWorkspace?
    private let privateStore: any PrivateStore
    private let transport: any MFLHTTPTransport
    private let requestInterval: Duration
    private let restoreTimeout: Duration
    private var seasonStatus: MFLSeasonStatus?
    private var statusUpdatedAt: Date = .distantPast

    init(privateStore: any PrivateStore = KeychainPrivateStore(),
         transport: any MFLHTTPTransport = MFLURLSessionTransport(), requestInterval: Duration = .seconds(1),
         restoreTimeout: Duration = .seconds(15)) {
        self.privateStore = privateStore
        self.transport = transport
        self.requestInterval = requestInterval
        self.restoreTimeout = restoreTimeout
    }

    func signIn(with credentials: LoginCredentials) async throws -> LeagueWorkspace {
        let reference = try MFLLeagueReference(season: credentials.season, leagueID: credentials.leagueID)
        let configuration = MFLClientConfiguration(
            league: reference,
            userAgent: "MFL Blitz/0.1 (com.biggsjm.MFLBlitz)",
            minimumRequestInterval: requestInterval
        )
        let newClient = MFLClient(configuration: configuration, transport: transport)
        _ = try await newClient.authenticate(username: credentials.username, password: credentials.password)
        return try await finishSignIn(client: newClient, credentials: credentials)
    }

    func restoreSession() async throws -> LeagueWorkspace? {
        guard let saved = try privateStore.decode(SavedSession.self, key: "session") else { return nil }
        let reference = try MFLLeagueReference(season: saved.season, leagueID: saved.leagueID)
        let newClient = MFLClient(configuration: MFLClientConfiguration(
            league: reference, userAgent: "MFL Blitz/0.1 (com.biggsjm.MFLBlitz)", minimumRequestInterval: requestInterval),
            transport: transport, authenticationCookie: try MFLAuthenticationCookie(value: saved.cookie))
        do {
            return try await withThrowingTaskGroup(of: LeagueWorkspace.self) { group in
                group.addTask {
                    try await self.finishSignIn(client: newClient,
                        credentials: LoginCredentials(leagueID: saved.leagueID, season: saved.season),
                        expectedFranchise: saved.franchiseID)
                }
                group.addTask { [restoreTimeout] in
                    try await Task.sleep(for: restoreTimeout)
                    throw RepositoryError.server("MFL took too long to reconnect. Your saved session and drafts are kept; try signing in again.")
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw CancellationError() }
                return result
            }
        } catch let error as MFLCoreError {
            if case .unauthorized = error { try privateStore.remove("session") }
            throw error
        }
    }

    private func finishSignIn(client newClient: MFLClient, credentials: LoginCredentials,
                              expectedFranchise: String? = nil) async throws -> LeagueWorkspace {
        let memberships = try await newClient.myLeagues(
            includeFranchiseNames: false,
            refreshPolicy: .reloadIgnoringCache
        )
        guard !memberships.leagues.isEmpty else {
            throw RepositoryError.server(
                "MFL returned no leagues for \(credentials.season). Check the season or sign in again."
            )
        }
        guard let membership = memberships.leagues.first(where: { $0.leagueID == credentials.leagueID }) else {
            throw RepositoryError.server(
                "MFL accepted the login, but league \(credentials.leagueID) is not associated with this account for \(credentials.season)."
            )
        }
        guard membership.franchiseID != "0000" else {
            throw RepositoryError.server(
                "This MFL account is the commissioner but is not assigned to a franchise in league \(credentials.leagueID)."
            )
        }
        if let expectedFranchise, expectedFranchise != membership.franchiseID {
            throw RepositoryError.server("Your franchise assignment changed. Sign in again to confirm your team; saved drafts have not been applied.")
        }
        guard let host = membership.serverHost else {
            throw RepositoryError.server("MFL returned an invalid host for league \(credentials.leagueID).")
        }
        await newClient.setLeagueHost(host)
        let loadedLeague = try await newClient.league(refreshPolicy: .reloadIgnoringCache)
        guard let franchise = loadedLeague.franchises.first(where: { $0.id == membership.franchiseID }) else {
            throw RepositoryError.server(
                "MFL mapped this account to franchise \(membership.franchiseID), but that franchise was not present in league \(credentials.leagueID)."
            )
        }

        guard let baseURL = URL(string: "https://\(host.name)") else {
            throw RepositoryError.server("MFL returned an invalid league host.")
        }

        let status = try? await newClient.seasonStatus()
        let newWorkspace = LeagueWorkspace(
            leagueID: credentials.leagueID,
            season: credentials.season,
            leagueName: loadedLeague.name,
            franchiseID: franchise.id,
            franchiseName: cleanText(franchise.name),
            baseURL: baseURL,
            week: status?.currentWeek ?? loadedLeague.startWeek ?? 1,
            lineupWeek: status?.lineupWeek,
            weekIsConfirmed: status != nil
        )

        guard let cookie = await newClient.authenticationCookie() else { throw RepositoryError.missingSession }
        try Task.checkCancellation()
        try privateStore.encode(SavedSession(cookie: cookie.value, season: credentials.season,
            leagueID: credentials.leagueID, franchiseID: franchise.id), key: "session")
        client = newClient
        league = loadedLeague
        workspace = newWorkspace
        seasonStatus = status
        statusUpdatedAt = status == nil ? .distantPast : Date()
        return newWorkspace
    }

    func currentWeek() async throws -> Int {
        let (client, _, _) = try requireSession()
        // A membership check lets the foreground refresh detect expired cookies
        // even if the league's public scores are still accessible.
        let memberships = try await client.myLeagues(refreshPolicy: .reloadIgnoringCache)
        guard let workspace, memberships.leagues.contains(where: {
            $0.leagueID == workspace.leagueID && $0.franchiseID == workspace.franchiseID
        }) else { throw RepositoryError.missingSession }
        let status = try await client.seasonStatus()
        seasonStatus = status
        statusUpdatedAt = Date()
        self.workspace = LeagueWorkspace(leagueID: workspace.leagueID, season: workspace.season,
            leagueName: workspace.leagueName, franchiseID: workspace.franchiseID,
            franchiseName: workspace.franchiseName, baseURL: workspace.baseURL,
            week: status.currentWeek, lineupWeek: status.lineupWeek)
        return status.currentWeek
    }

    func loadWorkspace() async throws -> LeagueWorkspace {
        try requireWorkspace()
    }

    func loadScores(week: Int) async throws -> ScoresSnapshot {
        try await makeScoresSnapshot(week: week, refreshPolicy: .useCache)
    }

    func refreshScores(week: Int) async throws -> ScoresSnapshot {
        try await makeScoresSnapshot(week: week, refreshPolicy: .reloadIgnoringCache)
    }

    private func makeScoresSnapshot(
        week: Int,
        refreshPolicy: MFLRefreshPolicy
    ) async throws -> ScoresSnapshot {
        let (client, _, workspace) = try requireSession()
        if Date().timeIntervalSince(statusUpdatedAt) >= 90,
           let status = try? await client.seasonStatus() {
            seasonStatus = status
            statusUpdatedAt = Date()
        }
        let isCompleted = week <= (seasonStatus?.completedWeek ?? 0)
        async let liveTask: MFLLiveScoring? = isCompleted
            ? client.weeklyResults(week: week)
            : liveScoringIfAvailable(from: client, week: week, includeBench: true, refreshPolicy: refreshPolicy)
        async let leagueTask = client.league()
        let (live, refreshedLeague) = try await (liveTask, leagueTask)
        self.league = refreshedLeague

        guard let live else {
            return ScoresSnapshot(
                week: week,
                matchups: [],
                lastUpdated: Date(),
                isLive: false,
                scorePrecision: scorePrecision(for: refreshedLeague)
            )
        }
        guard live.week == nil || live.week == week else {
            throw RepositoryError.server("MFL returned a different scoring week. Your existing scores were kept.")
        }
        let projections = (try? await client.projectedScores(week: week))?.scoresByPlayerID ?? [:]

        let livePlayerIDs = Set(
            live.matchups
                .flatMap(\.franchises)
                .flatMap(\.players)
                .map(\.id)
        )
        // Aggregate live scoring remains useful even if MFL's player catalog
        // is temporarily unavailable. In that case the detail rows keep their
        // real ids, scores, statuses, and clocks and display neutral placeholders
        // for only the missing catalog fields.
        let catalog: MFLPlayerCatalog? = if livePlayerIDs.isEmpty {
            nil
        } else {
            try? await client.players(ids: livePlayerIDs.sorted())
        }
        let catalogByID = Dictionary(grouping: catalog?.players ?? [], by: \.id)
            .compactMapValues { $0.count == 1 ? $0[0] : nil }
        let franchiseByID = Dictionary(uniqueKeysWithValues: refreshedLeague.franchises.map { ($0.id, $0) })
        let matchups = live.matchups.compactMap { matchup -> Matchup? in
            guard matchup.franchises.count >= 2 else { return nil }
            let ordered = matchup.franchises.sorted { lhs, rhs in
                if lhs.isHome == rhs.isHome { return lhs.franchiseID < rhs.franchiseID }
                return lhs.isHome == false
            }
            let away = ordered[0]
            let home = ordered[1]
            let awayTeam = makeMatchupTeam(
                away,
                franchise: franchiseByID[away.franchiseID],
                playerCatalog: catalogByID,
                completed: isCompleted,
                projections: projections
            )
            let homeTeam = makeMatchupTeam(
                home,
                franchise: franchiseByID[home.franchiseID],
                playerCatalog: catalogByID,
                completed: isCompleted,
                projections: projections
            )
            return Matchup(
                id: matchup.id,
                away: awayTeam,
                home: homeTeam,
                isUserMatchup: away.franchiseID == workspace.franchiseID || home.franchiseID == workspace.franchiseID,
                status: isCompleted ? .final : gameStatus(for: [away, home])
            )
        }

        return ScoresSnapshot(
            week: live.week ?? week,
            matchups: matchups,
            lastUpdated: Date(),
            isLive: matchups.contains(where: { $0.status.isLive }),
            scorePrecision: scorePrecision(for: refreshedLeague)
        )
    }

    func loadLineup(week: Int) async throws -> LineupSnapshot {
        let (client, league, workspace) = try requireSession()
        let requirements = league.starterRequirements.map {
            LineupPositionRequirement(
                position: $0.position,
                minimum: $0.minimum ?? 0,
                maximum: $0.maximum ?? $0.minimum ?? 0
            )
        }
        let rosterCollection = try await client.rosters(
            franchiseID: workspace.franchiseID,
            week: week,
            refreshPolicy: .reloadIgnoringCache
        )
        guard let roster = rosterCollection.rosters.first(where: { $0.franchiseID == workspace.franchiseID }) else {
            return unavailableLineup(
                week: week,
                league: league,
                requirements: requirements,
                message: "MFL didn’t return a roster for \(workspace.franchiseName) in Week \(week)."
            )
        }

        let playerIDs = roster.players.map(\.id)
        guard !playerIDs.isEmpty else {
            return unavailableLineup(
                week: week,
                league: league,
                requirements: requirements,
                message: "MFL hasn’t published a roster for Week \(week) yet."
            )
        }
        guard Set(playerIDs).count == playerIDs.count else {
            return unavailableLineup(
                week: week,
                league: league,
                requirements: requirements,
                message: "This roster contains duplicate player copies, which this preview can’t edit safely yet."
            )
        }

        async let catalogTask = client.players(ids: playerIDs)
        async let projectionTask = try? await client.projectedScores(week: week)
        async let statusTask = client.playerRosterStatus(
            playerIDs: playerIDs,
            week: week,
            franchiseID: workspace.franchiseID,
            refreshPolicy: .reloadIgnoringCache
        )
        // A `nil` result here means only MFL's narrow documented preseason gap.
        // Other scoring failures remain errors so missing in-season game state
        // cannot accidentally make a player appear movable.
        async let liveTask = liveScoringIfAvailable(
            from: client,
            week: week,
            includeBench: true,
            refreshPolicy: .reloadIgnoringCache
        )
        let (catalog, rosterStatuses, live) = try await (catalogTask, statusTask, liveTask)
        let projections = await projectionTask?.scoresByPlayerID ?? [:]
        let catalogByID = Dictionary(grouping: catalog.players, by: \.id)
        let statusCollectionsByID = Dictionary(grouping: rosterStatuses.statuses, by: \.id)
        let playerByID = catalogByID.compactMapValues { $0.count == 1 ? $0[0] : nil }
        let statusByID = statusCollectionsByID.compactMapValues { $0.count == 1 ? $0[0] : nil }
        let liveFranchise = live?.matchups
            .flatMap(\.franchises)
            .first(where: { $0.franchiseID == workspace.franchiseID })
        let liveByID = Dictionary(grouping: liveFranchise?.players ?? [], by: \.id)
            .compactMapValues { $0.first }

        let assignmentByID = Dictionary(uniqueKeysWithValues: playerIDs.compactMap { playerID in
            statusByID[playerID]?.rosterFranchise(id: workspace.franchiseID).map { (playerID, $0) }
        })
        let supportedStatuses: Set<MFLPlayerLineupStatus> = [
            .starter,
            .nonStarter,
            .injuredReserve,
            .taxiSquad,
        ]
        let hasCompleteAssignments = playerIDs.allSatisfy { playerID in
            assignmentByID[playerID].map { supportedStatuses.contains($0.status) } == true
        }
        let hasCompleteCatalog = playerIDs.allSatisfy { playerID in
            guard let player = playerByID[playerID], let position = player.position else { return false }
            return !cleanText(player.displayName).isEmpty && !position.isEmpty
        }
        let hasUniqueStatuses = playerIDs.allSatisfy { statusCollectionsByID[$0]?.count == 1 }
        let hasCompleteGameState = live == nil || playerIDs.allSatisfy { playerID in
            guard let assignment = assignmentByID[playerID] else { return false }
            if assignment.status == .injuredReserve || assignment.status == .taxiSquad { return true }
            return liveByID[playerID]?.hasReportedGameSecondsRemaining == true
        }
        let hasSupportedRules = supportsLineupEditing(for: league)
        let editState: LineupEditState
        if !hasSupportedRules {
            editState = .unavailable(
                "Lineup changes are not enabled for this league’s rule configuration yet."
            )
        } else if hasCompleteAssignments && hasCompleteCatalog && hasUniqueStatuses && hasCompleteGameState {
            editState = .editable
        } else {
            editState = .unavailable(
                "MFL didn’t return a complete saved lineup and game state for Week \(week), so changes are disabled to protect your starters."
            )
        }

        let players = roster.players.map { rosterPlayer -> LineupPlayer in
            let player = playerByID[rosterPlayer.id]
            let livePlayer = liveByID[rosterPlayer.id]
            let assignment = assignmentByID[rosterPlayer.id]
            let isReserve = assignment?.status == .injuredReserve || assignment?.status == .taxiSquad
            let isLocked: Bool = if isReserve {
                true
            } else if let livePlayer {
                // This only detects an NFL game that has begun. MFL remains
                // authoritative for every league-specific lineup deadline.
                !livePlayer.hasReportedGameSecondsRemaining || livePlayer.gameSecondsRemaining < 3_600
            } else {
                false
            }
            return LineupPlayer(
                id: rosterPlayer.id,
                name: cleanText(player?.displayName ?? "Player \(rosterPlayer.id)"),
                position: player?.position ?? "—",
                nflTeam: player?.nflTeam ?? "FA",
                opponent: "—",
                projectedPoints: projections[rosterPlayer.id]?.doubleValue,
                seasonPoints: livePlayer?.score.doubleValue ?? 0,
                isStarter: assignment?.status == .starter,
                isLocked: isLocked,
                injuryStatus: assignment?.status == .injuredReserve ? .injuredReserve : nil,
                gameTime: Date()
            )
        }

        return LineupSnapshot(
            week: live?.week ?? week,
            players: players,
            requiredStarterCount: league.starterCount ?? players.filter(\.isStarter).count,
            positionRequirements: requirements,
            requiredTiebreakerCount: league.tiebreakerCount ?? 0,
            tiebreakerPlayerIDs: [],
            deadline: nil,
            lastSubmitted: nil,
            serverStarterPlayerIDs: Set(
                assignmentByID.compactMap { playerID, assignment in
                    assignment.status == .starter ? playerID : nil
                }
            ),
            projectionNote: projections.isEmpty
                ? "Week \(week) projections are unavailable from MFL. Missing values stay blank."
                : "Week \(week) · MFL / Fantasy Sharks projections, using your league’s scoring. Missing players stay blank.",
            editState: editState
        )
    }

    private func unavailableLineup(
        week: Int,
        league: MFLLeague,
        requirements: [LineupPositionRequirement],
        message: String
    ) -> LineupSnapshot {
        LineupSnapshot(
            week: week,
            players: [],
            requiredStarterCount: league.starterCount ?? 0,
            positionRequirements: requirements,
            requiredTiebreakerCount: league.tiebreakerCount ?? 0,
            tiebreakerPlayerIDs: [],
            deadline: nil,
            lastSubmitted: nil,
            editState: .unavailable(message)
        )
    }

    private func supportsLineupEditing(for league: MFLLeague) -> Bool {
        guard let starterCount = league.starterCount,
              starterCount > 0,
              league.partialLineupsAllowed == false,
              league.bestLineup == false,
              league.lineupLockout == false,
              !league.starterRequirements.isEmpty
        else { return false }

        let supportedPositions: Set<String> = ["QB", "RB", "WR", "TE"]
        let positionNames = league.starterRequirements.map(\.position)
        guard Set(positionNames).count == positionNames.count,
              positionNames.allSatisfy({ supportedPositions.contains($0) }),
              league.starterRequirements.allSatisfy({ requirement in
                  guard let minimum = requirement.minimum, let maximum = requirement.maximum else {
                      return false
                  }
                  return minimum >= 0 && maximum >= minimum
              })
        else { return false }

        let minimumStarters = league.starterRequirements.compactMap(\.minimum).reduce(0, +)
        let maximumStarters = league.starterRequirements.compactMap(\.maximum).reduce(0, +)
        guard (minimumStarters ... maximumStarters).contains(starterCount) else { return false }

        switch league.tiebreakerCount ?? 0 {
        case 0:
            return league.tiebreakerType == nil
                || league.tiebreakerType?.lowercased() == "none"
        case 1:
            return league.tiebreakerType?.lowercased() == "nonstarter"
        default:
            return false
        }
    }

    /// Returns `nil` only for MFL's documented preseason live-scoring gap.
    /// Authentication, transport, and every other API error continue to fail
    /// closed so a real session problem is never mistaken for an empty week.
    private func liveScoringIfAvailable(
        from client: MFLClient,
        week: Int? = nil,
        includeBench: Bool = false,
        refreshPolicy: MFLRefreshPolicy = .useCache
    ) async throws -> MFLLiveScoring? {
        do {
            return try await client.liveScoring(
                week: week,
                includeBench: includeBench,
                refreshPolicy: refreshPolicy
            )
        } catch {
            guard Self.isPreseasonLiveScoringError(error) else { throw error }
            return nil
        }
    }

    static func isPreseasonLiveScoringError(_ error: Error) -> Bool {
        guard case let MFLCoreError.api(apiMessage) = error else { return false }
        let normalizedMessage = apiMessage.lowercased()
        return normalizedMessage.contains("live scoring")
            && normalizedMessage.contains("not available")
            && normalizedMessage.contains("season starts")
    }

    func submitLineup(_ lineup: LineupSnapshot) async throws {
        let (client, _, workspace) = try requireSession()
        guard lineup.editState.allowsEditing else {
            throw RepositoryError.server(
                "MFL Blitz doesn’t have a complete authoritative lineup state for this week, so nothing was submitted."
            )
        }
        let submittedStarterIDs = lineup.starters.map(\.id)
        let submittedTiebreakerIDs = lineup.tiebreakerPlayerIDs
        let rosterPlayerIDs = lineup.players.map(\.id)
        let rosterPlayerIDSet = Set(rosterPlayerIDs)

        guard !rosterPlayerIDs.isEmpty,
              hasUniqueIdentifiers(rosterPlayerIDs),
              hasUniqueIdentifiers(submittedStarterIDs),
              hasUniqueIdentifiers(submittedTiebreakerIDs),
              Set(submittedStarterIDs).isSubset(of: rosterPlayerIDSet),
              Set(submittedTiebreakerIDs).isSubset(of: rosterPlayerIDSet),
              Set(submittedStarterIDs).isDisjoint(with: submittedTiebreakerIDs),
              submittedStarterIDs.count == lineup.requiredStarterCount,
              submittedTiebreakerIDs.count == lineup.requiredTiebreakerCount
        else {
            throw RepositoryError.server(
                "The lineup has an invalid starter or tiebreaker selection, so it was not submitted."
            )
        }

        let hasInvalidPositionCount = lineup.positionRequirements.contains { requirement in
            let count = lineup.starters.count(where: { $0.position == requirement.position })
            return count < requirement.minimum || count > requirement.maximum
        }
        guard !hasInvalidPositionCount else {
            throw RepositoryError.server(
                "The lineup does not satisfy this league’s position limits, so it was not submitted."
            )
        }

        let tiebreakerIDs = Set(submittedTiebreakerIDs)
        guard lineup.players.allSatisfy({ player in
            !tiebreakerIDs.contains(player.id)
                || (!player.isStarter && !player.isLocked && player.injuryStatus != .injuredReserve)
        }) else {
            throw RepositoryError.server(
                "Every tiebreaker must be an eligible, unlocked bench player, so the lineup was not submitted."
            )
        }

        guard lineup.players.allSatisfy({ player in
            !player.isLocked
                || lineup.serverStarterPlayerIDs.contains(player.id) == player.isStarter
        }) else {
            throw RepositoryError.server(
                "A player whose NFL game has started was moved. Refresh to restore the locked player; nothing was submitted."
            )
        }

        let preflight = try await client.playerRosterStatus(
            playerIDs: rosterPlayerIDs,
            week: lineup.week,
            franchiseID: workspace.franchiseID,
            refreshPolicy: .reloadIgnoringCache
        )
        let preflightStarterIDs = try Self.verifiedStarterIDs(
            from: preflight,
            rosterPlayerIDs: rosterPlayerIDs,
            franchiseID: workspace.franchiseID
        )
        guard containsExactlyTheSameIdentifiers(
            preflightStarterIDs,
            Array(lineup.serverStarterPlayerIDs)
        ) else {
            throw RepositoryError.server(
                "Your saved MFL lineup changed after this screen loaded. Refresh to review the latest starters; nothing was submitted."
            )
        }

        _ = try await client.submitLineup(
            MFLLineupSubmission(
                week: lineup.week,
                starterPlayerIDs: submittedStarterIDs,
                tiebreakerPlayerIDs: submittedTiebreakerIDs
            )
        )

        let verified = try await client.playerRosterStatus(
            playerIDs: rosterPlayerIDs,
            week: lineup.week,
            franchiseID: workspace.franchiseID,
            refreshPolicy: .reloadIgnoringCache
        )
        let serverStarterIDs = try Self.verifiedStarterIDs(
            from: verified,
            rosterPlayerIDs: rosterPlayerIDs,
            franchiseID: workspace.franchiseID
        )
        guard containsExactlyTheSameIdentifiers(serverStarterIDs, submittedStarterIDs) else {
            throw RepositoryError.server(
                "MFL replied, but its saved starters did not exactly match the submitted lineup. Refresh before trying again."
            )
        }
    }

    func loadWaivers() async throws -> WaiverSnapshot {
        let (client, _, workspace) = try requireSession()
        let league = try await client.league(refreshPolicy: .reloadIgnoringCache)
        self.league = league
        async let freeAgentTask = client.freeAgents(refreshPolicy: .reloadIgnoringCache)
        async let pendingTask = client.pendingWaivers(franchiseID: workspace.franchiseID, refreshPolicy: .reloadIgnoringCache)
        async let calendarTask: MFLJSONValue? = try? await client.calendar()
        async let resultsTask: MFLJSONValue? = try? await client.waiverResults()
        let projectionWeek = seasonStatus?.lineupWeek ?? (workspace.weekIsConfirmed ? workspace.week : nil)
        async let projectionTask = projectionsIfAvailable(client: client, week: projectionWeek)
        let (freeAgentPool, pending) = try await (freeAgentTask, pendingTask)
        // A malformed non-empty response must never become an apparently empty
        // queue that a replacement could erase.
        _ = try waiverVerificationClaims(from: pending, franchiseID: workspace.franchiseID)
        let catalog = try await client.players()
        let playerByID = Dictionary(uniqueKeysWithValues: catalog.players.map { ($0.id, $0) })
        let ownedRoster = try await client.rosters(franchiseID: workspace.franchiseID, refreshPolicy: .reloadIgnoringCache)
        let ownedIDs = Set(ownedRoster.rosters.first?.players.map(\.id) ?? [])
        let ownedNames = Dictionary(uniqueKeysWithValues: catalog.players.filter { ownedIDs.contains($0.id) }.map { ($0.id, $0.displayName) })
        let projections = await projectionTask

        let candidates = freeAgentPool.players.compactMap { freeAgent -> WaiverCandidate? in
            guard let player = playerByID[freeAgent.id],
                  let position = player.position,
                  ["QB", "RB", "WR", "TE", "K", "DEF"].contains(position) else { return nil }
            return WaiverCandidate(
                id: freeAgent.id,
                name: cleanText(player.displayName),
                position: position,
                nflTeam: player.nflTeam ?? "FA",
                rosteredPercent: 0,
                projectedPoints: projections[freeAgent.id]?.doubleValue,
                seasonPoints: 0,
                trend: 0,
                injuryStatus: nil
            )
        }
        let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let claims = pending.requests
            .filter { $0.franchiseID == nil || $0.franchiseID == workspace.franchiseID }
            .flatMap { request in
                request.claims.enumerated().compactMap { index, claim -> WaiverClaim? in
                    let player = candidateByID[claim.playerID] ?? makeFallbackCandidate(id: claim.playerID, catalog: playerByID)
                        ?? WaiverCandidate(id: claim.playerID, name: "Player \(claim.playerID)", position: "—", nflTeam: "—", rosteredPercent: 0, projectedPoints: nil, seasonPoints: 0, trend: 0, injuryStatus: nil)
                    return WaiverClaim(
                        player: player,
                        bid: claim.bidAmount ?? 0,
                        dropPlayerID: claim.dropPlayerID,
                        dropPlayerName: claim.dropPlayerID.flatMap { ownedNames[$0] },
                        round: request.round ?? 1,
                        priority: claim.priority ?? index + 1
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.round == rhs.round { return lhs.priority < rhs.priority }
                return lhs.round < rhs.round
            }

        let franchise = league.franchises.first(where: { $0.id == workspace.franchiseID })
        let (calendar, results) = await (calendarTask, resultsTask)
        return WaiverSnapshot(
            availableBudget: franchise?.blindBidAvailableBalance ?? league.blindBidSeasonLimit ?? 0,
            increment: league.blindBidIncrement ?? league.blindBidMinimum ?? 1,
            maxRounds: league.maxWaiverRounds ?? 1,
            candidates: candidates,
            claims: claims,
            processesAt: Self.nextBlindBidDate(in: calendar),
            minimumBid: league.blindBidMinimum ?? 0,
            unavailableReason: franchise?.blindBidAvailableBalance == nil
                ? "MFL didn’t return your remaining bid balance. Check MFL before making changes."
                : waiverAvailability(league),
            results: waiverResults(from: results, catalog: playerByID, league: league),
            resultsUnavailable: results == nil,
            projectionWeek: projectionWeek,
            projectionNote: projections.isEmpty ? "MFL projections are unavailable for this waiver week." : "MFL / Fantasy Sharks · league-scored projections"
        )
    }

    func submitWaivers(_ claims: [WaiverClaim], replacing baseline: [WaiverClaim]) async throws {
        let (client, _, workspace) = try requireSession()
        let fresh = try await loadWaivers()
        if let reason = fresh.unavailableReason { throw RepositoryError.server(reason) }
        let (_, league, _) = try requireSession()
        let expectedClaims = try waiverVerificationClaims(from: claims)
        let baselineClaims = try waiverVerificationClaims(from: baseline)
        let worstCaseSpend = Dictionary(grouping: claims, by: \.round).values
            .reduce(Decimal.zero) { $0 + ($1.map(\.bid).max() ?? 0) }
        let availableIDs = Set(fresh.candidates.map(\.id))
        let owned = try await client.rosters(franchiseID: workspace.franchiseID, refreshPolicy: .reloadIgnoringCache)
        let ownedIDs = Set(owned.rosters.first(where: { $0.franchiseID == workspace.franchiseID })?.players.map(\.id) ?? [])
        guard worstCaseSpend <= fresh.availableBudget,
              claims.allSatisfy({ $0.bid >= fresh.minimumBid && $0.bid.isWholeMultiple(of: fresh.increment)
                && availableIDs.contains($0.player.id)
                && ($0.dropPlayerID == nil || ownedIDs.contains($0.dropPlayerID!)) }),
              Dictionary(grouping: claims, by: \.round).values.allSatisfy({ Set($0.map(\.player.id)).count == $0.count }) else {
            throw RepositoryError.server("Your budget, player availability, drop roster, or bid rules changed. Refresh and review before submitting; nothing was sent.")
        }
        let highestSubmittedRound = expectedClaims.map(\.round).max() ?? 0

        if let configuredMaximum = league.maxWaiverRounds,
           highestSubmittedRound > configuredMaximum
        {
            throw RepositoryError.server(
                "The waiver queue contains a round beyond this league's configured limit, so it was not submitted."
            )
        }

        // Read first so only confirmed differences are mutated. MFL has no
        // transactional batch or idempotency key, so all local validation and
        // comparison happens before the first mutation.
        let pendingBeforeWrite = try await client.pendingWaivers(
            franchiseID: workspace.franchiseID,
            refreshPolicy: .reloadIgnoringCache
        )
        let existingClaims = try waiverVerificationClaims(
            from: pendingBeforeWrite,
            franchiseID: workspace.franchiseID
        )
        if existingClaims == expectedClaims { return }
        guard existingClaims == baselineClaims else {
            throw RepositoryError.server("Your saved MFL waiver queue changed. Compare it with your draft before replacing anything; nothing was sent.")
        }
        let expectedByRound = Dictionary(grouping: expectedClaims, by: \.round)
        let existingByRound = Dictionary(grouping: existingClaims, by: \.round)
        let affectedRounds = Set(expectedByRound.keys)
            .union(existingByRound.keys)
            .filter { expectedByRound[$0, default: []] != existingByRound[$0, default: []] }
            .sorted { lhs, rhs in
                // Make non-empty replacements before deliberate clears. If MFL
                // rejects an early request, confirmed existing later rounds are
                // left intact.
                let lhsIsClear = expectedByRound[lhs, default: []].isEmpty
                let rhsIsClear = expectedByRound[rhs, default: []].isEmpty
                if lhsIsClear != rhsIsClear { return rhsIsClear }
                return lhs < rhs
            }

        var completedRounds: [Int] = []
        for round in affectedRounds {
            let bids = expectedByRound[round, default: []].map {
                MFLBlindBid(
                    playerID: $0.playerID,
                    amount: $0.bid,
                    dropPlayerID: $0.dropPlayerID
                )
            }
            do {
                _ = try await client.submitBlindBidWaiverRequest(
                    MFLBlindBidWaiverRequest(round: round, bids: bids, replaceExisting: true))
                let readback = try await client.pendingWaivers(franchiseID: workspace.franchiseID, refreshPolicy: .reloadIgnoringCache)
                let saved = try waiverVerificationClaims(from: readback, franchiseID: workspace.franchiseID)
                // Verify the whole intermediate queue, not just the modified round.
                let expectedIntermediate = existingClaims.filter { !Set(completedRounds + [round]).contains($0.round) }
                    + expectedClaims.filter { Set(completedRounds + [round]).contains($0.round) }
                guard saved == expectedIntermediate.sorted(by: { ($0.round, $0.position) < ($1.round, $1.position) }) else {
                    throw waiverVerificationUnavailable()
                }
                completedRounds.append(round)
            } catch {
                if let readback = try? await client.pendingWaivers(franchiseID: workspace.franchiseID, refreshPolicy: .reloadIgnoringCache),
                   let saved = try? waiverVerificationClaims(from: readback, franchiseID: workspace.franchiseID),
                   saved == expectedClaims { return }
                throw RepositoryError.server("Waiver save stopped at round \(round). Confirmed earlier rounds: \(completedRounds.map(String.init).joined(separator: ", ").isEmpty ? "none" : completedRounds.map(String.init).joined(separator: ", ")). The interrupted round may have saved. No request was retried. Compare MFL’s saved queue before continuing. \(error.localizedDescription)")
            }
        }

        if !affectedRounds.isEmpty {
            let verified = try await client.pendingWaivers(
                franchiseID: workspace.franchiseID,
                refreshPolicy: .reloadIgnoringCache
            )
            let savedClaims = try waiverVerificationClaims(
                from: verified,
                franchiseID: workspace.franchiseID
            )
            guard savedClaims == expectedClaims else {
                throw RepositoryError.server(
                    "MFL replied, but its saved waiver count, order, players, drops, or bids did not exactly match the submitted queue. Refresh before trying again."
                )
            }
        }
    }

    func loadStandings() async throws -> [StandingRow] {
        let (client, league, workspace) = try requireSession()
        let standings = try await client.standings()
        let franchiseByID = Dictionary(uniqueKeysWithValues: league.franchises.map { ($0.id, $0) })
        let divisionByID = Dictionary(uniqueKeysWithValues: league.divisions.map { ($0.id, $0.name) })

        return standings.franchises.enumerated().map { index, item in
            let franchise = franchiseByID[item.id]
            return StandingRow(
                id: item.id,
                rank: index + 1,
                name: cleanText(franchise?.name ?? "Franchise \(item.id)"),
                abbreviation: franchise?.abbreviation ?? String(format: "%02d", index + 1),
                division: franchise?.divisionID.flatMap { divisionByID[$0] } ?? "League",
                wins: item.wins ?? 0,
                losses: item.losses ?? 0,
                ties: item.ties ?? 0,
                pointsFor: item.pointsFor?.doubleValue ?? 0,
                pointsAgainst: item.pointsAgainst?.doubleValue ?? 0,
                streak: item.streak ?? "—",
                isUser: item.id == workspace.franchiseID,
                accentSeed: Int(item.id) ?? index
            )
        }
    }

    func loadBoard() async throws -> [BoardThread] {
        let (client, league, _) = try requireSession()
        let board = try await client.messageBoard(count: 30, refreshPolicy: .reloadIgnoringCache)
        let franchiseByID = Dictionary(uniqueKeysWithValues: league.franchises.map { ($0.id, cleanText($0.name)) })

        return board.threads.map { summary in
            let preview = summary.attributes["body"]?.stringValue
                ?? summary.attributes["message"]?.stringValue
                ?? "Open to read the latest post."
            return BoardThread(
                id: summary.id,
                subject: cleanText(summary.subject),
                author: summary.lastPostFranchiseID.flatMap { franchiseByID[$0] } ?? "League member",
                preview: cleanText(preview),
                lastActivity: summary.lastPostDate ?? .distantPast,
                replyCount: summary.replyCount ?? 0,
                isUnread: false,
                posts: []
            )
        }
    }

    func loadThread(id: String) async throws -> BoardThread {
        let (client, league, workspace) = try requireSession()
        let loaded = try await client.messageBoardThread(id: id, refreshPolicy: .reloadIgnoringCache)
        let franchiseByID = Dictionary(uniqueKeysWithValues: league.franchises.map { ($0.id, cleanText($0.name)) })
        let existing = try? await loadBoard().first(where: { $0.id == id })
        let posts = loaded.messages.map { message in
            BoardPost(
                id: message.id,
                author: message.franchiseID.flatMap { franchiseByID[$0] } ?? "League member",
                body: cleanText(message.body),
                postedAt: message.date ?? .distantPast,
                isUser: message.franchiseID == workspace.franchiseID
            )
        }
        return BoardThread(
            id: id,
            subject: cleanText(loaded.subject ?? existing?.subject ?? "Message board"),
            author: posts.first?.author ?? existing?.author ?? "League member",
            preview: posts.last?.body ?? existing?.preview ?? "",
            lastActivity: posts.last?.postedAt ?? existing?.lastActivity ?? .distantPast,
            replyCount: max(0, posts.count - 1),
            isUnread: false,
            posts: posts
        )
    }

    func postMessage(subject: String?, body: String, threadID: String?) async throws {
        let (client, _, workspace) = try requireSession()
        guard try await pendingBoardPost() == nil else {
            throw messageVerificationUnavailable()
        }
        let existingIDs: Set<String>
        if let threadID {
            let before = try await client.messageBoardThread(
                id: threadID,
                refreshPolicy: .reloadIgnoringCache
            )
            existingIDs = Set(before.messages.map(\.id))
        } else {
            let before = try await client.messageBoard(count: 100, refreshPolicy: .reloadIgnoringCache)
            existingIDs = Set(before.threads.map(\.id))
        }
        let pending = PendingBoardPost(subject: subject, body: body, threadID: threadID,
                                       existingIDs: existingIDs, startedAt: Date())
        // Fail closed if the marker cannot be persisted BEFORE a possible write.
        try privateStore.encode(pending, key: "board.pending.\(workspace.storageScope)")
        do {
            _ = try await client.postMessageBoard(MFLMessageBoardPost(threadID: threadID, subject: subject, body: body))
        } catch {
            if (try? await reconcileBoardPost()) == true { return }
            throw messageVerificationUnavailable()
        }
        guard try await reconcileBoardPost() else { throw messageVerificationUnavailable() }
    }

    func pendingBoardPost() async throws -> PendingBoardPost? {
        let workspace = try requireWorkspace()
        return try privateStore.decode(PendingBoardPost.self, key: "board.pending.\(workspace.storageScope)")
    }

    func reconcileBoardPost() async throws -> Bool {
        let (client, _, workspace) = try requireSession()
        guard let pending = try await pendingBoardPost() else { return true }
        var confirmed = false
        if let threadID = pending.threadID {
            let thread = try await client.messageBoardThread(id: threadID, refreshPolicy: .reloadIgnoringCache)
            confirmed = thread.messages.contains {
                !pending.existingIDs.contains($0.id) && $0.franchiseID == workspace.franchiseID
                    && cleanText($0.body) == cleanText(pending.body)
            }
        } else {
            let board = try await client.messageBoard(count: 100, refreshPolicy: .reloadIgnoringCache)
            for summary in board.threads where !pending.existingIDs.contains(summary.id)
                && cleanText(summary.subject) == cleanText(pending.subject ?? "") {
                let thread = try await client.messageBoardThread(id: summary.id, refreshPolicy: .reloadIgnoringCache)
                // Verify the new thread's original body and owner, not just a
                // matching subject in a summary list.
                if let first = thread.messages.first,
                   first.franchiseID == workspace.franchiseID,
                   cleanText(first.body) == cleanText(pending.body),
                   first.date.map({ $0 >= pending.startedAt.addingTimeInterval(-120) }) ?? true {
                    confirmed = true
                    break
                }
            }
        }
        if confirmed { try privateStore.remove("board.pending.\(workspace.storageScope)") }
        return confirmed
    }

    func acknowledgeUnconfirmedPost() async throws {
        let workspace = try requireWorkspace()
        try privateStore.remove("board.pending.\(workspace.storageScope)")
    }

    func signOut() async {
        try? privateStore.remove("session")
        await client?.setAuthenticationCookie(nil)
        client = nil
        league = nil
        workspace = nil
        seasonStatus = nil
    }

    private func requireWorkspace() throws -> LeagueWorkspace {
        guard let workspace else { throw RepositoryError.missingSession }
        return workspace
    }

    private func requireSession() throws -> (MFLClient, MFLLeague, LeagueWorkspace) {
        guard let client, let league, let workspace else { throw RepositoryError.missingSession }
        return (client, league, workspace)
    }

    private func makeMatchupTeam(
        _ value: MFLLiveFranchise,
        franchise: MFLFranchise?,
        playerCatalog: [String: MFLPlayer],
        completed: Bool = false,
        projections: [String: Decimal] = [:]
    ) -> MatchupTeam {
        let players = value.players.map { livePlayer in
            var player = makeMatchupPlayer(livePlayer, catalogPlayer: playerCatalog[livePlayer.id])
            if completed { player.gameSecondsRemaining = 0 }
            player.projectedPoints = projections[player.id]?.doubleValue
            return player
        }
        let starters = players.filter { $0.lineupStatus == .starter }
        let starterProjections = starters.compactMap(\.projectedPoints)
        let projectedTotal = !starters.isEmpty && starterProjections.count == starters.count
            ? starterProjections.reduce(0, +) : nil
        return MatchupTeam(
            id: value.franchiseID,
            name: cleanText(franchise?.name ?? "Franchise \(value.franchiseID)"),
            abbreviation: franchise?.abbreviation ?? value.franchiseID,
            score: value.score.doubleValue,
            projectedScore: projectedTotal,
            playersRemaining: value.playersYetToPlay + value.playersCurrentlyPlaying,
            accentSeed: Int(value.franchiseID) ?? 0,
            starters: players.filter { $0.lineupStatus == .starter },
            bench: players.filter { $0.lineupStatus == .bench },
            unclassifiedPlayers: players.filter { $0.lineupStatus == .unknown }
        )
    }

    private func projectionsIfAvailable(client: MFLClient, week: Int?) async -> [String: Decimal] {
        guard let week else { return [:] }
        return (try? await client.projectedScores(week: week))?.scoresByPlayerID ?? [:]
    }

    private func scorePrecision(for league: MFLLeague) -> Int {
        min(max(league.scorePrecision ?? 1, 0), 4)
    }

    private func makeMatchupPlayer(
        _ value: MFLLivePlayer,
        catalogPlayer: MFLPlayer?
    ) -> MatchupPlayer {
        let status: MatchupLineupStatus
        if value.status.rawValue.caseInsensitiveCompare(MFLLivePlayerStatus.starter.rawValue) == .orderedSame {
            status = .starter
        } else if value.status.rawValue.caseInsensitiveCompare(MFLLivePlayerStatus.nonstarter.rawValue) == .orderedSame {
            status = .bench
        } else {
            status = .unknown
        }

        let cleanedName = catalogPlayer.map { cleanText($0.displayName) } ?? ""
        let cleanedStatLine = value.updatedStats.map(cleanText)
        return MatchupPlayer(
            id: value.id,
            name: cleanedName.isEmpty ? "Player \(value.id)" : cleanedName,
            position: catalogPlayer?.position.flatMap { $0.isEmpty ? nil : $0 } ?? "—",
            nflTeam: catalogPlayer?.nflTeam.flatMap { $0.isEmpty ? nil : $0 } ?? "—",
            livePoints: value.hasReportedScore ? value.score.doubleValue : nil,
            lineupStatus: status,
            gameSecondsRemaining: value.hasReportedGameSecondsRemaining
                ? value.gameSecondsRemaining
                : nil,
            statLine: cleanedStatLine.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private func gameStatus(for franchises: [MFLLiveFranchise]) -> GameStatus {
        if franchises.contains(where: { $0.playersCurrentlyPlaying > 0 }) {
            return .live("In progress")
        }
        if franchises.contains(where: { $0.playersYetToPlay > 0 }) {
            return .pregame(nil)
        }
        // Missing clocks/zero preseason totals are not evidence of a final game.
        let starters = franchises.flatMap(\.players).filter(\.isStarter)
        if !starters.isEmpty, starters.allSatisfy({ $0.hasReportedGameSecondsRemaining && $0.gameSecondsRemaining == 0 }) {
            return .final
        }
        return .pregame(nil)
    }

    private func waiverAvailability(_ league: MFLLeague) -> String? {
        guard league.conditionalBlindBidding == true,
              league.currentWaiverType?.uppercased().contains("BBID") == true,
              let rounds = league.maxWaiverRounds, rounds > 0,
              league.blindBidMinimum != nil, league.blindBidSeasonLimit != nil else {
            return "This waiver window or league format is not supported for native bidding. Use MFL for first-come adds or other waiver formats."
        }
        return nil
    }

    static func nextBlindBidDate(in value: MFLJSONValue?, now: Date = Date()) -> Date? {
        let events = value?.objectValue?["calendar"]?.objectValue?["event"]?.arrayValue ?? []
        return events.compactMap { event -> Date? in
            guard let fields = event.objectValue,
                  (fields["type"]?.stringValue ?? fields["event_type"]?.stringValue) == "WAIVER_BBID",
                  let raw = fields["start_time"]?.stringValue ?? fields["timestamp"]?.stringValue,
                  let timestamp = TimeInterval(raw) else { return nil }
            let date = Date(timeIntervalSince1970: timestamp)
            // Only explicit future occurrences are shown. Do not guess recurring
            // events across time zones/DST from an old occurrence.
            return date > now ? date : nil
        }.min()
    }

    private func waiverResults(from value: MFLJSONValue?, catalog: [String: MFLPlayer], league: MFLLeague) -> [WaiverResult] {
        let rows = value?.objectValue?["transactions"]?.objectValue?["transaction"]?.arrayValue ?? []
        return rows.enumerated().compactMap { index, item in
            guard let fields = item.objectValue,
                  let type = fields["type"]?.stringValue,
                  ["BBID_WAIVER", "WAIVER", "FREE_AGENT"].contains(type) else { return nil }
            let franchiseID = fields["franchise"]?.stringValue ?? fields["franchise_id"]?.stringValue
            let franchise = league.franchises.first { $0.id == franchiseID }
            let raw = fields["transaction"]?.stringValue ?? ""
            let parts = raw.components(separatedBy: "|")
            func names(_ part: String) -> String {
                part.split(separator: ",").map { id in cleanText(catalog[String(id)]?.displayName ?? "Player \(id)") }.joined(separator: ", ")
            }
            var detail = type == "BBID_WAIVER" ? "Blind-bid waiver processed" : "Player acquisition"
            if let adds = parts.first, !adds.isEmpty { detail = "Added \(names(adds))" }
            if parts.count > 1, !parts[1].isEmpty { detail += " · Dropped \(names(parts[1]))" }
            if parts.count > 2, let amount = Decimal(string: parts[2]), amount >= 0 {
                detail += " · \(amount.formatted(.currency(code: "USD")))"
            }
            return WaiverResult(id: fields["id"]?.stringValue ?? "\(index)-\(raw)",
                franchise: cleanText(franchise?.name ?? "League member"), description: detail,
                date: fields["timestamp"]?.stringValue.flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) })
        }
    }

    private func makeFallbackCandidate(
        id: String,
        catalog: [String: MFLPlayer]
    ) -> WaiverCandidate? {
        guard let player = catalog[id] else { return nil }
        return WaiverCandidate(
            id: id,
            name: cleanText(player.displayName),
            position: player.position ?? "—",
            nflTeam: player.nflTeam ?? "FA",
            rosteredPercent: 0,
            projectedPoints: nil,
            seasonPoints: 0,
            trend: 0,
            injuryStatus: nil
        )
    }

    private func hasUniqueIdentifiers(_ identifiers: [String]) -> Bool {
        Set(identifiers).count == identifiers.count
    }

    private func containsExactlyTheSameIdentifiers(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.count == rhs.count && Set(lhs) == Set(rhs)
    }

    static func verifiedStarterIDs(
        from response: MFLPlayerRosterStatusCollection,
        rosterPlayerIDs: [String],
        franchiseID: String
    ) throws -> [String] {
        let requestedIDs = Set(rosterPlayerIDs)
        let statusesByID = Dictionary(
            grouping: response.statuses.filter { requestedIDs.contains($0.id) },
            by: \.id
        )
        guard requestedIDs.count == rosterPlayerIDs.count,
              requestedIDs.allSatisfy({ statusesByID[$0]?.count == 1 })
        else {
            throw RepositoryError.server(
                "MFL did not return one unique roster status for every player, so the lineup could not be confirmed."
            )
        }

        var starterIDs: [String] = []
        for playerID in rosterPlayerIDs {
            guard let status = statusesByID[playerID]?.first,
                  let assignment = status.rosterFranchise(id: franchiseID),
                  [.starter, .nonStarter, .injuredReserve, .taxiSquad].contains(assignment.status)
            else {
                throw RepositoryError.server(
                    "MFL returned an incomplete or ambiguous lineup state, so the lineup could not be confirmed."
                )
            }
            if assignment.status == .starter { starterIDs.append(playerID) }
        }
        return starterIDs
    }

    private struct VerifiedWaiverClaim: Equatable {
        let round: Int
        let position: Int
        let playerID: String
        let dropPlayerID: String?
        let bid: Decimal
    }

    private struct ServerWaiverClaim {
        let claim: MFLWaiverClaim
    }

    private func waiverVerificationClaims(from claims: [WaiverClaim]) throws -> [VerifiedWaiverClaim] {
        guard claims.allSatisfy({
            $0.round > 0
                && $0.priority > 0
                && isValidMFLIdentifier($0.player.id)
                && $0.bid >= 0
                && !$0.bid.isNaN
                && ($0.dropPlayerID.map { isValidMFLIdentifier($0) } ?? true)
        }) else {
            throw RepositoryError.server(
                "Every waiver request needs a valid player, bid, drop, and positive round, so the queue was not submitted."
            )
        }

        let indexedClaims = claims.enumerated().sorted { lhs, rhs in
            if lhs.element.round == rhs.element.round {
                if lhs.element.priority == rhs.element.priority {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.priority < rhs.element.priority
            }
            return lhs.element.round < rhs.element.round
        }

        let prioritiesByRound = Dictionary(grouping: indexedClaims, by: \.element.round)
        guard prioritiesByRound.values.allSatisfy({ values in
            values.map(\.element.priority) == Array(1 ... values.count)
        }) else {
            throw RepositoryError.server(
                "Waiver alternatives in each round must have a unique, consecutive priority, so the queue was not submitted."
            )
        }

        return indexedClaims.map { indexed in
            return VerifiedWaiverClaim(
                round: indexed.element.round,
                position: indexed.element.priority,
                playerID: indexed.element.player.id,
                dropPlayerID: normalizedDropPlayerID(indexed.element.dropPlayerID),
                bid: indexed.element.bid
            )
        }
    }

    private func waiverVerificationClaims(
        from pending: MFLPendingWaivers,
        franchiseID: String
    ) throws -> [VerifiedWaiverClaim] {
        var claimsByRound: [Int: [ServerWaiverClaim]] = [:]

        for request in pending.requests where requestBelongsToFranchise(request, franchiseID: franchiseID) {
            guard rawClaimCount(in: request) == request.claims.count else {
                throw waiverVerificationUnavailable()
            }
            guard !request.claims.isEmpty else {
                // Empty requests are only authoritative if an explicit empty
                // claim/picks field was supplied; an unknown request is not empty.
                let known = ["pick", "claim", "bid", "request", "picks", "PICKS"]
                guard known.contains(where: { request.attributes[$0] != nil }) else {
                    throw waiverVerificationUnavailable()
                }
                continue
            }
            guard let round = request.round, round > 0 else {
                throw waiverVerificationUnavailable()
            }
            guard rawClaimCount(in: request) == request.claims.count else {
                throw waiverVerificationUnavailable()
            }

            let compactDropEvidence = compactClaimsHaveExplicitDrops(in: request)
            for (index, claim) in request.claims.enumerated() {
                let hasExplicitDrop = hasExplicitDropAttribute(claim)
                    || compactDropEvidence?[safe: index] == true
                guard claim.bidAmount != nil, hasExplicitDrop else {
                    throw waiverVerificationUnavailable()
                }
                claimsByRound[round, default: []].append(
                    ServerWaiverClaim(claim: claim)
                )
            }
        }

        var verified: [VerifiedWaiverClaim] = []
        for round in claimsByRound.keys.sorted() {
            guard let serverClaims = claimsByRound[round] else { continue }
            let priorities = serverClaims.map(\.claim.priority)
            if priorities.contains(where: { $0 != nil }) {
                guard priorities.allSatisfy({ $0 != nil }),
                      priorities.compactMap({ $0 }) == Array(1 ... serverClaims.count)
                else {
                    throw waiverVerificationUnavailable()
                }
            }

            for (offset, value) in serverClaims.enumerated() {
                guard let bid = value.claim.bidAmount else {
                    throw waiverVerificationUnavailable()
                }
                verified.append(
                    VerifiedWaiverClaim(
                        round: round,
                        position: offset + 1,
                        playerID: value.claim.playerID,
                        dropPlayerID: normalizedDropPlayerID(value.claim.dropPlayerID),
                        bid: bid
                    )
                )
            }
        }
        return verified
    }

    private func requestBelongsToFranchise(
        _ request: MFLPendingWaiver,
        franchiseID: String
    ) -> Bool {
        request.franchiseID == nil || request.franchiseID == franchiseID
    }

    private func rawClaimCount(in request: MFLPendingWaiver) -> Int {
        for key in ["pick", "claim", "bid", "request"] {
            if let value = request.attributes[key] {
                return value.arrayValue?.count ?? 0
            }
        }
        if let compact = request.attributes["picks"]?.stringValue
            ?? request.attributes["PICKS"]?.stringValue
        {
            return compact.split(separator: ",", omittingEmptySubsequences: true).count
        }
        return request.claims.count
    }

    private func compactClaimsHaveExplicitDrops(in request: MFLPendingWaiver) -> [Bool]? {
        guard let compact = request.attributes["picks"]?.stringValue
            ?? request.attributes["PICKS"]?.stringValue
        else {
            return nil
        }
        return compact.split(separator: ",", omittingEmptySubsequences: true).map { pick in
            pick.split(separator: "_", omittingEmptySubsequences: false).count >= 3
        }
    }

    private func hasExplicitDropAttribute(_ claim: MFLWaiverClaim) -> Bool {
        let keys = Set(claim.attributes.keys.map { $0.lowercased() })
        return !keys.isDisjoint(with: [
            "drop",
            "dropplayer",
            "drop_player",
            "dropplayerid",
            "drop_player_id",
        ])
    }

    private func normalizedDropPlayerID(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "0000" else { return nil }
        return value
    }

    private func isValidMFLIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty
            && !identifier.contains(",")
            && !identifier.contains("_")
            && !identifier.contains("\r")
            && !identifier.contains("\n")
    }

    private func waiverVerificationUnavailable() -> RepositoryError {
        RepositoryError.server(
            "MFL replied, but omitted a waiver round, order, drop, or bid needed to verify the saved queue. Refresh and confirm it on MFL."
        )
    }

    private func messageBody(in attributes: [String: MFLJSONValue]) -> String? {
        attributes["body"]?.stringValue
            ?? attributes["message"]?.stringValue
            ?? attributes["text"]?.stringValue
    }

    private func messageVerificationUnavailable() -> RepositoryError {
        RepositoryError.server(
            "MFL accepted the message, but the board export did not provide enough matching data to verify it. Refresh and confirm it on MFL."
        )
    }

    private nonisolated func cleanText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
