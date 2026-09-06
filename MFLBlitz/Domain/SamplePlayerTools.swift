import Foundation

extension DemoLeagueRepository {
    func previewRoster(franchiseID: String, week: Int?) -> [RosterPlayerSummary] {
        let base = SampleTeamPlayers.roster(franchiseID: franchiseID, lineupWeek: week)
        guard franchiseID == SampleData.workspace.franchiseID, let membership = demoMembership else { return base }
        return membership.map { id, status in
            let original = base.first { $0.id == id }
            let candidate = SampleData.waivers.candidates.first { $0.id == id }
            return RosterPlayerSummary(identity: original?.identity ?? PlayerIdentity(id: id,
                name: candidate?.name ?? "Player \(id)", position: candidate?.position, nflTeam: candidate?.nflTeam),
                membership: RosterMembership(rawValue: status),
                lineupAssignment: status == "INJURED_RESERVE" ? .injuredReserve : original?.lineupAssignment ?? .nonstarter)
        }.sorted { $0.id < $1.id }
    }

    func loadRosterActionContext() async throws -> RosterActionContext {
        let roster = previewRoster(franchiseID: SampleData.workspace.franchiseID, week: nil)
        return RosterActionContext(scope: SampleData.workspace.storageScope, ownerID: SampleData.workspace.franchiseID,
            players: roster.map(\.identity), membership: Dictionary(uniqueKeysWithValues: roster.map {
                ($0.id, $0.membership == .injuredReserve ? "INJURED_RESERVE" : "ROSTER")
            }), activeLimit: 18, irLimit: 3, allowed: Set(RosterActionKind.allCases))
    }

    func performRosterAction(_ request: RosterActionRequest, reviewed: RosterActionContext) async throws -> RosterActionReceipt {
        let context = try await loadRosterActionContext()
        guard context.scope == reviewed.scope, context.membership == reviewed.membership else {
            throw RepositoryError.server("Your preview roster changed. Review the move again.")
        }
        if let error = context.problem(for: request) { throw RepositoryError.server(error) }
        demoMembership = context.expectedMembership(after: request)
        return RosterActionReceipt(confirmed: true, message: "Preview roster updated")
    }

    func loadPlayerAvailability(week: Int, refresh: Bool) async throws -> PlayerAvailabilitySnapshot {
        var value = PlayerAvailabilitySnapshot(scope: SampleData.workspace.storageScope, week: week)
        let roster = SampleData.lineup.players
        for player in roster {
            value.games[player.nflTeam] = NFLGameContext(opponent: "CHI", isHome: true,
                kickoff: Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 12), matchingPolicy: .nextTime))
            value.byeWeeks[player.nflTeam] = 8
        }
        if let player = roster.last { value.injuries[player.id] = PlayerHealth(status: "Questionable", details: "Knee") }
        // Explicitly synthetic eligibility for the preview IR journey.
        value.injuries["12620"] = PlayerHealth(status: "Out", details: "Preview injury designation")
        value.injuries["13319"] = PlayerHealth(status: "Questionable", details: "Preview injury designation")
        value.injuryUpdatedAt = Date().addingTimeInterval(-3_600)
        return value
    }

    func loadPlayerResearch(playerID: String, beforeWeek: Int?, contextWeek: Int) async throws -> PlayerResearchPage {
        // Synthetic history is explicitly inside Preview, not mixed into live reads.
        let completed = 4
        let last = min(completed, (beforeWeek ?? 5) - 1)
        let weeks = last > 0 ? stride(from: last, through: max(1, last - 3), by: -1).map {
            PlayerHistoryWeek(week: $0, points: [0.0, 14.2, 8.7, 19.1][$0 - 1])
        } : []
        return PlayerResearchPage(scope: SampleData.workspace.storageScope, playerID: playerID,
            completedWeek: completed, total: 42, average: 10.5, weeks: weeks,
            opponentPointsAllowed: 16.4, opponentName: "CHI")
    }

    func loadWatchList(refresh: Bool) async throws -> WatchListSnapshot {
        var players: [PlayerIdentity] = []
        for id in demoWatched.sorted() { players.append(try await loadPlayerDetail(playerID: id, refresh: false).identity) }
        return WatchListSnapshot(scope: SampleData.workspace.storageScope, players: players)
    }

    func setWatched(playerID: String, isWatched: Bool) async throws -> WatchListSnapshot {
        if isWatched { demoWatched.insert(playerID) } else { demoWatched.remove(playerID) }
        return try await loadWatchList(refresh: true)
    }

    func acknowledgeWatchList() async throws {}
}
