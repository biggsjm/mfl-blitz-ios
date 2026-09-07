import Foundation
import MFLCore

enum SampleData {
    static let now = Date()

    static let workspace = LeagueWorkspace(
        leagueID: "41333",
        season: 2026,
        leagueName: "Champion Hall",
        franchiseID: "0001",
        franchiseName: "Uber Beasts",
        baseURL: URL(string: "https://www45.myfantasyleague.com")!,
        week: 1
    )

    static let scores = ScoresSnapshot(
        week: 1,
        matchups: [
            Matchup(
                id: "0001-0008",
                away: .init(id: "0001", name: "Uber Beasts", abbreviation: "UB", score: 112.7, projectedScore: 128.4, playersRemaining: 3, accentSeed: 1, starters: demoStarters("0001", "UB", score: 112.7, remaining: 3), bench: demoBench("0001", "UB")),
                home: .init(id: "0008", name: "GPT 5.0 now available", abbreviation: "RU", score: 108.2, projectedScore: 121.9, playersRemaining: 2, accentSeed: 8, starters: demoStarters("0008", "RU", score: 108.2, remaining: 2), bench: demoBench("0008", "RU")),
                isUserMatchup: true,
                status: .live("3rd · 8:42")
            ),
            Matchup(
                id: "0002-0011",
                away: .init(id: "0002", name: "Croton Bug Eaters", abbreviation: "CBE", score: 96.4, projectedScore: 119.1, playersRemaining: 4, accentSeed: 2, starters: demoStarters("0002", "CBE", score: 96.4, remaining: 4), bench: demoBench("0002", "CBE")),
                home: .init(id: "0011", name: "The Mean Green", abbreviation: "TMG", score: 101.8, projectedScore: 124.3, playersRemaining: 3, accentSeed: 11, starters: demoStarters("0011", "TMG", score: 101.8, remaining: 3), bench: demoBench("0011", "TMG")),
                isUserMatchup: false,
                status: .live("Halftime")
            ),
            Matchup(
                id: "0003-0007",
                away: .init(id: "0003", name: "Secret Asian Man", abbreviation: "SAM", score: 0, projectedScore: 117.6, playersRemaining: 9, accentSeed: 3, starters: demoStarters("0003", "SAM", score: 0, remaining: 9, isPregame: true), bench: demoBench("0003", "SAM", isPregame: true)),
                home: .init(id: "0007", name: "Fields of Gold", abbreviation: "JPH", score: 0, projectedScore: 125.8, playersRemaining: 9, accentSeed: 7, starters: demoStarters("0007", "JPH", score: 0, remaining: 9, isPregame: true), bench: demoBench("0007", "JPH", isPregame: true)),
                isUserMatchup: false,
                status: .pregame(Calendar.current.date(byAdding: .hour, value: 3, to: now)!)
            ),
            Matchup(
                id: "0004-0009",
                away: .init(id: "0004", name: "Chemical Bulldogs", abbreviation: "CB", score: 131.5, projectedScore: 131.5, playersRemaining: 0, accentSeed: 4, starters: demoStarters("0004", "CB", score: 131.5, remaining: 0), bench: demoBench("0004", "CB")),
                home: .init(id: "0009", name: "Pray For Mojo", abbreviation: "PFM", score: 119.2, projectedScore: 119.2, playersRemaining: 0, accentSeed: 9, starters: demoStarters("0009", "PFM", score: 119.2, remaining: 0), bench: demoBench("0009", "PFM")),
                isUserMatchup: false,
                status: .final
            ),
            Matchup(
                id: "0005-0010",
                away: .init(id: "0005", name: "Bears Sausage Ditka", abbreviation: "BSD", score: 88.9, projectedScore: 116.2, playersRemaining: 4, accentSeed: 5, starters: demoStarters("0005", "BSD", score: 88.9, remaining: 4), bench: demoBench("0005", "BSD")),
                home: .init(id: "0010", name: "360° Turnaround", abbreviation: "360", score: 92.1, projectedScore: 122.7, playersRemaining: 4, accentSeed: 10, starters: demoStarters("0010", "360", score: 92.1, remaining: 4), bench: demoBench("0010", "360")),
                isUserMatchup: false,
                status: .live("2nd · 2:13")
            ),
            Matchup(
                id: "0006-0012",
                away: .init(id: "0006", name: "Two Bad Neighbors", abbreviation: "BAB", score: 73.4, projectedScore: 110.4, playersRemaining: 5, accentSeed: 6, starters: demoStarters("0006", "BAB", score: 73.4, remaining: 5), bench: demoBench("0006", "BAB")),
                home: .init(id: "0012", name: "Bitchbettahavemymoney.com", abbreviation: "BBM", score: 84.6, projectedScore: 118.8, playersRemaining: 4, accentSeed: 12, starters: demoStarters("0012", "BBM", score: 84.6, remaining: 4), bench: demoBench("0012", "BBM")),
                isUserMatchup: false,
                status: .live("2nd · 11:06")
            )
        ],
        lastUpdated: now,
        isLive: true
    )

