import Foundation

enum MatchupModeSection: String, CaseIterable, Identifiable, Sendable {
    case completed, inProgress, upcoming, unavailable
    var id: String { rawValue }
    var title: String {
        switch self {
        case .completed: "Completed"
        case .inProgress: "In progress"
        case .upcoming: "Yet to play"
        case .unavailable: "Other game states"
        }
    }
}

/// A view of the existing weekly snapshot, never another data subscription.
struct MatchupModeTeam {
    struct Entry: Identifiable {
        var player: MatchupPlayer
        let section: MatchupModeSection
        let state: String
        let kickoff: Date?
        var id: String { player.id }
    }
    let entries: [Entry]
    let official: Double?
    let hasUnclassifiedPlayers: Bool

    init(team: MatchupTeam, week: Int, scope: String?, feed: NFLWeekFeed?,
         availability: PlayerAvailabilitySnapshot?, scoringGames: NFLScoringSnapshot? = nil, now: Date = Date()) {
        official = team.reportedScore
        hasUnclassifiedPlayers = !team.unclassifiedPlayers.isEmpty
        let data = availability.flatMap { $0.scope == scope && $0.week == week ? $0 : nil }
        var seen = Set<String>()
        entries = team.starters.compactMap { original in
            guard seen.insert(original.id).inserted else { return nil }
            var player = original
            let records = team.starters.filter { $0.id == original.id }
            if Set(records).count > 1 {
                player.livePoints = nil; player.gameSecondsRemaining = nil
                return Entry(player: player, section: .unavailable, state: "Conflicting player data", kickoff: nil)
            }
            let game = feed.flatMap { $0.week == week ? $0.game(team: player.nflTeam) : nil }
            let info = MatchupGameInfo(player: player, availability: data, scope: scope, week: week,
                scoringGames: scoringGames, nflGame: game, now: now)
            let kickoff = game.map { Date(timeIntervalSince1970: $0.kickoff) } ?? data?.games[player.nflTeam]?.kickoff
            let section: MatchupModeSection
            let state: String
            if let game, game.status != "NS" || !info.isLive {
                section = game.isLive ? .inProgress : game.isFinal ? .completed : game.status == "NS" ? .upcoming : .unavailable
                state = (game.gameIsStale(now: now) ? "Last known: " : "") + game.statusLabel
            } else if data?.byeWeeks[player.nflTeam] == week {
                section = .unavailable; state = "Bye week"
            } else {
                if info.isLive {
                    section = .inProgress; state = info.status ?? "In progress"
                } else if info.status == "Regulation complete" {
                    section = .unavailable; state = "Regulation complete"
                } else if info.status == "Final" {
                    section = .completed; state = "Final"
                } else if info.kickoff != nil {
                    section = .upcoming; state = "Scheduled"
                } else {
                switch player.gameState {
                case .live: section = .inProgress; state = "In progress"
                case .final: section = .completed; state = "Final"
                case .pregame: section = .upcoming; state = "Scheduled"
                case .unknown: section = .unavailable; state = "Status unavailable"
                }
                }
            }
            return Entry(player: player, section: section, state: state, kickoff: kickoff)
        }
    }

    func entries(in section: MatchupModeSection) -> [Entry] { entries.filter { $0.section == section } }
    func points(in section: MatchupModeSection) -> Double? { Self.total(entries(in: section).map(\.player)) }
    var starterTotal: Double? { hasUnclassifiedPlayers ? nil : Self.total(entries.map(\.player)) }
    var difference: Double? {
        guard let official, let starterTotal else { return nil }
        return official - starterTotal
    }
    var nextKickoff: Date? { entries(in: .upcoming).compactMap(\.kickoff).min() }

    static func total(_ players: [MatchupPlayer]) -> Double? {
        guard players.allSatisfy({ $0.livePoints?.isFinite == true }) else { return nil }
        let decimal = players.compactMap { $0.livePoints.flatMap { Decimal(string: String($0)) } }.reduce(0, +)
        return NSDecimalNumber(decimal: decimal).doubleValue
    }
}
