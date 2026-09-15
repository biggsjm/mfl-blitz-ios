import Foundation
import Testing
@testable import MFLBlitz

@MainActor struct ScoringPresentationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func snapshot(points: Double? = 10, time: TimeInterval = 0, week: Int = 1) -> ScoresSnapshot {
        var value = SampleData.scores
        value.week = week
        value.checkedAt = now.addingTimeInterval(time)
        value.lastUpdated = value.checkedAt!
        value.matchups = [value.matchups[0]]
        value.matchups[0].away.starters[0].livePoints = points
        value.matchups[0].away.starters[0].gameSecondsRemaining = 1800
        return value
    }

    @Test func independentFreshness() {
        let value = snapshot()
        #expect(ScoreFreshness(snapshot: value, now: now).state == .fresh)
        #expect(ScoreFreshness(snapshot: value, refreshing: true, now: now).state == .refreshing)
        #expect(ScoreFreshness(snapshot: value, failed: true, now: now).state == .delayed)
        #expect(ScoreFreshness(snapshot: value, offline: true, now: now).state == .offline)
        #expect(ScoreFreshness(snapshot: value, saved: true, now: now).state == .saved)
        #expect(ScoreFreshness(snapshot: value, now: now.addingTimeInterval(209)).state == .fresh)
        #expect(ScoreFreshness(snapshot: value, now: now.addingTimeInterval(210)).state == .delayed)
        #expect(ScoreFreshness(snapshot: value, failed: true, now: now).qualifiesGameState)
        #expect(ScoringGamePresentation.label(for: value.matchups[0], stale: true) == "Last known: Live")
        #expect(value.matchups[0].status.isLive)
    }

    @Test func timestampsNeverInventFreshness() throws {
        var value = snapshot()
        value.checkedAt = nil
        #expect(ScoreFreshness(snapshot: value, now: now).state == .saved)
        value.matchups = []
        #expect(ScoreFreshness(snapshot: value, now: now).state == .loading)
        value.checkedAt = now.addingTimeInterval(60)
        #expect(ScoreFreshness(snapshot: value, now: now).checkedAt == nil)
        #expect(ScoreFreshness.age(now.addingTimeInterval(-78), now: now) == "1 min ago")
        #expect(ScoreFreshness.age(now.addingTimeInterval(-4), now: now) == "just now")
        let legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot())) as! [String: Any]
        var withoutReceipt = legacy; withoutReceipt.removeValue(forKey: "checkedAt")
        let decoded = try JSONDecoder().decode(ScoresSnapshot.self, from: JSONSerialization.data(withJSONObject: withoutReceipt))
        #expect(decoded.checkedAt == nil)
    }

    @Test func changesOnlyFromObservedChecks() {
        let tracker = ScoringChangeTracker()
        tracker.observe(snapshot(), scope: "a", now: now)
        #expect(tracker.events.isEmpty)
        tracker.observe(snapshot(points: 12.4, time: 95), scope: "a", now: now.addingTimeInterval(95))
        #expect(tracker.events.count == 1)
        #expect(tracker.events[0].signedText == "+2.4")
        tracker.observe(snapshot(points: 12.4, time: 190), scope: "a", now: now.addingTimeInterval(190))
        #expect(tracker.events.count == 1, "A successful check isn't a scoring event")
        #expect(tracker.change(for: tracker.events[0].key, now: now.addingTimeInterval(155)) == nil)
        #expect(tracker.recent(now: now.addingTimeInterval(396)).isEmpty)
    }

    @Test func correctionsZerosAndPrecision() {
        let tracker = ScoringChangeTracker()
        tracker.observe(snapshot(points: 0), scope: "a", now: now)
        tracker.observe(snapshot(points: -0.2, time: 10), scope: "a", now: now.addingTimeInterval(10))
        #expect(tracker.events.first?.signedText == "−0.2")
        tracker.observe(snapshot(points: -0.201, time: 20), scope: "a", now: now.addingTimeInterval(20))
        #expect(tracker.events.count == 1)
        var final = snapshot(points: 0, time: 30)
        final.matchups[0].status = .final
        tracker.observe(final, scope: "a", now: now.addingTimeInterval(30))
        #expect(tracker.events.first?.signedText == "+0.2")
    }

    @Test func missingIsNotZeroOrAChange() {
        let tracker = ScoringChangeTracker()
        for (index, points) in [10.0, nil, 0, .nan, 3].enumerated() {
            tracker.observe(snapshot(points: points, time: Double(index) * 10), scope: "a", now: now.addingTimeInterval(Double(index) * 10))
        }
        #expect(tracker.events.isEmpty)
        var team = snapshot().matchups[0].away
        team.hasReportedScore = false
        #expect(team.reportedScore == nil)
        team.hasReportedScore = true; team.score = 0
        #expect(team.reportedScore == 0)
    }

    @Test func scopeRecoveryAndOutOfOrder() {
        let tracker = ScoringChangeTracker()
        tracker.observe(snapshot(), scope: "a", now: now)
        tracker.observe(snapshot(points: 20, time: 300), scope: "a", now: now.addingTimeInterval(300))
        #expect(tracker.events.isEmpty)
        tracker.observe(snapshot(points: 21, time: 301), scope: "a", now: now.addingTimeInterval(301))
        #expect(tracker.events.count == 1)
        tracker.observe(snapshot(points: 100, time: 250), scope: "a", now: now.addingTimeInterval(302))
        #expect(tracker.events.count == 1)
        tracker.invalidate()
        tracker.observe(snapshot(points: 22, time: 303), scope: "a", now: now.addingTimeInterval(303))
        #expect(tracker.events.isEmpty)
        tracker.observe(snapshot(points: 50, time: 304, week: 2), scope: "a", now: now.addingTimeInterval(304))
        #expect(tracker.events.isEmpty)
        tracker.observe(snapshot(points: 60, time: 305, week: 2), scope: "b", now: now.addingTimeInterval(305))
        #expect(tracker.events.isEmpty)
    }

    @Test func boundedHistory() {
        let tracker = ScoringChangeTracker()
        for index in 0..<40 {
            tracker.observe(snapshot(points: Double(index), time: Double(index)), scope: "a", now: now.addingTimeInterval(Double(index)))
        }
        #expect(tracker.events.count == 20)
    }

    @Test func pregameAndFinalPlayerNavigation() {
        var player = snapshot().matchups[0].away.starters[0]
        func info() -> MatchupGameInfo { MatchupGameInfo(player: player, availability: nil, scope: "a", week: 1) }
        #expect(PlayerScoringContext.isEligible(player, game: info()))
        player.gameSecondsRemaining = 3600
        #expect(!PlayerScoringContext.isEligible(player, game: info()))
        #expect(ScoringGamePresentation.actualPoints(player) == nil)
        player.gameSecondsRemaining = 0
        #expect(PlayerScoringContext.isEligible(player, game: info()))
        let bye = PlayerAvailabilitySnapshot(scope: "a", week: 1, byeWeeks: [player.nflTeam: 1])
        #expect(!PlayerScoringContext.isEligible(player, game: MatchupGameInfo(player: player, availability: bye, scope: "a", week: 1)))
        player.gameSecondsRemaining = nil
        #expect(!PlayerScoringContext.isEligible(player, game: info()))
    }

    @Test func benchTotalsRequireReportedBenchPoints() {
        var team = snapshot().matchups[0].away
        let officialScore = team.score
        for index in team.bench.indices { team.bench[index].livePoints = 0 }
        #expect(ScoringGamePresentation.benchPoints(for: team) == 0)
        team.bench[0].livePoints = 12.4
        team.bench[1].livePoints = -0.4
        #expect(ScoringGamePresentation.benchPoints(for: team) == 12)
        #expect(team.score == officialScore)
        team.starters[0].livePoints = 1_000
        #expect(ScoringGamePresentation.benchPoints(for: team) == 12, "Only bench players contribute")
        team.bench[1].livePoints = nil
        #expect(ScoringGamePresentation.benchPoints(for: team) == nil)
        team.bench[1].livePoints = .nan
        #expect(ScoringGamePresentation.benchPoints(for: team) == nil)
        team.bench[1].livePoints = 0
        team.unclassifiedPlayers = [team.starters[0]]
        #expect(ScoringGamePresentation.benchPoints(for: team) == nil)
        team.unclassifiedPlayers = []
        team.bench.append(team.bench[0])
        #expect(ScoringGamePresentation.benchPoints(for: team) == nil)
        team.bench = []
        #expect(ScoringGamePresentation.benchPoints(for: team) == nil)
    }

    @Test func betweenGamesAndMargins() {
        var match = snapshot().matchups[0]
        match.status = .pregame(nil)
        match.away.starters[0].gameSecondsRemaining = 0
        match.home.starters[0].gameSecondsRemaining = 3600
        #expect(ScoringGamePresentation.label(for: match, stale: false) == "Between games")
        match.away.score = 10; match.home.score = 12
        #expect(ScoringGamePresentation.margin(match, franchiseID: match.away.id, precision: 1) == "Trailing by 2.0 points")
        match.status = .final
        #expect(ScoringGamePresentation.margin(match, franchiseID: match.home.id, precision: 1) == "Won by 2.0 points")
        match.home.hasReportedScore = false
        #expect(ScoringGamePresentation.margin(match, franchiseID: match.home.id, precision: 1) == nil)
        #expect(match.leaderID == nil)
        match.status = .pregame(nil)
        match.away.clearDisplayClocks(); match.home.clearDisplayClocks()
        #expect(ScoringGamePresentation.label(for: match, stale: false) == "Status unavailable")
    }

    @Test func liveEstimateKeepsOfficialPointsAndOnlyAddsRemainingProjection() {
        var match = snapshot().matchups[0]
        match.away.score = 22
        match.away.playersRemaining = 2
        match.away.starters = Array(match.away.starters.prefix(3))
        // A finished player needs no projection; a halftime player has half of
        // their original expectation remaining; an upcoming player has all of it.
        match.away.starters[0].gameSecondsRemaining = 0
        match.away.starters[0].projectedPoints = nil
        match.away.starters[1].gameSecondsRemaining = 1800
        match.away.starters[1].projectedPoints = 12
        match.away.starters[2].gameSecondsRemaining = 3600
        match.away.starters[2].projectedPoints = 20
        match.away.bench[0].projectedPoints = 500
        func estimate() -> ScoringGamePresentation.Projection {
            ScoringGamePresentation.projection(for: match.away, in: match, stale: false)
        }
        #expect(estimate().points == 48)
        #expect(estimate().isLiveEstimate)
        match.away.score = 20 // A correction stays in the official total.
        #expect(estimate().points == 46)
        match.away.starters[1].gameSecondsRemaining = 900
        #expect(estimate().points == 43)
        match.away.starters[1].gameSecondsRemaining = 0
        match.away.starters[2].gameSecondsRemaining = 0
        match.away.playersRemaining = 0
        #expect(estimate().points == 20)
        match.status = .final
        #expect(!estimate().isVisible)
    }

    @Test func liveEstimateRejectsIncompleteAmbiguousOrStaleInputs() {
        let base = snapshot().matchups[0]
        #expect(ScoringGamePresentation.projection(for: base.away, in: base, stale: false).points != nil)
        #expect(ScoringGamePresentation.projection(for: base.away, in: base, stale: true).points == nil)
        for invalid in 0..<9 {
            var team = base.away
            switch invalid {
            case 0: team.starters[0].projectedPoints = nil
            case 1: team.starters[0].projectedPoints = .infinity
            case 2: team.starters[0].gameSecondsRemaining = nil
            case 3: team.starters[0].gameSecondsRemaining = -1
            case 4: team.hasReportedScore = false
            case 5: team.starters.append(team.starters[0])
            case 6: team.unclassifiedPlayers = [team.bench.removeFirst()]
            case 7: team.playersRemaining += 1
            default: team.starters = []
            }
            #expect(ScoringGamePresentation.projection(for: team, in: base, stale: false).points == nil)
        }
    }

    @Test func projectionsKeepPregameSourceAndWaitBetweenGames() {
        var match = snapshot().matchups[0]
        match.status = .pregame(nil)
        for index in match.away.starters.indices { match.away.starters[index].gameSecondsRemaining = 3600 }
        for index in match.home.starters.indices { match.home.starters[index].gameSecondsRemaining = 3600 }
        var result = ScoringGamePresentation.projection(for: match.away, in: match, stale: false)
        #expect(!result.isLiveEstimate)
        #expect(result.points == match.away.projectedScore)
        match.away.playersRemaining = match.away.starters.count - 1
        match.away.starters[0].gameSecondsRemaining = 0
        result = ScoringGamePresentation.projection(for: match.away, in: match, stale: false)
        #expect(result.isLiveEstimate)
        #expect(result.points != nil)
    }
}