    static let lineupPlayers: [LineupPlayer] = [
        player("12620", "Dak Prescott", "QB", "DAL", "@ NYG", 22.4, 0, true, nil, 3),
        player("14073", "Josh Jacobs", "RB", "GB", "vs MIN", 18.7, 0, true, nil, 4),
        player("13319", "Aaron Jones", "RB", "MIN", "@ GB", 14.2, 0, true, .questionable, 4),
        player("15284", "Jaylen Waddle", "WR", "DEN", "vs KC", 16.8, 0, true, nil, 5),
        player("15761", "Khalil Shakir", "WR", "BUF", "vs NYJ", 13.1, 0, true, nil, 2),
        player("14842", "Michael Pittman Jr.", "WR", "PIT", "@ CLE", 12.9, 0, true, .questionable, 5),
        player("15889", "Chigoziem Okonkwo", "TE", "WAS", "vs PHI", 9.4, 0, true, nil, 2),
        player("16080", "Rashid Shaheed", "WR", "SEA", "@ LAR", 11.7, 0, true, nil, 3),
        player("14056", "Kyler Murray", "QB", "MIN", "@ GB", 20.6, 0, false, nil, 4),
        player("15256", "Javonte Williams", "RB", "DAL", "@ NYG", 11.2, 0, true, nil, 3),
        player("15757", "Wan'Dale Robinson", "WR", "TEN", "vs JAX", 10.5, 0, false, nil, 3),
        player("15712", "Tyler Allgeier", "RB", "ARI", "vs SF", 8.8, 0, false, nil, 6),
        player("16269", "Brenton Strange", "TE", "JAX", "@ TEN", 7.3, 0, false, nil, 3),
        player("16596", "Braelon Allen", "RB", "NYJ", "@ BUF", 7.9, 0, false, nil, 2),
        player("17047", "Dylan Sampson", "RB", "CLE", "vs PIT", 6.4, 0, false, nil, 5),
        player("17080", "Jaylin Noel", "WR", "HOU", "vs IND", 5.8, 0, false, nil, 1),
        player("14860", "Jauan Jennings", "WR", "MIN", "@ GB", 0, 0, false, .out, 4),
        player("16222", "Bench Reserve", "RB", "FA", "—", 0, 0, false, .injuredReserve, 7)
    ]

    static let lineup = LineupSnapshot(
        week: 1,
        players: lineupPlayers,
        requiredStarterCount: 9,
        positionRequirements: [
            .init(position: "QB", minimum: 1, maximum: 1),
            .init(position: "RB", minimum: 2, maximum: 4),
            .init(position: "WR", minimum: 3, maximum: 5),
            .init(position: "TE", minimum: 1, maximum: 3)
        ],
        requiredTiebreakerCount: 1,
        tiebreakerPlayerIDs: ["14056"],
        deadline: Calendar.current.date(byAdding: .hour, value: 5, to: now)!,
        lastSubmitted: Calendar.current.date(byAdding: .day, value: -1, to: now),
        serverStarterPlayerIDs: Set(lineupPlayers.filter(\.isStarter).map(\.id)),
        editState: .editable
    )

    static let waiverCandidates: [WaiverCandidate] = [
        .init(id: "w1", name: "Isaiah Bond", position: "WR", nflTeam: "CLE", rosteredPercent: 18, projectedPoints: 12.7, seasonPoints: 0, trend: 14, injuryStatus: nil),
        .init(id: "w2", name: "Bhayshul Tuten", position: "RB", nflTeam: "JAX", rosteredPercent: 36, projectedPoints: 10.9, seasonPoints: 0, trend: 9, injuryStatus: nil),
        .init(id: "w3", name: "Elijah Arroyo", position: "TE", nflTeam: "SEA", rosteredPercent: 12, projectedPoints: 8.8, seasonPoints: 0, trend: 7, injuryStatus: .questionable),
        .init(id: "w4", name: "Jalen Royals", position: "WR", nflTeam: "KC", rosteredPercent: 8, projectedPoints: 8.4, seasonPoints: 0, trend: 11, injuryStatus: nil),
        .init(id: "w5", name: "Kyle Monangai", position: "RB", nflTeam: "CHI", rosteredPercent: 6, projectedPoints: 7.6, seasonPoints: 0, trend: 5, injuryStatus: nil),
        .init(id: "w6", name: "Tyler Shough", position: "QB", nflTeam: "NO", rosteredPercent: 4, projectedPoints: 16.1, seasonPoints: 0, trend: 3, injuryStatus: nil)
    ]

