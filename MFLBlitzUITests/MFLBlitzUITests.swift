import XCTest

final class MFLBlitzUITests: XCTestCase {
    @MainActor
    func testPreviewShowsPriorityTabs() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Preview Champion Hall"].tap()

        XCTAssertTrue(app.tabBars.buttons["Scores"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Lineup"].exists)
        XCTAssertTrue(app.tabBars.buttons["Waivers"].exists)
        XCTAssertTrue(app.tabBars.buttons["Standings"].exists)
        XCTAssertTrue(app.tabBars.buttons["Board"].exists)
    }
}
