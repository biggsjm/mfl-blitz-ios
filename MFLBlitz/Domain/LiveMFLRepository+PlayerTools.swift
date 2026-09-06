import Foundation
import MFLCore

extension LiveMFLRepository {
    private enum AvailabilitySource: Sendable {
        case injuries(MFLInjuries?), schedule(MFLNFLSchedule?), byes(MFLByeWeeks?)
    }

    func loadPlayerAvailability(week: Int, refresh: Bool) async throws -> PlayerAvailabilitySnapshot {
        let (client, _, workspace) = try requireSession()
        let result = try await withThrowingTaskGroup(of: AvailabilitySource.self) { group in
            // Cache source data at its own cadence; explicit refresh may refresh
            // injuries/schedule but does not re-download the daily bye table.
            let policy: MFLRefreshPolicy = refresh ? .reloadIgnoringCache : .useCache
            group.addTask { .injuries(try await TeamPlayerMapper.optionalRead { try await client.injuries(week: week, refreshPolicy: policy) }) }
            group.addTask { .schedule(try await TeamPlayerMapper.optionalRead { try await client.nflSchedule(week: week, refreshPolicy: policy) }) }
            group.addTask { .byes(try await TeamPlayerMapper.optionalRead { try await client.nflByeWeeks() }) }
            var snapshot = PlayerAvailabilitySnapshot(scope: workspace.storageScope, week: week)
            for try await source in group {
                switch source {
                case .injuries(let value):
                    guard let value else { snapshot.issues.append("Injury report unavailable."); continue }
                    snapshot.injuryUpdatedAt = value.timestamp
                    snapshot.injuries = value.byPlayerID.compactMapValues { entry in
                        guard let status = TeamPlayerMapper.text(entry.status) else { return nil }
                        return PlayerHealth(status: status, details: TeamPlayerMapper.text(entry.details))
                    }
                case .schedule(let value):
                    guard let value else { snapshot.issues.append("NFL schedule unavailable."); continue }
                    var candidates: [String: [NFLGameContext]] = [:]
                    for game in value.matchups where game.teams.count == 2 {
                        guard game.teams[0].id != game.teams[1].id else { continue }
                        for index in 0...1 {
                            let own = game.teams[index], opponent = game.teams[1-index]
                            candidates[own.id, default: []].append(NFLGameContext(opponent: opponent.id,
                                isHome: own.isHome, kickoff: game.kickoff))
                        }
                    }
                    snapshot.games = candidates.compactMapValues { $0.count == 1 ? $0.first : nil }
                case .byes(let value):
                    if let value { snapshot.byeWeeks = value.byTeamID }
                    else { snapshot.issues.append("Bye information unavailable.") }
                }
            }
            return snapshot
        }
        try validatePlayerToolsSession(client, workspace.storageScope)
        return result
    }

    func loadPlayerResearch(playerID: String, beforeWeek: Int?, contextWeek: Int) async throws -> PlayerResearchPage {
        let (client, _, workspace) = try requireSession()
        let status = try await playerToolsSeasonStatus(client: client)
        let league = try await client.league()
        let completed = min(status.completedWeek, league.endWeek ?? 18)
        let start = max(1, league.startWeek ?? 1)
        let last = min(completed, beforeWeek.map { $0 - 1 } ?? completed)
        var page = PlayerResearchPage(scope: workspace.storageScope, playerID: playerID,
            completedWeek: completed, weeks: [])
        guard last >= start else { return page }
        // Each page is at most four targeted reads, not four complete league weeks.
        let first = max(start, last - 3)
        for week in stride(from: last, through: first, by: -1) {
            let response = try await TeamPlayerMapper.optionalRead {
                try await client.playerScores(playerIDs: [playerID], period: .week(week))
            }
            try validatePlayerToolsSession(client, workspace.storageScope)
            let points = response?.scoresByPlayerID[playerID].map { NSDecimalNumber(decimal: $0).doubleValue }
            page.weeks.append(PlayerHistoryWeek(week: week, points: points?.isFinite == true ? points : nil,
                unavailable: response == nil))
        }
        page.nextBeforeWeek = first > start ? first : nil
        if beforeWeek == nil {
            let total = try await TeamPlayerMapper.optionalRead {
                try await client.playerScores(playerIDs: [playerID], period: .yearToDate)
            }
            let average = try await TeamPlayerMapper.optionalRead {
                try await client.playerScores(playerIDs: [playerID], period: .average)
            }
            page.total = total?.scoresByPlayerID[playerID].map { NSDecimalNumber(decimal: $0).doubleValue }
            page.average = average?.scoresByPlayerID[playerID].map { NSDecimalNumber(decimal: $0).doubleValue }
            if total == nil || average == nil { page.issues.append("Season totals could not be refreshed.") }
            // An empty preseason pointsAllowed response is valid. Do not guess
            // field meanings or manufacture a matchup rank from absent data.
            let allowed = try await TeamPlayerMapper.optionalRead { try await client.pointsAllowed() }
            let catalog = try await client.players()
            if let player = catalog.players.first(where: { $0.id == playerID }),
               let team = player.nflTeam, let position = player.position {
                let availability = try await loadPlayerAvailability(week: contextWeek, refresh: false)
                if let opponent = availability.games[team]?.opponent {
                    page.opponentName = opponent
                    page.opponentPointsAllowed = Self.pointsAllowed(allowed, opponent: opponent, position: position)
                }
            }
        }
        try validatePlayerToolsSession(client, workspace.storageScope)
        return page
    }

