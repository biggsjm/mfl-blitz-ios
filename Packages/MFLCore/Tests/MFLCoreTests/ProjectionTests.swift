import Foundation
import Testing
@testable import MFLCore

struct ProjectionTests {
    @Test("Projection zeroes, missing values, duplicates and singleton payloads stay distinct")
    func projectionDecoding() throws {
        let values = try JSONDecoder().decode(MFLProjectedScoresResponse.self, from: Data(#"{"projectedScores":{"week":"1","playerScore":[{"id":"001","score":"12.25"},{"id":"002","score":0},{"id":"003"},{"id":"004","score":"N/A"},{"id":"005","score":"4"},{"id":"005","score":"5"}]}}"#.utf8))
        #expect(values.projectedScores.week == 1)
        #expect(values.projectedScores.scoresByPlayerID == ["001": Decimal(string: "12.25")!, "002": 0])
        let single = try JSONDecoder().decode(MFLProjectedScoresResponse.self, from: Data(#"{"projectedScores":{"week":1,"playerScore":{"id":"001","score":"-1.25"}}}"#.utf8))
        #expect(single.projectedScores.scoresByPlayerID["001"] == Decimal(string: "-1.25"))
    }
}
