import Foundation

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
                away: .init(id: "0001", name: "Uber Beasts", abbreviation: "UB", score: 112.7, projectedScore: 128.4, playersRemaining: 3, accentSeed: 1),
                home: .init(id: "0008", name: "GPT 5.0 now available", abbreviation: "RU", score: 108.2, projectedScore: 121.9, playersRemaining: 2, accentSeed: 8),
                isUserMatchup: true,
                status: .live("3rd · 8:42")
            ),
            Matchup(
                id: "0002-0011",
                away: .init(id: "0002", name: "Croton Bug Eaters", abbreviation: "CBE", score: 96.4, projectedScore: 119.1, playersRemaining: 4, accentSeed: 2),
                home: .init(id: "0011", name: "The Mean Green", abbreviation: "TMG", score: 101.8, projectedScore: 124.3, playersRemaining: 3, accentSeed: 11),
                isUserMatchup: false,
                status: .live("Halftime")
            ),
            Matchup(
                id: "0003-0007",
                away: .init(id: "0003", name: "Secret Asian Man", abbreviation: "SAM", score: 0, projectedScore: 117.6, playersRemaining: 9, accentSeed: 3),
                home: .init(id: "0007", name: "Fields of Gold", abbreviation: "JPH", score: 0, projectedScore: 125.8, playersRemaining: 9, accentSeed: 7),
                isUserMatchup: false,
                status: .pregame(Calendar.current.date(byAdding: .hour, value: 3, to: now)!)
            ),
            Matchup(
                id: "0004-0009",
                away: .init(id: "0004", name: "Chemical Bulldogs", abbreviation: "CB", score: 131.5, projectedScore: 131.5, playersRemaining: 0, accentSeed: 4),
                home: .init(id: "0009", name: "Pray For Mojo", abbreviation: "PFM", score: 119.2, projectedScore: 119.2, playersRemaining: 0, accentSeed: 9),
                isUserMatchup: false,
                status: .final
            ),
            Matchup(
                id: "0005-0010",
                away: .init(id: "0005", name: "Bears Sausage Ditka", abbreviation: "BSD", score: 88.9, projectedScore: 116.2, playersRemaining: 4, accentSeed: 5),
                home: .init(id: "0010", name: "360° Turnaround", abbreviation: "360", score: 92.1, projectedScore: 122.7, playersRemaining: 4, accentSeed: 10),
                isUserMatchup: false,
                status: .live("2nd · 2:13")
            ),
            Matchup(
                id: "0006-0012",
                away: .init(id: "0006", name: "Two Bad Neighbors", abbreviation: "BAB", score: 73.4, projectedScore: 110.4, playersRemaining: 5, accentSeed: 6),
                home: .init(id: "0012", name: "Bitchbettahavemymoney.com", abbreviation: "BBM", score: 84.6, projectedScore: 118.8, playersRemaining: 4, accentSeed: 12),
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
        lastSubmitted: Calendar.current.date(byAdding: .day, value: -1, to: now)
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
        StandingRow(id: id, rank: rank, name: name, abbreviation: abbreviation, division: division, wins: wins, losses: losses, ties: ties, pointsFor: pointsFor, pointsAgainst: pointsAgainst, streak: streak, isUser: isUser, accentSeed: accentSeed)
    }
}

actor DemoLeagueRepository: LeagueRepository {
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
        return value
    }

    func submitLineup(_ lineup: LineupSnapshot) async throws { try await shortDelay() }
    func loadWaivers() async throws -> WaiverSnapshot { try await shortDelay(); return SampleData.waivers }
    func submitWaivers(_ claims: [WaiverClaim]) async throws { try await shortDelay() }
    func loadStandings() async throws -> [StandingRow] { try await shortDelay(); return SampleData.standings }
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
