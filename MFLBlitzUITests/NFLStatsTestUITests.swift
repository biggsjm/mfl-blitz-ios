import XCTest

final class NFLStatsTestUITests: XCTestCase {
    @MainActor func testHistoricalPreviewFromSettings() {
        let app = XCUIApplication()
        app.launch()
        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10)); preview.tap()
        app.tabBars.buttons["My Team"].firstMatch.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        let test = app.buttons["nfl-stats-test"]
        if !test.isHittable { app.swipeUp() }
        XCTAssertTrue(test.waitForExistence(timeout: 5)); test.tap()
        XCTAssertTrue(app.staticTexts["Synthetic preview"].waitForExistence(timeout: 5))
        app.buttons["nfl-test-load-games"].tap()
        let game = app.buttons["nfl-test-game-11"]
        XCTAssertTrue(game.waitForExistence(timeout: 5)); game.tap()
        app.buttons["nfl-test-load-players"].tap()
        let player = app.buttons["nfl-test-player-1-10"]
        XCTAssertTrue(player.waitForExistence(timeout: 5)); player.tap()
        XCTAssertTrue(app.staticTexts["Example Quarterback"].waitForExistence(timeout: 5))
        let yards = app.descendants(matching: .any)["nfl-test-stat-Passing-yards"].firstMatch
        XCTAssertTrue(yards.waitForExistence(timeout: 5))
        XCTAssertEqual(yards.label, "Yards, 240")
        XCTAssertEqual(app.descendants(matching: .any)["nfl-test-stat-Passing-passing touch downs"].firstMatch.label, "Passing TDs, 0")
        XCTAssertEqual(app.descendants(matching: .any)["nfl-test-stat-Passing-sacks"].firstMatch.label, "Sacks, —")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Historical NFL stats – synthetic preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let review = app.buttons["nfl-test-review-match"]
        if !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.waitForExistence(timeout: 5)); review.tap()
        let candidate = app.buttons["nfl-test-candidate-101"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nfl-test-candidate-102"].exists)
        XCTAssertFalse(app.buttons["nfl-test-confirm-match"].exists)
        candidate.tap()
        let confirm = app.buttons["nfl-test-confirm-match"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertFalse(confirm.isEnabled)
        let note = app.textFields["nfl-test-verification-note"].firstMatch
        if !note.isHittable { app.swipeUp() }
        // axis: .vertical is exposed as a text view on supported iOS releases.
        let noteView = app.textViews["nfl-test-verification-note"].firstMatch
        let input = note.exists ? note : noteView
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap()
        input.typeText("Verified synthetic profile identities.")
        app.swipeUp()
        XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue(app.staticTexts["Reviewed match"].waitForExistence(timeout: 5))
        let matched = XCTAttachment(screenshot: app.screenshot())
        matched.name = "Reviewed historical player match – synthetic only"; matched.lifetime = .keepAlways
        add(matched)
        app.buttons["nfl-test-remove-match"].tap()
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Reviewed match"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(player.waitForExistence(timeout: 5))
    }
}
