import SwiftUI
import XCTest
import Vision
@testable import MFLBlitz

final class MatchupActivityLayoutTests: XCTestCase {
    @MainActor func testNativeCardFitsLockScreenWithLogosAndLatestChange() throws {
        for width: CGFloat in [343, 408] {
            for scheme: ColorScheme in [.light, .dark] {
                try capture(width: width, scheme: scheme, stale: false, longNames: false)
            }
        }
    }

    @MainActor func testNextKickoffAndContinuationFit() throws {
        try capture(width:343,scheme:.light,stale:false,longNames:false,waiting:true)
        try capture(width:343,scheme:.dark,stale:false,longNames:false,continuation:true)
    }
    @MainActor func testLargeScoresLongNamesAndStaleFallbackFit() throws {
        try capture(width: 343, scheme: .dark, stale: false, longNames: true)
        try capture(width: 343, scheme: .light, stale: true, longNames: true)
    }

    @MainActor func testShortAndUnevenScoresStayCenteredOverTeamNames() throws {
        for width: CGFloat in [343, 408] {
            for pair in [("3.0", "3.0"), ("0.0", "112.7")] {
                try capture(width: width, scheme: .light, stale: false, longNames: false,
                            awayScore: pair.0, homeScore: pair.1)
            }
        }
    }

    @MainActor private func capture(width: CGFloat, scheme: ColorScheme, stale: Bool, longNames: Bool,
                                    awayScore: String? = nil, homeScore: String? = nil, waiting: Bool = false, continuation: Bool = false) throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let attributes = MatchupActivityAttributes(scope: "synthetic", week: 1, matchupID: "0001-0008",
            homeName: longNames ? String(repeating: "Long team name ", count: 5) : "Bears Sausage Ditka",
            awayName: "Uber Beasts", homeAbbreviation: "0005", awayAbbreviation: "UB")
        let awayArt = try XCTUnwrap(MatchupActivityArtworkStore.makeArtwork(from: XCTUnwrap(logo("UB", color: .systemRed).cgImage)))
        let homeArt = try XCTUnwrap(MatchupActivityArtworkStore.makeArtwork(from: XCTUnwrap(logo("BD", color: .systemBlue).cgImage)))
        var state = MatchupActivityAttributes.ContentState(homeScore: homeScore ?? (longNames ? "199.875" : "108.2"),
            awayScore: awayScore ?? (longNames ? "−99.125" : "112.7"), activePlayers: 8, updatedAt: date,
            homeProjection: "131.4", awayProjection: "128.6",
            homeRecord: "0–0", awayRecord: "0–0",
            latestChange: .init(text: longNames ? "Kenneth Walker III +12.125 pts · BSD" : "Brenton Strange +6.0 pts · UB", checkedAt: date),
            homeArtwork: homeArt, awayArtwork: awayArt)
        state.homePlaying=3;state.awayPlaying=5;state.homeYetToPlay=2;state.awayYetToPlay=1
        state.statContext="2 rec · 23 rec yd · 1 rec TD"
        if waiting { state.phase="waiting";state.nextKickoff=date.addingTimeInterval(3600);state.homePlaying=0;state.awayPlaying=0 }
        state.continuationNeeded=continuation
        // Exercise the real size guard and encoder/decoder, not injected images.
        let payload = try JSONEncoder().encode(state.fittingActivityBudget(attributes: attributes))
        let decoded = try JSONDecoder().decode(MatchupActivityAttributes.ContentState.self, from: payload)
        XCTAssertNotNil(MatchupActivityScoreboard.image(decoded.awayArtwork))
        XCTAssertNotNil(MatchupActivityScoreboard.image(decoded.homeArtwork))
        XCTAssertEqual(attributes.homeDisplayAbbreviation, longNames ? "LTNL" : "BSD")
        let view = MatchupActivityScoreboard(attributes: attributes, state: decoded, isStale: stale)
            .frame(width: width).environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, longNames ? .accessibility5 : .large)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertLessThanOrEqual(image.size.height, 160, "Lock Screen content must fit Apple's compact activity height")
        XCTAssertEqual(image.size.width, width)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Live Activity \(Int(width)) \(scheme) \(stale ? "stale" : "live") \(longNames ? "long" : "normal") \(state.awayScore)-\(state.homeScore)".replacingOccurrences(of: ".", with: "_")
        attachment.lifetime = .keepAlways; add(attachment)
        if !stale {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let results = request.results ?? []
            let recognized = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            XCTAssertTrue(recognized.contains("131.4") && recognized.contains("128.6"), "Both live estimates must render: \(recognized)")
            XCTAssertFalse(recognized.contains("0–0"), "Legacy records must not render")
            if longNames {
                XCTAssertTrue(recognized.contains("99.125"), "The actual away score must render in full: \(recognized)")
                XCTAssertTrue(recognized.contains("199.875"), "The actual home score must render in full: \(recognized)")
            } else if awayScore != nil {
                func box(for text: String, isAway: Bool) throws -> CGRect {
                    for result in results {
                        guard let candidate = result.topCandidates(1).first else { continue }
                        var start = candidate.string.startIndex
                        while let range = candidate.string.range(of: text, range: start..<candidate.string.endIndex) {
                            if let box = try candidate.boundingBox(for: range)?.boundingBox,
                               (box.midX < 0.5) == isAway { return box }
                            start = range.upperBound
                        }
                    }
                    XCTFail("Missing rendered text \(text) in: \(recognized)")
                    throw NSError(domain: "ActivityLayout", code: 1)
                }
                for (name, score, isAway) in [("Uber Beasts", state.awayScore, true), ("Bears Sausage Ditka", state.homeScore, false)] {
                    // Vision sometimes treats a large 0.0 as artwork. Measure the
                    // white score glyphs directly, independent of digit recognition.
                    let number = try scoreBounds(in: image, isAway: isAway)
                    let identity = try box(for: name, isAway: isAway)
                    XCTAssertEqual(number.midX * width, identity.midX * width, accuracy: 3,
                                   "\(score) must be centered over its team name regardless of digit count")
                }
            }
        }
    }

    @MainActor private func scoreBounds(in image: UIImage, isAway: Bool) throws -> CGRect {
        let source = try XCTUnwrap(image.cgImage)
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let columns = isAway ? 0..<Int(Double(width) * 0.44) : Int(Double(width) * 0.56)..<width
        var minimum = width, maximum = -1
        for y in Int(Double(height) * 0.21)..<Int(Double(height) * 0.48) {
            for x in columns {
                let offset = (y * width + x) * 4
                if pixels[offset] > 235 && pixels[offset + 1] > 235 && pixels[offset + 2] > 235 {
                    minimum = min(minimum, x); maximum = max(maximum, x)
                }
            }
        }
        XCTAssertGreaterThan(maximum, minimum, "A complete visible score should occupy the score region")
        return CGRect(x: Double(minimum) / Double(width), y: 0, width: Double(maximum - minimum) / Double(width), height: 0)
    }

    @MainActor private func logo(_ text: String, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        return renderer.image { _ in
            color.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 64, height: 64), cornerRadius: 14).fill()
            (text as NSString).draw(at: CGPoint(x: 10, y: 18), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 25), .foregroundColor: UIColor.white])
        }
    }
}
