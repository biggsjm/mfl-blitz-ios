import XCTest

final class PlayerToolsUITests: XCTestCase {
    @MainActor
    func testWatchlistAndResearchKeepMyTeamNavigation() {
        let app = preview()
        app.tabBars.buttons["My Team"].firstMatch.tap()
        let player = app.buttons["roster-player-12620"]
        for _ in 0..<5 where !player.isHittable { app.swipeUp() }
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        player.tap()
        let watch = app.buttons["player-watch-12620"]
        XCTAssertTrue(watch.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilEnabled(watch))
        watch.tap()
        XCTAssertEqual(watch.label, "Remove from watchlist")
        let history = app.descendants(matching: .any)["player-recent-form"].firstMatch
        for _ in 0..<7 where !history.isHittable { app.swipeUp() }
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        capture(app, "Player research — history and availability")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls["team-section-picker"].buttons["Watchlist"].tap()
        let saved = app.buttons["watchlist-player-12620"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        capture(app, "My Team — synced watchlist")
        saved.tap()
        XCTAssertTrue(watch.waitForExistence(timeout: 5))
        XCTAssertEqual(watch.label, "Remove from watchlist")
        watch.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Your shortlist starts here"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRosterReviewCancelAndIRReadback() {
        let app = preview()
        app.tabBars.buttons["My Team"].firstMatch.tap()
        let manage = app.buttons["Manage roster"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        manage.tap()
        let playerMenu = app.buttons["Manage Dak Prescott"]
        for _ in 0..<5 where !playerMenu.isHittable { app.swipeUp() }
        XCTAssertTrue(playerMenu.waitForExistence(timeout: 5))
        playerMenu.tap()
        app.buttons["Drop player"].tap()
        let confirm = app.buttons["confirm-roster-move"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilEnabled(confirm))
        capture(app, "Roster move — explicit review and Close")
        confirm.tap()
        XCTAssertTrue(app.alerts["Drop player?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(playerMenu.waitForExistence(timeout: 5))
        playerMenu.tap()
        app.buttons["Move to IR"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilEnabled(confirm))
        confirm.tap()
        app.alerts.buttons["Move to IR"].tap()
        XCTAssertTrue(app.staticTexts["Preview roster updated"].waitForExistence(timeout: 15))
        capture(app, "Roster move — confirmed synthetic IR move")
        app.buttons["Close"].tap()
        app.swipeUp()
        XCTAssertTrue(app.navigationBars["Roster moves"].exists)
    }

    @MainActor
    func testLargeTextRosterReview() {
        let app = preview(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.tabBars.buttons["My Team"].firstMatch.tap()
        let manage = app.buttons["Manage roster"]
        for _ in 0..<6 where !manage.isHittable { app.swipeUp() }
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        manage.tap()
        let menu = app.buttons["Manage Dak Prescott"]
        for _ in 0..<8 where !menu.isHittable { app.swipeUp() }
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        app.buttons["Drop player"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        capture(app, "Roster review — largest text identity")
        let confirm = app.buttons["confirm-roster-move"]
        for _ in 0..<10 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.isHittable)
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        capture(app, "Roster review — largest text action")
        app.buttons["Close"].tap()
    }

    @MainActor private func preview(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        app.buttons["Preview Champion Hall"].tap()
        XCTAssertTrue(app.tabBars.buttons["My Team"].firstMatch.waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func waitUntilEnabled(_ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)], timeout: 5) == .completed
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
