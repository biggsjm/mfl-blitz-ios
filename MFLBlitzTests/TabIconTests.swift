import Testing
import UIKit
@testable import MFLBlitz

@MainActor
struct TabIconTests {
    @Test("The lineup play diagram is bundled at tab-bar size and inherits native tint")
    func lineupPlayAsset() throws {
        let image = try #require(UIImage(named: "LineupPlay", in: .main, compatibleWith: nil))
        #expect(image.size == CGSize(width: 25, height: 25))
        #expect(image.renderingMode == .alwaysTemplate)
    }
}
