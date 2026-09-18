import XCTest

extension XCTestCase {
    /// `isHittable` can be true for a control partly covered by pinned chrome.
    /// Bring its tap point safely into the content area before its normal tap.
    @MainActor func revealControl(_ element: XCUIElement, in app: XCUIApplication,
                                  above pinnedControl: XCUIElement? = nil) {
        for _ in 0..<40 {
            let top = (app.navigationBars.allElementsBoundByIndex.filter(\.isHittable)
                .map { $0.frame.maxY }.max() ?? app.frame.minY) + 8
            var bottom = app.tabBars.firstMatch.exists && app.tabBars.firstMatch.isHittable
                ? app.tabBars.firstMatch.frame.minY : app.frame.maxY - 20
            if let pinnedControl, pinnedControl.exists && pinnedControl.isHittable {
                bottom = min(bottom, pinnedControl.frame.minY)
            }
            bottom -= 8
            let height = bottom - top
            XCTAssertGreaterThan(height, 44, "Scroll within unobscured content")
            guard height > 44 else { return }
            if element.exists && element.isHittable,
               element.frame.midY >= top + 22, element.frame.midY <= bottom - 22 { return }
            let downward = element.exists && element.frame.midY < (top + bottom) / 2
            let from = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: app.frame.midX, dy: top + height * (downward ? 0.3 : 0.75)))
            let to = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: app.frame.midX, dy: top + height * (downward ? 0.75 : 0.3)))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        XCTFail("Could not reveal the control's tap point: \(element.identifier)")
    }
}