    static let waivers = WaiverSnapshot(
        availableBudget: 95,
        increment: 1,
        maxRounds: 8,
        candidates: waiverCandidates,
        claims: [
            .init(
                player: waiverCandidates[0],
                bid: 14,
                dropPlayerID: "17080",
                dropPlayerName: "Jaylin Noel",
                round: 1,
                priority: 1
            ),
            .init(
                player: waiverCandidates[1],
                bid: 9,
                dropPlayerID: "17080",
                dropPlayerName: "Jaylin Noel",
                round: 1,
                priority: 2
            )
        ],
        processesAt: Calendar.current.nextDate(after: now, matching: DateComponents(hour: 3), matchingPolicy: .nextTime)!
    )

    static let standings: [StandingRow] = [
        standing("0011", 1, "The Mean Green", "TMG", "Faulk", 0, 0, 0, 0, 0, "—", false, 11),
        standing("0002", 2, "Croton Bug Eaters", "CBE", "Faulk", 0, 0, 0, 0, 0, "—", false, 2),
        standing("0007", 3, "Fields of Gold", "JPH", "Faulk", 0, 0, 0, 0, 0, "—", false, 7),
        standing("0003", 4, "Secret Asian Man", "SAM", "Faulk", 0, 0, 0, 0, 0, "—", false, 3),
        standing("0001", 5, "Uber Beasts", "UB", "Warner", 0, 0, 0, 0, 0, "—", true, 1),
        standing("0008", 6, "GPT 5.0 now available", "RU", "Warner", 0, 0, 0, 0, 0, "—", false, 8),
        standing("0006", 7, "Two Bad Neighbors", "BAB", "Warner", 0, 0, 0, 0, 0, "—", false, 6),
        standing("0005", 8, "Bears Sausage Ditka", "BSD", "Warner", 0, 0, 0, 0, 0, "—", false, 5),
        standing("0004", 9, "Chemical Bulldogs", "CB", "Bruce", 0, 0, 0, 0, 0, "—", false, 4),
        standing("0010", 10, "360° Turnaround", "360", "Bruce", 0, 0, 0, 0, 0, "—", false, 10),
        standing("0009", 11, "Pray For Mojo", "PFM", "Bruce", 0, 0, 0, 0, 0, "—", false, 9),
        standing("0012", 12, "Bitchbettahavemymoney.com", "BBM", "Bruce", 0, 0, 0, 0, 0, "—", false, 12)
    ]

    /// An explicit synthetic two-week scenario; normal Preview stays preseason.
    static var previewStandings: [StandingRow] {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--preview-ranked-standings") else { return standings }
        let noDivisions = ProcessInfo.processInfo.arguments.contains("--preview-no-divisions")
        var rows = standings.enumerated().map { index, original in
            var row = original
            row.wins = index < 3 ? 2 : index < 9 ? 1 : 0
            row.losses = 2 - row.wins
            row.pointsFor = Double(300 - index * 10)
            if index == 6 { row.pointsFor = 250 }
            if index == 3 { row.losses = 0; row.ties = 1 }
            if noDivisions { row.divisionID = nil }
            row.standingsRule = "PCT,PTS"
            row.overallRankIssue = nil; row.divisionRankIssue = nil
            return row
        }
        let source: [MFLStanding] = rows.compactMap { row in
            let payload = ["id": row.id, "h2hw": String(row.wins), "h2hl": String(row.losses),
                           "h2ht": String(row.ties), "pf": String(row.pointsFor)]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            return try? JSONDecoder().decode(MFLStanding.self, from: data)
        }
        let overall = MFLStandingsRanking.resolve(source, criteria: "PCT,PTS", hasResults: true)
        for index in rows.indices {
            rows[index].overallPlace = overall.places[rows[index].id]
            if let division = rows[index].divisionID {
                let ids = Set(rows.filter { $0.divisionID == division }.map(\.id))
                rows[index].divisionPlace = MFLStandingsRanking.resolve(source.filter { ids.contains($0.id) },
                    criteria: "PCT,PTS", hasResults: true).places[rows[index].id]
            }
        }
        return rows
        #else
        return standings
        #endif
    }

