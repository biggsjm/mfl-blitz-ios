import Foundation
import Testing
@testable import MFLCore

struct ProjectionTests {
    @Test("The blank placeholder observed in the live Week 1 feed does not discard valid projections")
    func liveFeedPlaceholder() throws {
        let url = try #require(Bundle.module.url(forResource: "projected-scores-placeholder", withExtension: "json"))
        let result = try JSONDecoder().decode(MFLProjectedScoresResponse.self,
            from: Data(contentsOf: url))
        #expect(result.projectedScores.week == 1)
        #expect(result.projectedScores.players.count == 2)
        #expect(result.projectedScores.scoresByPlayerID["13589"] == Decimal(string: "34.8"))
        #expect(result.projectedScores.scoresByPlayerID["test-player"] == 0)
        #expect(result.projectedScores.scoresByPlayerID[""] == nil)
    }

    @Test("Anonymous projection placeholders are omitted, but identified missing scores still protect against duplicates")
    func anonymousRows() throws {
        let data = Data(#"{"projectedScores":{"week":"1","playerScore":[{"score":""},{"id":null,"score":""},{"id":"  ","score":""},{"id":"001","score":"4.0"},{"id":"001","score":""},{"id":"002","score":"7.5"}]}}"#.utf8)
        let result = try JSONDecoder().decode(MFLProjectedScoresResponse.self, from: data)
        #expect(result.projectedScores.players.count == 3)
        #expect(result.projectedScores.scoresByPlayerID == ["002": Decimal(string: "7.5")!])
        let single = try JSONDecoder().decode(MFLProjectedScoresResponse.self,
            from: Data(#"{"projectedScores":{"week":1,"playerScore":{"id":"","score":""}}}"#.utf8))
        #expect(single.projectedScores.players.isEmpty)
    }

    @Test("Projection zeroes, missing values, duplicates and singleton payloads stay distinct")
    func projectionDecoding() throws {
        let values = try JSONDecoder().decode(MFLProjectedScoresResponse.self, from: Data(#"{"projectedScores":{"week":"1","playerScore":[{"id":"001","score":"12.25"},{"id":"002","score":0},{"id":"003"},{"id":"004","score":"N/A"},{"id":"005","score":"4"},{"id":"005","score":"5"}]}}"#.utf8))
        #expect(values.projectedScores.week == 1)
        #expect(values.projectedScores.scoresByPlayerID == ["001": Decimal(string: "12.25")!, "002": 0])
        let single = try JSONDecoder().decode(MFLProjectedScoresResponse.self, from: Data(#"{"projectedScores":{"week":1,"playerScore":{"id":"001","score":"-1.25"}}}"#.utf8))
        #expect(single.projectedScores.scoresByPlayerID["001"] == Decimal(string: "-1.25"))
    }
}
