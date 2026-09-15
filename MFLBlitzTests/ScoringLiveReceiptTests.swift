import Foundation
import Testing
@testable import MFLBlitz

@MainActor struct ScoringLiveReceiptTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func newerActivitySuppliesOnlyTheHeader() throws {
        var scores = SampleData.scores
        scores.checkedAt = now.addingTimeInterval(-120)
        let match = scores.matchups[0]
        let state = MatchupActivityAttributes.ContentState(homeScore: "130.2", awayScore: "141.0", activePlayers: 3,
            updatedAt: now, homeProjection: "150.2", awayProjection: "161.0", phase: "live")
        let receipt = try #require(ScoringLiveReceipt(matchup: match, snapshot: scores, state: state, now: now))
        #expect(receipt.matchup.home.reportedScore == 130.2)
        #expect(receipt.matchup.away.reportedScore == 141)
        #expect(receipt.projection(home: true, stale: false).points == 150.2)
        #expect(receipt.projection(home: false, stale: true).points == nil)
        #expect(receipt.matchup.away.players == match.away.players)
        #expect(scores.checkedAt == now.addingTimeInterval(-120))
        #expect(receipt.snapshot.checkedAt == now)
        scores.checkedAt = now
        scores.matchups[0].home.score = 129 // MFL correction wins at same/newer receipt.
        #expect(ScoringLiveReceipt(matchup: scores.matchups[0], snapshot: scores, state: state, now: now) == nil)
    }

    @Test func invalidMissingAndFutureContentCannotReplaceScores() {
        var scores = SampleData.scores; scores.checkedAt = now.addingTimeInterval(-120)
        for value in ["—", "NaN", "inf", ""] {
            let state = MatchupActivityAttributes.ContentState(homeScore: value, awayScore: "0", activePlayers: 1, updatedAt: now)
            #expect(ScoringLiveReceipt(matchup: scores.matchups[0], snapshot: scores, state: state, now: now) == nil)
        }
        let future = MatchupActivityAttributes.ContentState(homeScore: "1", awayScore: "0", activePlayers: 1, updatedAt: now.addingTimeInterval(60))
        #expect(ScoringLiveReceipt(matchup: scores.matchups[0], snapshot: scores, state: future, now: now) == nil)
        #expect(ScoringLiveReceipt(matchup: scores.matchups[0], snapshot: scores, state: nil, now: now) == nil)
    }

    @Test func coldPreviewRequiresExactIdentityAndDoesNotInventPlayers() throws {
        let attributes = MatchupActivityAttributes(scope: "league", week: 1, matchupID: "a-b", homeName: "Home", awayName: "Away",
            homeAbbreviation: "H", awayAbbreviation: "A", homeID: "b", awayID: "a")
        let state = MatchupActivityAttributes.ContentState(homeScore: "20", awayScore: "30", activePlayers: 3, updatedAt: now)
        let preview = try #require(ScoringLiveReceipt.preview(attributes: attributes, state: state, scope: "league", week: 1, matchupID: "a-b", now: now))
        #expect(preview.checkedAt == nil && preview.matchups[0].home.starters.isEmpty)
        #expect(preview.matchups[0].home.id == "b" && preview.matchups[0].away.reportedScore == 30)
        #expect(ScoringLiveReceipt.preview(attributes: attributes, state: state, scope: "other", week: 1, matchupID: "a-b", now: now) == nil)
        #expect(ScoringLiveReceipt.preview(attributes: attributes, state: state, scope: "league", week: 2, matchupID: "a-b", now: now) == nil)
        #expect(ScoringLiveReceipt.preview(attributes: attributes, state: state, scope: "league", week: 1, matchupID: "b-a", now: now) == nil)
    }

    @Test func finalKeepsCorrectionsAndHidesEstimates() throws {
        var scores = SampleData.scores; scores.checkedAt = now.addingTimeInterval(-120)
        let state = MatchupActivityAttributes.ContentState(homeScore: "-0.5", awayScore: "0", activePlayers: 0,
            updatedAt: now, homeProjection: "NaN", phase: "final")
        let receipt = try #require(ScoringLiveReceipt(matchup: scores.matchups[0], snapshot: scores, state: state, now: now))
        #expect(receipt.matchup.home.reportedScore == -0.5 && receipt.matchup.away.reportedScore == 0)
        #expect(receipt.matchup.status == .final)
        #expect(!receipt.projection(home: true, stale: false).isVisible)
    }
}