    static let board: [BoardThread] = [
        BoardThread(
            id: "t1",
            subject: "Week 1 is finally here",
            author: "The Mean Green",
            preview: "Good luck to everyone except the team playing me.",
            lastActivity: Calendar.current.date(byAdding: .minute, value: -18, to: now)!,
            replyCount: 7,
            isUnread: true,
            posts: [
                .init(id: "p1", author: "The Mean Green", body: "Good luck to everyone except the team playing me.", postedAt: Calendar.current.date(byAdding: .hour, value: -2, to: now)!, isUser: false),
                .init(id: "p2", author: "Uber Beasts", body: "Saving this for Sunday night.", postedAt: Calendar.current.date(byAdding: .minute, value: -18, to: now)!, isUser: true)
            ]
        ),
        BoardThread(
            id: "t2",
            subject: "Waivers process Wednesday at 3 AM",
            author: "Commissioner",
            preview: "Reminder: conditional bids are enabled. Check every round before submitting.",
            lastActivity: Calendar.current.date(byAdding: .hour, value: -4, to: now)!,
            replyCount: 2,
            isUnread: true,
            posts: [
                .init(id: "p3", author: "Commissioner", body: "Reminder: conditional bids are enabled. Check every round before submitting.", postedAt: Calendar.current.date(byAdding: .hour, value: -4, to: now)!, isUser: false)
            ]
        ),
        BoardThread(
            id: "t3",
            subject: "Keeper deadline recap",
            author: "Chemical Bulldogs",
            preview: "All twelve teams are in. Draft board is ready.",
            lastActivity: Calendar.current.date(byAdding: .day, value: -3, to: now)!,
            replyCount: 11,
            isUnread: false,
            posts: [
                .init(id: "p4", author: "Chemical Bulldogs", body: "All twelve teams are in. Draft board is ready.", postedAt: Calendar.current.date(byAdding: .day, value: -3, to: now)!, isUser: false)
            ]
        )
    ]

    private static func demoStarters(
        _ teamID: String,
        _ abbreviation: String,
        score: Double,
        remaining: Int,
        isPregame: Bool = false
    ) -> [MatchupPlayer] {
        let slots = [
            ("QB", "Quarterback", "DAL", 0.20),
            ("RB", "Running Back 1", "GB", 0.13),
            ("RB", "Running Back 2", "MIN", 0.11),
            ("WR", "Wide Receiver 1", "BUF", 0.14),
            ("WR", "Wide Receiver 2", "MIA", 0.12),
            ("WR", "Wide Receiver 3", "PIT", 0.10),
            ("TE", "Tight End", "JAX", 0.08),
            ("WR", "Flex Receiver", "SEA", 0.07),
            ("RB", "Flex Back", "NYJ", 0.05),
        ]

        return slots.enumerated().map { index, slot in
            let gameSecondsRemaining: Int
            if isPregame {
                gameSecondsRemaining = 3_600
            } else if index < remaining {
                gameSecondsRemaining = index.isMultiple(of: 2) ? 1_365 : 3_600
            } else {
                gameSecondsRemaining = 0
            }
            return MatchupPlayer(
                id: "\(teamID)-starter-\(index)",
                name: "\(abbreviation) \(slot.1)",
                position: slot.0,
                nflTeam: slot.2,
                livePoints: (score * slot.3 * 10).rounded() / 10,
                lineupStatus: .starter,
                gameSecondsRemaining: gameSecondsRemaining,
                statLine: gameSecondsRemaining > 0 && gameSecondsRemaining < 3_600
                    ? demoStatLine(for: slot.0)
                    : nil,
                lineupSlot: index >= 7 ? "FLEX" : slot.0
            )
        }
    }

    private static func demoBench(
        _ teamID: String,
        _ abbreviation: String,
        isPregame: Bool = false
    ) -> [MatchupPlayer] {
        [
            MatchupPlayer(
                id: "\(teamID)-bench-0",
                name: "\(abbreviation) Bench Quarterback",
                position: "QB",
                nflTeam: "ARI",
                livePoints: isPregame ? 0 : 14.2,
                lineupStatus: .bench,
                gameSecondsRemaining: isPregame ? 3_600 : 0,
                statLine: nil
            ),
            MatchupPlayer(
                id: "\(teamID)-bench-1",
                name: "\(abbreviation) Bench Runner",
                position: "RB",
                nflTeam: "CLE",
                livePoints: isPregame ? 0 : 6.8,
                lineupStatus: .bench,
                gameSecondsRemaining: isPregame ? 3_600 : 0,
                statLine: nil
            ),
        ]
    }

    private static func demoStatLine(for position: String) -> String {
        switch position {
        case "QB": "18/27, 214 yds, 2 TD"
        case "RB": "12 rush, 68 yds · 3 rec, 24 yds"
        case "WR": "6 rec, 82 yds"
        case "TE": "4 rec, 46 yds"
        default: "Live"
        }
    }

