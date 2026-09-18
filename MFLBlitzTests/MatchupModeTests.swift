import Foundation
import SwiftUI
import Testing
@testable import MFLBlitz

struct MatchupModeTests {
    private func feed(status: String, kickoff: Double? = nil) -> NFLWeekFeed {
        var result = NFLFeedPreview.make(); let old = result.games[0]
        result.games[0] = NFLFeedGame(id: old.id, season: old.season, week: old.week,
            kickoff: kickoff ?? old.kickoff, status: status, timer: old.timer, home: old.home, away: old.away,
            homeScore: old.homeScore, awayScore: old.awayScore, checkedAt: old.checkedAt, stale: false,
            players: old.players, statsCheckedAt: old.statsCheckedAt, statsStale: false)
        return result
    }
    private func player(_ id: String, _ team: String, _ seconds: Int?, _ points: Double?) -> MatchupPlayer {
        .init(id: id, name: "Player \(id)", position: "RB", nflTeam: team, livePoints: points,
              lineupStatus: .starter, gameSecondsRemaining: seconds, statLine: nil, projectedPoints: 20)
    }
    private func team(_ players: [MatchupPlayer], score: Double = 15) -> MatchupTeam {
        .init(id: "0001", name: "Test", abbreviation: "T", score: score, projectedScore: 80,
              playersRemaining: 2, accentSeed: 1, starters: players)
    }
    @Test func groupsRealGameStatesAndKeepsBenchOutsideTotals() {
        var value = team([player("done", "JAC", 0, 10), player("live", "DAL", 0, 5), player("later", "BUF", 3600, 0)])
        value.bench = [player("bench", "DAL", 1200, 100)]
        let result = MatchupModeTeam(team: value, week: 1, scope: "one", feed: NFLFeedPreview.make(), availability: nil)
        #expect(result.entries(in: .completed).map(\.id) == ["done"])
        #expect(result.entries(in: .inProgress).map(\.id) == ["live"])
        #expect(result.entries(in: .upcoming).map(\.id) == ["later"])
        #expect(result.starterTotal == 15); #expect(result.difference == 0)
        #expect(result.entries.count == 3)
    }
    @Test(arguments: ["HT", "OT", "BT", "Q4"])
    func breaksAndOvertimeDoNotFinishAPlayer(status: String) {
        let feed = feed(status: status)
        let result = MatchupModeTeam(team: team([player("one", "DAL", 0, 5)]), week: 1, scope: nil, feed: feed, availability: nil)
        #expect(result.entries[0].section == .inProgress)
    }
    @Test(arguments: ["PST", "CANC", "TBD"])
    func exceptionalStatesCannotBecomeFinished(status: String) {
        let feed = feed(status: status)
        let result = MatchupModeTeam(team: team([player("one", "DAL", 0, 5)]), week: 1, scope: nil, feed: feed, availability: nil)
        #expect(result.entries[0].section == .unavailable)
    }
    @Test func missingPointsAndCorrectionsNeverManufactureTotals() {
        var value = team([player("one", "DAL", 1000, nil), player("two", "JAC", 0, 10)])
        let missing = MatchupModeTeam(team: value, week: 1, scope: nil, feed: nil, availability: nil)
        #expect(missing.starterTotal == nil); #expect(missing.difference == nil)
        #expect(missing.points(in: .inProgress) == nil); #expect(missing.points(in: .completed) == 10)
        value.starters[0].livePoints = -2
        let corrected = MatchupModeTeam(team: value, week: 1, scope: nil, feed: nil, availability: nil)
        #expect(corrected.starterTotal == 8); #expect(corrected.difference == 7)
        #expect(corrected.entries[0].player.projectedPoints == 20)
    }
    @Test func byeUnknownAndDuplicatePlayersRemainExplicit() {
        var availability = PlayerAvailabilitySnapshot(scope: "one", week: 1)
        availability.byeWeeks["BUF"] = 1
        let value = team([player("bye", "BUF", 0, 0), player("unknown", "XXX", nil, nil), player("dup", "DAL", 200, 4), player("dup", "DAL", 200, 5)])
        let result = MatchupModeTeam(team: value, week: 1, scope: "one", feed: nil, availability: availability)
        #expect(result.entries(in: .unavailable).count == 3)
        #expect(result.entries.first?.state == "Bye week"); #expect(result.starterTotal == nil)
    }
    @Test func clockAloneDoesNotMovePregamePlayers() {
        let feed = feed(status: "NS", kickoff: Date().timeIntervalSince1970 - 300)
        let result = MatchupModeTeam(team: team([player("one", "DAL", 3600, 0)]), week: 1, scope: nil, feed: feed, availability: nil)
        #expect(result.entries[0].section == .upcoming)
    }
    @Test func activePlayersRemainVisibleWhileNFLProviderWaitsForKickoff() {
        let value = team([player("active", "DAL", 3249, 3), player("later", "BUF", 3600, 0)], score: 3)
        let result = MatchupModeTeam(team: value, week: 1, scope: "one", feed: feed(status: "NS"), availability: nil)
        #expect(result.entries(in: .inProgress).map(\.id) == ["active"])
        #expect(result.entries(in: .upcoming).map(\.id) == ["later"])
        #expect(result.entries(in: .inProgress).first?.state == "Live")
        #expect(result.points(in: .inProgress) == 3 && result.difference == 0)
    }
    @Test func tiedRegulationWithoutVerifiedFinalStaysUnclassified() {
        let now = Date()
        let games = NFLScoringSnapshot(scope: "one", week: 1,
            games: ["DAL": NFLGameContext(opponent: "NYG", isHome: false,
                kickoff: now.addingTimeInterval(-7200), score: 24, opponentScore: 24,
                gameSecondsRemaining: 0)], checkedAt: now)
        let result = MatchupModeTeam(team: team([player("one", "DAL", 0, 5)]), week: 1,
            scope: "one", feed: nil, availability: nil, scoringGames: games, now: now)
        #expect(result.entries[0].section == .unavailable)
        #expect(result.points(in: .completed) == 0)
    }
    @Test func nflGameClockOverridesALaggingPlayerClock() {
        let now = Date()
        let games = NFLScoringSnapshot(scope: "one", week: 1,
            games: ["MIN": NFLGameContext(opponent: "CHI", isHome: false,
                kickoff: now.addingTimeInterval(-3600), score: 24, opponentScore: 17,
                gameSecondsRemaining: 1500)], checkedAt: now)
        let result = MatchupModeTeam(team: team([player("one", "MIN", 0, 5)]), week: 1,
            scope: "one", feed: nil, availability: nil, scoringGames: games, now: now)
        #expect(result.entries[0].section == .inProgress)
        #expect(result.points(in: .completed) == 0)
    }
    @Test func weeklyContextResolvesConsistentlyAndRejectsConflicts() {
        let id = PlayerIdentity(id: "one", name: "Player one", position: "RB", nflTeam: "DAL")
        let value = team([player("one", "DAL", 1000, 5)])
        var scores = ScoresSnapshot(week: 1, matchups: [.init(id: "m", away: value, home: team([]), isUserMatchup: true, status: .live("Live"))], lastUpdated: Date(), isLive: true, checkedAt: Date())
        let context = PlayerScoringContext.resolve(identity: id, week: 1, scores: scores, availability: nil, scope: nil, nflGame: nil)
        #expect(context?.player.livePoints == 5); #expect(context?.week == 1)
        #expect(PlayerScoringContext.resolve(identity: id, week: 2, scores: scores, availability: nil, scope: nil, nflGame: nil) == nil)
        scores.matchups[0].home.starters = [player("one", "DAL", 1000, 9)]
        #expect(PlayerScoringContext.resolve(identity: id, week: 1, scores: scores, availability: nil, scope: nil, nflGame: NFLFeedPreview.make().games[0])?.player.livePoints == nil)
    }
    @Test func freeAgentCanHaveAnNFLBoxWithoutInventedFantasyPoints() {
        let context = PlayerScoringContext.resolve(identity: .init(id: "free", name: "Free", position: "QB", nflTeam: "DAL"),
            week: 1, scores: nil, availability: nil, scope: nil, nflGame: NFLFeedPreview.make().games[0])
        #expect(context != nil); #expect(context?.player.livePoints == nil); #expect(context?.checkedAt == nil)
    }
    @Test func groupedTimelineExplainsOneTeamDeltaWithoutAddingItTwice() {
        func event(_ id: String, _ kind: String, _ value: Double) -> MatchupTimelineEvent {
            .init(id: id, at: 500, kind: kind, name: id, teamID: "one", playerID: kind == "player" ? id : nil, previous: 0, current: value, source: "app")
        }
        let events = [event("team", "team", 8), event("one", "player", 3), event("two", "player", 5), event("gap", "gap", 0)]
        let result = MatchupTimelineUpdate.grouped(events + [events[0]])
        #expect(result.count == 1); #expect(result[0].delta == 8); #expect(result[0].players.count == 2)
    }
    @MainActor @Test func confirmedQuietPeriodsSuppressGapsButUnknownIntervalsDoNot() {
        let finalTeam = team([player("one", "DAL", 0, 5)])
        var matchup = Matchup(id: "m", away: finalTeam, home: team([]), isUserMatchup: true, status: .final)
        #expect(!MatchupTimelineStore.needsGap(previous: matchup, current: matchup, at: Date()))
        matchup.status = .live("Live")
        #expect(MatchupTimelineStore.needsGap(previous: matchup, current: matchup, at: Date()))
        let kickoff = Date().addingTimeInterval(3600)
        matchup.status = .pregame(kickoff); matchup.away.starters[0].gameSecondsRemaining = 3600
        #expect(!MatchupTimelineStore.needsGap(previous: matchup, current: matchup, at: Date()))
        #expect(MatchupTimelineStore.needsGap(previous: matchup, current: matchup, at: kickoff.addingTimeInterval(60)))
    }
    @Test func lineupReadinessSeparatesAvailabilityFromFilledSlots() {
        var lineup = SampleData.lineup
        let first = lineup.starters[0]
        var data = PlayerAvailabilitySnapshot(scope: "one", week: lineup.week)
        data.injuryUpdatedAt = Date(); data.injuries[first.id] = .init(status: "Out")
        let out = LineupReadiness(lineup: lineup, availability: data, scope: "one")
        #expect(out.issues.contains { $0.playerID == first.id && $0.urgent }); #expect(out.attentionCount >= 1)
        data.injuries[first.id] = .init(status: "Questionable")
        #expect(LineupReadiness(lineup: lineup, availability: data, scope: "one").issues.first?.urgent == false)
        data.injuryUpdatedAt = nil
        #expect(LineupReadiness(lineup: lineup, availability: data, scope: "one").availabilityUnknown)
        lineup.players.removeAll { $0.id == first.id }
        #expect(LineupReadiness(lineup: lineup, availability: nil, scope: "one").emptySlots > 0)
    }
    @MainActor @Test func actionTintHasReadableContrastAndActivityLabelsIncludeCounts() {
        let color = UIColor(Color.blitzAction).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ v: CGFloat) -> Double { v <= 0.04045 ? Double(v / 12.92) : pow(Double((v + 0.055) / 1.055), 2.4) }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        #expect(1.05 / (luminance + 0.05) >= 4.5)
        var state = MatchupActivityAttributes.ContentState(homeScore: "12", awayScore: "9", activePlayers: 2, updatedAt: Date())
        state.homePlaying = 1; state.homeYetToPlay = 3
        #expect(state.teamAccessibilityLabel(name: "Home", home: true, isStale: false).contains("1 playing · 3 yet to play"))
        #expect(state.teamAccessibilityLabel(name: "Home", home: true, isStale: true).contains("scores delayed"))
        #expect(!state.teamAccessibilityLabel(name: "Home", home: true, isStale: true).contains("playing"))
    }
}
