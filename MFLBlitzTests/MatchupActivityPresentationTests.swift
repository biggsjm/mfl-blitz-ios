import Foundation
import Testing
import UIKit
@testable import MFLBlitz

struct MatchupActivityPresentationTests {
    @Test func relaunchAndFailedArtworkReadPreserveTheDeliveredPaletteAndLogo() throws {
        let art = MatchupActivityAttributes.Artwork(imageData: Data("logo".utf8), red: 0.7, green: 0.1, blue: 0.2)
        let old = MatchupActivityAttributes.ContentState(homeScore: "3.0", awayScore: "4.0", activePlayers: 2,
            updatedAt: .now, homeArtwork: art, awayArtwork: art)
        var fresh = MatchupActivityAttributes.ContentState(homeScore: "9.0", awayScore: "4.0", activePlayers: 2,
            updatedAt: old.updatedAt.addingTimeInterval(90), homeProjection: "110.3")
        fresh = fresh.preservingArtwork(from: old)
        let decoded = try JSONDecoder().decode(MatchupActivityAttributes.ContentState.self, from: JSONEncoder().encode(fresh))
        #expect(decoded.homeArtwork == art && decoded.awayArtwork == art)
        #expect(decoded.homeScore == "9.0" && decoded.homeProjection == "110.3")
        fresh.homeArtwork?.imageData = nil
        #expect(fresh.preservingArtwork(from: decoded).homeArtwork == art)
        fresh.homeArtwork?.red = 0.2
        #expect(fresh.preservingArtwork(from: decoded).homeArtwork?.imageData == nil)
        #expect(fresh.preservingArtwork(from: nil).awayArtwork == art)
    }

    @Test func activityUsesLiveEstimatesAndSuppressesStaleAndFinalValues() {
        var state = MatchupActivityAttributes.ContentState(homeScore: "3.0", awayScore: "4.0", activePlayers: 2,
            updatedAt: .now, homeProjection: "110.3", homeRecord: "0–0", awayRecord: "1–0", phase: "live")
        #expect(state.projectionLabel(home: true, isStale: false) == "Live est. 110.3")
        #expect(state.projectionLabel(home: false, isStale: false) == "Live est. —")
        #expect(state.projectionLabel(home: true, isStale: true) == "Live est. —")
        state.phase = "final"
        #expect(state.projectionLabel(home: true, isStale: false) == nil)
    }

