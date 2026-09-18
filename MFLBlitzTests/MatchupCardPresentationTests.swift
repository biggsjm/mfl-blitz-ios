import Foundation
import Testing
@testable import MFLBlitz

struct MatchupCardPresentationTests {
    private let now = ISO8601DateFormatter().date(from: "2026-12-18T18:00:00Z")!
    private let saturday = ISO8601DateFormatter().date(from: "2026-12-19T18:15:00Z")!
    private let sunday = ISO8601DateFormatter().date(from: "2026-12-20T18:00:00Z")!

    private func team(_ id: String, nfl: String, seconds: Int = 3600) -> MatchupTeam {
        .init(id: id, name: id, abbreviation: id, score: 5, projectedScore: 100, playersRemaining: 1,
            accentSeed: 1, starters: [.init(id: id, name: id, position: "WR", nflTeam: nfl,
                livePoints: 5, lineupStatus: .starter, gameSecondsRemaining: seconds)])
    }

    private func group(_ team: MatchupTeam, games: NFLScoringSnapshot?, week: Int = 16) -> MatchupModeTeam {
        .init(team: team, week: week, scope: "league", feed: nil, availability: nil, scoringGames: games, now: now)
    }

    @Test func nextStarterUsesScoringScheduleWithoutVisitingLineupOrPlayerDetails() {
        var away = team("a", nfl: "DAL")
        away.bench = team("bench", nfl: "BUF").starters
        let home = team("h", nfl: "DET")
        let match = Matchup(id: "m", away: away, home: home, isUserMatchup: true, status: .pregame(nil))
        let games = NFLScoringSnapshot(scope: "league", week: 16, games: [
            "DAL": .init(opponent: "NYG", isHome: true, kickoff: sunday),
            "DET": .init(opponent: "CHI", isHome: false, kickoff: saturday),
            "BUF": .init(opponent: "NE", isHome: false, kickoff: now.addingTimeInterval(3600))
        ], checkedAt: now)
        #expect(ScoringGamePresentation.cardFooter(for: match, stale: false,
            away: group(away, games: games), home: group(home, games: games), now: now) == .nextGame(saturday))
        #expect(group(home, games: games, week: 15).nextKickoff == nil, "Never use another week's schedule")
        let otherScope = NFLScoringSnapshot(scope: "other", week: 16, games: games.games, checkedAt: now)
        #expect(group(home, games: otherScope).nextKickoff == nil)
    }

    @Test func oldKickoffCannotHideTheNextScheduledGame() {
        let away = team("a", nfl: "DAL"), home = team("h", nfl: "DET")
        let match = Matchup(id: "m", away: away, home: home, isUserMatchup: true, status: .pregame(nil))
        let games = NFLScoringSnapshot(scope: "league", week: 16, games: [
            "DAL": .init(opponent: "NYG", isHome: true, kickoff: now.addingTimeInterval(-3600)),
            "DET": .init(opponent: "CHI", isHome: false, kickoff: sunday)
        ], checkedAt: now)
        #expect(ScoringGamePresentation.cardFooter(for: match, stale: false,
            away: group(away, games: games), home: group(home, games: games), now: now) == .nextGame(sunday))
    }

    @Test func activeFinalStaleAndMissingDataDoNotAdvertiseAnInventedNextGame() {
        var match = Matchup(id: "m", away: team("a", nfl: "DAL", seconds: 0),
            home: team("h", nfl: "DET"), isUserMatchup: false, status: .pregame(nil))
        func footer(stale: Bool = false) -> ScoringGamePresentation.CardFooter? {
            ScoringGamePresentation.cardFooter(for: match, stale: stale, away: nil, home: nil, now: now)
        }
        #expect(footer() == nil, "No Between games filler when no schedule is known")
        match.status = .pregame(saturday)
        #expect(footer() == .nextGame(saturday))
        #expect(footer(stale: true) == nil)
        match.status = .live("Live")
        #expect(footer() == .status("Live", live: true))
        match.status = .final
        #expect(footer() == .status("Final", live: false))
    }

    @Test func newerActivityUsesItsOwnScheduleAndActiveCount() {
        let match = Matchup(id: "m", away: team("a", nfl: "DAL"), home: team("h", nfl: "DET"),
            isUserMatchup: true, status: .live("Between games"))
        var activity = MatchupActivityAttributes.ContentState(homeScore: "10", awayScore: "5", activePlayers: 0, updatedAt: now)
        activity.nextKickoff = saturday
        func footer() -> ScoringGamePresentation.CardFooter? {
            ScoringGamePresentation.cardFooter(for: match, stale: false, away: nil, home: nil, activity: activity, now: now)
        }
        #expect(footer() == .nextGame(saturday))
        activity.activePlayers = 1
        #expect(footer() == .status("Live", live: true))
        activity.activePlayers = 0; activity.nextKickoff = now.addingTimeInterval(-1)
        #expect(footer() == nil)
    }
}
