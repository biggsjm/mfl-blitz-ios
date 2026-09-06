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

    @MainActor
    func testScoreCardOpensPositionByPositionMatchup() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Preview Champion Hall"].tap()

        let matchup = app.buttons["matchup-0001-0008"]
        XCTAssertTrue(matchup.waitForExistence(timeout: 3))
        matchup.tap()

        XCTAssertTrue(app.navigationBars["Week 1 Matchup"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Starting lineups"].exists)
        let quarterbackComparison = app.staticTexts["position-QB"]
        XCTAssertTrue(quarterbackComparison.exists)
        for _ in 0 ..< 4 where !quarterbackComparison.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(quarterbackComparison.isHittable)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Position-by-position matchup"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