    private static func player(
        _ id: String,
        _ name: String,
        _ position: String,
        _ team: String,
        _ opponent: String,
        _ projection: Double,
        _ points: Double,
        _ starter: Bool,
        _ injury: InjuryStatus?,
        _ hoursUntilGame: Int
    ) -> LineupPlayer {
        LineupPlayer(
            id: id,
            name: name,
            position: position,
            nflTeam: team,
            opponent: opponent,
            projectedPoints: projection,
            seasonPoints: points,
            isStarter: starter,
            isLocked: false,
            injuryStatus: injury,
            gameTime: Calendar.current.date(byAdding: .hour, value: hoursUntilGame, to: now)!
        )
    }

    private static func standing(
        _ id: String,
        _ rank: Int,
        _ name: String,
        _ abbreviation: String,
        _ division: String,
        _ wins: Int,
        _ losses: Int,
        _ ties: Int,
        _ pointsFor: Double,
        _ pointsAgainst: Double,
        _ streak: String,
        _ isUser: Bool,
        _ accentSeed: Int
    ) -> StandingRow {
        StandingRow(id: id, name: name, abbreviation: abbreviation, division: division, wins: wins, losses: losses, ties: ties, pointsFor: pointsFor, pointsAgainst: pointsAgainst, streak: streak, isUser: isUser, accentSeed: accentSeed, ownerName: "Demo Owner \(accentSeed)", divisionID: division, standingsRule: "PCT,H2H,PTS,DIVPCT", overallRankIssue: .awaitingResults, divisionRankIssue: .awaitingResults)
    }
}

actor DemoLeagueRepository: LeagueRepository {
    var demoTrades = SampleData.tradePreview
    var demoWatched: Set<String> = []
    var demoMembership: [String: String]?
    func signIn(with credentials: LoginCredentials) async throws -> LeagueWorkspace {
        try await shortDelay()
        guard !credentials.username.isEmpty, !credentials.password.isEmpty else {
            throw RepositoryError.invalidCredentials
        }
        return SampleData.workspace
    }

    func loadWorkspace() async throws -> LeagueWorkspace { SampleData.workspace }

    func loadScores(week: Int) async throws -> ScoresSnapshot {
        try await shortDelay()
        var value = SampleData.scores
        value.week = week
        value.lastUpdated = Date()
        return value
    }

    func loadLineup(week: Int) async throws -> LineupSnapshot {
        try await shortDelay()
        var value = SampleData.lineup
        value.week = week
        if let demoMembership {
            value.players = value.players.filter { demoMembership[$0.id] != nil }.map { original in
                var player = original
                if demoMembership[player.id] == "INJURED_RESERVE" { player.injuryStatus = .injuredReserve; player.isStarter = false }
                else if player.injuryStatus == .injuredReserve { player.injuryStatus = nil }
                return player
            }
            for candidate in SampleData.waivers.candidates where demoMembership[candidate.id] == "ROSTER" && !value.players.contains(where: { $0.id == candidate.id }) {
                value.players.append(LineupPlayer(id: candidate.id, name: candidate.name, position: candidate.position,
                    nflTeam: candidate.nflTeam, opponent: "", projectedPoints: candidate.projectedPoints,
                    seasonPoints: 0, isStarter: false, isLocked: false, gameTime: .distantFuture))
            }
        }
        return value
    }

    func submitLineup(_ lineup: LineupSnapshot) async throws { try await shortDelay() }
    func loadWaivers() async throws -> WaiverSnapshot {
        try await shortDelay()
        var value = SampleData.waivers
        if let demoMembership { value.candidates.removeAll { demoMembership[$0.id] != nil } }
        return value
    }
    func submitWaivers(_ claims: [WaiverClaim], replacing baseline: [WaiverClaim]) async throws { try await shortDelay() }
    func loadStandings() async throws -> [StandingRow] { try await shortDelay(); return SampleData.previewStandings }
    func loadBoard() async throws -> [BoardThread] { try await shortDelay(); return SampleData.board }
    func loadThread(id: String) async throws -> BoardThread {
        try await shortDelay()
        guard let thread = SampleData.board.first(where: { $0.id == id }) else {
            throw RepositoryError.server("That message-board thread is no longer available.")
        }
        return thread
    }
    func postMessage(subject: String?, body: String, threadID: String?) async throws { try await shortDelay() }
    func signOut() async {}

    private func shortDelay() async throws {
        try await Task.sleep(for: .milliseconds(350))
    }
}
