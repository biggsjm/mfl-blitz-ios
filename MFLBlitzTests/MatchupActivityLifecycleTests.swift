import Foundation
import Testing
@testable import MFLBlitz

struct MatchupActivityLifecycleTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot() -> ScoresSnapshot {
        var scores = SampleData.scores
        scores.matchups = [scores.matchups[0]]
        scores.checkedAt = now; scores.lastUpdated = now
        return scores
    }

    private func eligible(_ scores: ScoresSnapshot) -> Matchup? {
        MatchupActivityPolicy.matchup(in: scores, workspace: SampleData.workspace, currentWeek: scores.week, now: now)
    }

    private func current(_ scores: ScoresSnapshot) -> Matchup? {
        MatchupActivityPolicy.currentMatchup(in: scores, workspace: SampleData.workspace, currentWeek: scores.week, now: now)
    }

    private func finish(_ team: inout MatchupTeam) {
        for index in team.starters.indices { team.starters[index].gameSecondsRemaining = 0 }
        team.playersRemaining = 0
    }

    @Test func gapsBetweenGamesRetainButDoNotStartAnActivity() throws {
        var scores = snapshot()
        #expect(eligible(scores) != nil)
        finish(&scores.matchups[0].away); finish(&scores.matchups[0].home)
        scores.matchups[0].home.starters[0].gameSecondsRemaining = 3600
        scores.matchups[0].home.playersRemaining = 1
        scores.matchups[0].status = .pregame(nil)
        #expect(eligible(scores) == nil)
        let retained = try #require(current(scores))
        #expect(MatchupActivityPolicy.phase(in: retained) == "waiting")
        scores.matchups[0].home.starters[0].gameSecondsRemaining = 3500
        #expect(eligible(scores) != nil)
        #expect(MatchupActivityPolicy.phase(in: scores.matchups[0]) == "live")
    }

    @Test func unavailableClocksOrPlayersAreNotAFinalResult() throws {
        var scores = snapshot()
        scores.matchups[0].away.clearDisplayClocks()
        scores.matchups[0].home.clearDisplayClocks()
        #expect(eligible(scores) == nil)
        #expect(current(scores) != nil)
        #expect(MatchupActivityPolicy.phase(in: scores.matchups[0]) == nil)
        scores.matchups[0].away.starters = []
        scores.matchups[0].home.starters = []
        #expect(MatchupActivityPolicy.phase(in: scores.matchups[0]) == nil)
        scores.matchups[0].home.hasReportedScore = false
        #expect(current(scores) == nil)
        scores.matchups = []
        #expect(current(scores) == nil)
    }

    @Test func finalRequiresAllStartersAndConsistentRemainingCounts() {
        var scores = snapshot()
        finish(&scores.matchups[0].away); finish(&scores.matchups[0].home)
        scores.matchups[0].status = .final
        let complete = scores.matchups[0]
        #expect(MatchupActivityPolicy.phase(in: complete) == "final")
        #expect(eligible(scores) == nil)
        for invalid in 0..<5 {
            var match = complete
            switch invalid {
            case 0: match.home.starters[0].gameSecondsRemaining = nil
            case 1: match.home.playersRemaining = 1
            case 2: match.home.starters.append(match.home.starters[0])
            case 3: match.home.unclassifiedPlayers = [match.home.bench.removeFirst()]
            default: match.home.starters[0].lineupStatus = .unknown
            }
            #expect(MatchupActivityPolicy.phase(in: match) == nil)
        }
    }

    @Test func staleWrongWeekAndAmbiguousReadsCannotReplaceCurrentActivity() {
        var scores = snapshot()
        scores.checkedAt = now.addingTimeInterval(-211)
        #expect(current(scores) == nil)
        scores = snapshot(); scores.matchups.append(scores.matchups[0])
        #expect(current(scores) == nil)
        scores = snapshot()
        #expect(MatchupActivityPolicy.currentMatchup(in: scores, workspace: SampleData.workspace,
            currentWeek: scores.week + 1, now: now) == nil)
    }

    @Test func automaticEndWaitsForTwoCompleteFreshFinalReads() {
        var matchup = snapshot().matchups[0]
        var check = MatchupActivityFinalCheck()
        #expect(check.phase(for: matchup, checkedAt: now) == "live")
        finish(&matchup.home); finish(&matchup.away)
        #expect(check.phase(for: matchup, checkedAt: now.addingTimeInterval(90)) == "waiting")
        #expect(check.phase(for: matchup, checkedAt: now.addingTimeInterval(100)) == "waiting")
        #expect(check.phase(for: matchup, checkedAt: now.addingTimeInterval(180)) == "final")
    }

    @Test func partialFinalAndStaleConfirmationCannotEnd() {
        var matchup = snapshot().matchups[0]
        var check = MatchupActivityFinalCheck()
        _ = check.phase(for: matchup, checkedAt: now)
        finish(&matchup.home); finish(&matchup.away)
        var partial = matchup; partial.home.starters.removeLast()
        for offset: Double in [90, 180] {
            #expect(check.phase(for: partial, checkedAt: now.addingTimeInterval(offset)) == "waiting")
        }
        #expect(check.phase(for: matchup, checkedAt: now.addingTimeInterval(270)) == "waiting")
        #expect(check.phase(for: matchup, checkedAt: now.addingTimeInterval(500)) == "waiting")
    }

    @Test func responseOrderingDoesNotReplaceTheSameActivity() {
        let matchup = snapshot().matchups[0]
        var attributes = MatchupActivityAttributes(scope: "league", week: 1,
            matchupID: "\(matchup.home.id)-\(matchup.away.id)", homeName: "H", awayName: "A", homeAbbreviation: "H", awayAbbreviation: "A")
        #expect(MatchupActivityPolicy.matches(attributes, matchup: matchup, scope: "league", week: 1))
        attributes.homeID = matchup.home.id; attributes.awayID = matchup.away.id
        attributes.matchupID = "provider-changed-id"
        #expect(MatchupActivityPolicy.matches(attributes, matchup: matchup, scope: "league", week: 1))
        #expect(!MatchupActivityPolicy.matches(attributes, matchup: matchup, scope: "other", week: 1))
        #expect(!MatchupActivityPolicy.matches(attributes, matchup: matchup, scope: "league", week: 2))
        attributes.homeID = "other-team"
        #expect(!MatchupActivityPolicy.matches(attributes, matchup: matchup, scope: "league", week: 1))
    }

    @MainActor @Test func lifecycleHistorySurvivesRelaunchAndStaysBounded() throws {
        let suite = "activity-history-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MatchupActivityController(defaults: defaults)
        for index in 0..<40 { controller.recordLifecycle("Event \(index)", date: now.addingTimeInterval(Double(index))) }
        let reopened = MatchupActivityController(defaults: defaults)
        #expect(reopened.lifecycleHistory.count == 30)
        #expect(reopened.lifecycleHistory.first?.message == "Event 10")
        #expect(reopened.lifecycleHistory.last?.message == "Event 39")
    }
}
