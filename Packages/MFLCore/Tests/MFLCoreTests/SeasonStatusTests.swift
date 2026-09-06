import Foundation
import Testing
@testable import MFLCore

struct SeasonStatusTests {
    @Test("MFL current and lineup weeks can differ and never use number grouping")
    func weeks() throws {
        let status = try JSONDecoder().decode(MFLSeasonStatus.self, from: Data(#"{"mfl_status":{"year":"2026","weeks":{"CurrentWeek":"1","LineupWeek":"2","CompletedWeek":"0","LiveScoringWeek":"1"}}}"#.utf8))
        #expect(status.currentWeek == 1)
        #expect(status.lineupWeek == 2)
        #expect(status.year == 2026)
        #expect(status.completedWeek == 0)
    }

    @Test("Incomplete or out-of-range week data is rejected")
    func invalidWeeks() {
        for fixture in [#"{"mfl_status":{"year":"2026","weeks":{"CurrentWeek":"2"}}}"#,
                        #"{"mfl_status":{"year":"2026","weeks":{"CurrentWeek":"99","LineupWeek":"2","CompletedWeek":"1","LiveScoringWeek":"2"}}}"#] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(MFLSeasonStatus.self, from: Data(fixture.utf8))
            }
        }
    }

    @Test("Unknown pending waiver envelopes do not silently decode as no saved bids")
    func unknownQueue() {
        for fixture in [#"{"pendingWaivers":{"unexpected":[{"player":"123"}]}}"#,
                        #"{"pendingWaivers":{"waiverRequest":["malformed"]}}"#] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(MFLPendingWaiversResponse.self, from: Data(fixture.utf8))
            }
        }
    }
}