    @Test func newerPushWithoutArtworkKeepsPreparedLogoAndItsOwnScores() {
        var prepared = MatchupActivityAttributes.ContentState(homeScore: "3.0", awayScore: "4.0", activePlayers: 2,
            updatedAt: .now, homeArtwork: .init(imageData: Data("logo".utf8), red: 0.7, green: 0.1, blue: 0.2))
        let delivered = MatchupActivityAttributes.ContentState(homeScore: "9.0", awayScore: "10.0", activePlayers: 3,
            updatedAt: prepared.updatedAt.addingTimeInterval(90), homeProjection: "101.2")
        prepared = prepared.reconciling(with: delivered)
        #expect(prepared.homeScore == "9.0" && prepared.awayScore == "10.0")
        #expect(prepared.homeProjection == "101.2" && prepared.updatedAt == delivered.updatedAt)
        #expect(prepared.homeArtwork?.imageData == Data("logo".utf8))
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func game() -> Matchup {
        var match = SampleData.scores.matchups[0]
        match.away.score = 20; match.home.score = 30
        match.away.abbreviation = "UB"; match.home.abbreviation = "BSD"
        for index in match.away.starters.indices { match.away.starters[index].livePoints = 0 }
        for index in match.home.starters.indices { match.home.starters[index].livePoints = 0 }
        match.away.starters[0].name = "Dak Prescott"
        return match
    }
    private func observe(_ game: Matchup, _ tracker: inout MatchupActivityChangeTracker, after seconds: Double,
                         scope: String = "a", week: Int = 1, precision: Int = 1) {
        tracker.observe(game, scope: scope, week: week, checkedAt: now.addingTimeInterval(seconds),
                        precision: precision, now: now.addingTimeInterval(seconds))
    }

    @Test func firstReadIsBaselineAndUnchangedChecksKeepTheLastChangeTime() {
        var tracker = MatchupActivityChangeTracker(), match = game()
        observe(match, &tracker, after: 0); #expect(tracker.latest == nil)
        match.away.score += 3; match.away.starters[0].livePoints = 3
        observe(match, &tracker, after: 90)
        #expect(tracker.latest?.text == "Dak Prescott +3.0 pts · UB")
        observe(match, &tracker, after: 180)
        #expect(tracker.latest?.checkedAt == now.addingTimeInterval(90))
    }

    @Test func batchesNeverInventPlayerOrdering() {
        var tracker = MatchupActivityChangeTracker(), match = game()
        observe(match, &tracker, after: 0)
        match.away.score += 4; match.away.starters[0].livePoints = 3; match.away.starters[1].livePoints = 1
        observe(match, &tracker, after: 90)
        #expect(tracker.latest?.text == "2 starters +4.0 pts · UB")
        match.away.score += 1; match.away.starters[0].livePoints = 4
        match.home.score += 2; match.home.starters[0].livePoints = 2
        observe(match, &tracker, after: 180)
        #expect(tracker.latest?.text == "UB +1.0 pts · BSD +2.0 pts")
    }

    @Test func benchAndUnreconciledPlayerChangesAreNotCredited() {
        var tracker = MatchupActivityChangeTracker(), match = game()
        observe(match, &tracker, after: 0)
        match.away.bench[0].livePoints = 100
        observe(match, &tracker, after: 30); #expect(tracker.latest == nil)
        match.away.score += 3; match.away.starters[0].livePoints = 1
        observe(match, &tracker, after: 90)
        #expect(tracker.latest?.text == "UB +3.0 pts")
    }

    @Test func missingPlayersOrLineupChangesUseOnlyOfficialTeamDeltas() {
        for variant in 0..<4 {
            var tracker = MatchupActivityChangeTracker(), match = game()
            observe(match, &tracker, after: 0)
            match.away.score += 3; match.away.starters[0].livePoints = 3
            switch variant {
            case 0: match.away.starters[1].livePoints = nil
            case 1: match.away.starters.removeLast()
            case 2: match.away.starters.append(match.away.starters[0])
            default: match.away.unclassifiedPlayers = [match.away.bench[0]]
            }
            observe(match, &tracker, after: 90)
            #expect(tracker.latest?.text == "UB +3.0 pts")
        }
    }

    @Test func correctionsAndDisplayPrecision() {
        var tracker = MatchupActivityChangeTracker(), match = game()
        observe(match, &tracker, after: 0)
        match.away.score -= 0.2; match.away.starters[0].livePoints = -0.2
        observe(match, &tracker, after: 90)
        #expect(tracker.latest?.text == "Dak Prescott −0.2 pts · UB")
        match.away.score -= 0.001; match.away.starters[0].livePoints = -0.201
        observe(match, &tracker, after: 100)
        #expect(tracker.latest?.checkedAt == now.addingTimeInterval(90))
        observe(match, &tracker, after: 110, precision: 3)
        #expect(tracker.latest == nil)
    }

    @Test func gapsScopeChangesAndFailuresResetAttribution() {
        for variant in 0..<4 {
            var tracker = MatchupActivityChangeTracker(), match = game()
            observe(match, &tracker, after: 0)
            match.away.score += 3; match.away.starters[0].livePoints = 3
            switch variant {
            case 0: observe(match, &tracker, after: 210)
            case 1: observe(match, &tracker, after: 90, scope: "b")
            case 2: observe(match, &tracker, after: 90, week: 2)
            default: tracker.reset(); observe(match, &tracker, after: 90)
            }
            #expect(tracker.latest == nil)
        }
    }

    @Test func duplicateOutOfOrderAndStaleReadsDoNotInventChanges() {
        var tracker = MatchupActivityChangeTracker(), match = game()
        observe(match, &tracker, after: 0)
        match.away.score += 3; match.away.starters[0].livePoints = 3
        observe(match, &tracker, after: 90)
        observe(game(), &tracker, after: 90)
        observe(game(), &tracker, after: 60)
        #expect(tracker.latest?.text == "Dak Prescott +3.0 pts · UB")
        tracker.observe(match, scope: "a", week: 1, checkedAt: now, precision: 1, now: now.addingTimeInterval(211))
        #expect(tracker.latest == nil)
    }

    @Test func missingTeamTotalDoesNotCompareAgainstZero() {
        var tracker = MatchupActivityChangeTracker(), match = game()
        match.away.hasReportedScore = false
        observe(match, &tracker, after: 0)
        match.away.hasReportedScore = true
        observe(match, &tracker, after: 90)
        #expect(tracker.latest == nil)
    }

    @Test func legacyPayloadDecodesAndArtworkKeepsPayloadSmall() throws {
        let legacy = Data(#"{"homeScore":"3.0","awayScore":"0.0","activePlayers":8,"updatedAt":0,"homeProjection":"120.0"}"#.utf8)
        var state = try JSONDecoder().decode(MatchupActivityAttributes.ContentState.self, from: legacy)
        #expect(state.latestChange == nil && state.homeArtwork == nil && state.homeRecord == nil)
        state.latestChange = .init(text: String(repeating: "W", count: 160), checkedAt: now)
        state.homeRecord = "10–2–1"; state.awayRecord = "9–3–1"
        // 0xff exposes the slash-escaping expansion missed by all-zero fixtures.
        let art = MatchupActivityAttributes.Artwork(imageData: Data(repeating: 255, count: 900), red: 0.1, green: 0.4, blue: 0.5)
        state.homeArtwork = art; state.awayArtwork = art
        let attrs = MatchupActivityAttributes(scope: String(repeating: "a", count: 150), week: 1, matchupID: "0001-0008",
            homeName: String(repeating: "W", count: 80), awayName: String(repeating: "W", count: 80),
            homeAbbreviation: "BSD", awayAbbreviation: "UB")
        #expect(try JSONEncoder().encode(state).count + JSONEncoder().encode(attrs).count < 4_096)
        let compact = state.fittingActivityBudget(attributes: attrs)
        #expect(compact.homeArtwork?.imageData == art.imageData && compact.awayArtwork?.imageData == art.imageData)
        let decoded = try JSONDecoder().decode(MatchupActivityAttributes.ContentState.self, from: JSONEncoder().encode(compact))
        #expect(decoded.homeArtwork?.imageData == art.imageData && decoded.awayArtwork?.imageData == art.imageData)
        let legacyArt = Data(#"{"imageData":"/w==","red":0.1,"green":0.4,"blue":0.5}"#.utf8)
        #expect(try JSONDecoder().decode(MatchupActivityAttributes.Artwork.self, from: legacyArt).imageData == Data([255]))
        state.homeArtwork?.imageData = Data(repeating: 1, count: 3_000)
        let fitted = state.fittingActivityBudget(attributes: attrs)
        #expect(fitted.homeArtwork?.imageData == nil && fitted.awayArtwork?.imageData == nil)
        #expect(fitted.homeArtwork?.red == art.red && fitted.latestChange == state.latestChange)
    }

    @Test func DetailedArtworkBecomesDecodableBoundedThumbnails() throws {
        var seed: UInt32 = 17
        var bytes = [UInt8](repeating: 255, count: 96 * 96 * 4)
        for i in bytes.indices where i % 4 != 3 {
            seed = 1_664_525 &* seed &+ 1_013_904_223
            bytes[i] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: 96, height: 96, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 96 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let artwork = try #require(MatchupActivityArtworkStore.makeArtwork(from: image))
        let data = try #require(artwork.imageData)
        #expect(data.count <= MatchupActivityArtworkStore.maximumLogoBytes)
        let decodedImage = try #require(UIImage(data: data)?.cgImage)
        #expect(decodedImage.width >= 36 && decodedImage.height >= 36)
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(artwork.red) + 0.7152 * linear(artwork.green) + 0.0722 * linear(artwork.blue)
        #expect(1.05 / (luminance + 0.05) >= 5)
    }
}