    /// Verified against the league's nonempty 2025 export: `points` is a
    /// position total, not an average. Do not divide by an assumed games count.
    static func pointsAllowed(_ value: MFLJSONValue?, opponent: String, position: String) -> Double? {
        guard let teams = value?.objectValue?["pointsAllowed"]?.objectValue?["team"]?.arrayValue else { return nil }
        let matches = teams.compactMap(\.objectValue).filter { $0["id"]?.stringValue == opponent }
        guard matches.count == 1, let entries = matches[0]["position"]?.arrayValue else { return nil }
        let positions = entries.compactMap(\.objectValue).filter {
            ($0["name"]?.stringValue ?? $0["id"]?.stringValue) == position
        }
        guard positions.count == 1, let raw = positions[0]["points"]?.stringValue,
              let score = Double(raw), score.isFinite else { return nil }
        return score
    }

    func loadWatchList(refresh: Bool) async throws -> WatchListSnapshot {
        let (client, _, workspace) = try requireSession()
        let list = try await client.watchList(refreshPolicy: refresh ? .reloadIgnoringCache : .useCache)
        let catalog = try await client.players()
        try validatePlayerToolsSession(client, workspace.storageScope)
        let byID = Dictionary(uniqueKeysWithValues: catalog.players.map { ($0.id, $0) })
        let players = list.playerIDs.map { TeamPlayerMapper.identity(byID[$0], id: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let pending = try privateStore.decode(PendingWatchAction.self, key: "watch-action.\(workspace.storageScope)")
        return WatchListSnapshot(scope: workspace.storageScope, players: players, pending: pending)
    }

    func setWatched(playerID: String, isWatched: Bool) async throws -> WatchListSnapshot {
        guard !watchMutationInFlight else { throw RepositoryError.server("A watchlist change is still being checked.") }
        watchMutationInFlight = true
        defer { watchMutationInFlight = false }
        let (client, _, workspace) = try requireSession()
        let key = "watch-action.\(workspace.storageScope)"
        guard try privateStore.read(key) == nil else {
            throw RepositoryError.server("Check the previous watchlist change before trying again.")
        }
        let before = try await loadWatchList(refresh: true)
        try validatePlayerToolsSession(client, workspace.storageScope)
        if before.playerIDs.contains(playerID) == isWatched { return before }
        try privateStore.encode(PendingWatchAction(playerID: playerID, isWatched: isWatched, startedAt: Date()), key: key)
        // The marker survives every error after this point. Never blindly retry.
        _ = try? await client.updateWatchList(playerID: playerID, isWatched: isWatched)
        try validatePlayerToolsSession(client, workspace.storageScope)
        return try await reconcileWatchList()
    }

    func reconcileWatchList() async throws -> WatchListSnapshot {
        let (client, _, workspace) = try requireSession()
        var fresh = try await loadWatchList(refresh: true)
        try validatePlayerToolsSession(client, workspace.storageScope)
        if let pending = fresh.pending, fresh.playerIDs.contains(pending.playerID) == pending.isWatched {
            try privateStore.remove("watch-action.\(workspace.storageScope)")
            fresh.pending = nil
        }
        return fresh
    }

    func acknowledgeWatchList() async throws {
        let (_, _, workspace) = try requireSession()
        guard !watchMutationInFlight else { throw RepositoryError.server("Wait for the current watchlist change.") }
        try privateStore.remove("watch-action.\(workspace.storageScope)")
    }

    func validatePlayerToolsSession(_ client: MFLClient, _ scope: String) throws {
        try Task.checkCancellation()
        let active = try requireSession()
        guard active.0 === client, active.2.storageScope == scope else { throw CancellationError() }
    }
}
