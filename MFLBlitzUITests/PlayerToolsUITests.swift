import XCTest

final class PlayerToolsUITests: XCTestCase {
    @MainActor
    func testIneligibleIRIsDisabledInPlayerAndRosterActions() {
        let app = preview()
        app.tabBars.buttons["My Team"].firstMatch.tap()
        let player = app.buttons["roster-player-13319"]
        for _ in 0..<6 where !player.isHittable { app.swipeUp() }
        player.tap()
        let move = app.buttons["Move to IR"]
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        XCTAssertFalse(move.isEnabled)
        XCTAssertTrue(app.staticTexts["Requires Out or IR"].waitForExistence(timeout: 5))
        capture(app, "Player Detail — ineligible IR disabled")
        app.navigationBars["Aaron Jones"].buttons.firstMatch.tap()
        let manage = app.buttons["Manage roster"]
        for _ in 0..<6 where !manage.isHittable { app.swipeDown() }
        manage.tap()
        let menu = revealRosterMenu("13319", in: app)
        menu.tap()
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        XCTAssertFalse(move.isEnabled)
        capture(app, "Roster menu — Questionable does not permit IR")
    }

    @MainActor
    func testFreeAgentAddReviewDoesNotChangeRosterOnCancel() {
        let app = preview()
        app.tabBars.buttons["My Team"].firstMatch.tap()
        app.buttons["Manage roster"].tap()
        app.segmentedControls.buttons["Free agents"].tap()
        let add = app.buttons["Add Isaiah Bond"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        app.buttons["roster-move-player-w1"].tap()
        XCTAssertTrue(app.buttons["player-watch-w1"].waitForExistence(timeout: 5))
        app.navigationBars["Isaiah Bond"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Roster moves"].waitForExistence(timeout: 5))
        XCTAssertTrue(add.exists)
        add.tap()
        let drop = app.buttons["roster-drop-player"]
        XCTAssertTrue(drop.waitForExistence(timeout: 5))
        drop.tap()
        app.buttons["Dak Prescott"].tap()
        let confirm = app.buttons["confirm-roster-move"]
        for _ in 0..<5 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.isHittable && confirm.isEnabled)
        capture(app, "Free-agent add — explicit paired drop review")
        confirm.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        app.segmentedControls.buttons["My roster"].tap()
        let retained = revealRosterMenu("12620", in: app)
        XCTAssertTrue(retained.exists)
    }

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
        let loadHistory = app.buttons["player-load-history"]
        for _ in 0..<7 where !loadHistory.isHittable { app.swipeUp() }
        XCTAssertTrue(loadHistory.waitForExistence(timeout: 5))
        loadHistory.tap()
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
        let playerMenu = revealRosterMenu("12620", in: app)
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
        let menu = revealRosterMenu("12620", in: app)
        XCTAssertTrue(menu.exists)
        XCTAssertGreaterThanOrEqual(menu.frame.height, 44)
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

    @MainActor private func revealRosterMenu(_ playerID: String, in app: XCUIApplication) -> XCUIElement {
        let container = app.descendants(matching: .any).matching(identifier: "roster-manage-\(playerID)").firstMatch
        for _ in 0..<12 {
            // iOS 18 exposes a labeled accessibility wrapper around the actual
            // UIKit menu button. The wrapper itself has no hittable point.
            let nativeButton = container.buttons.firstMatch
            let target = nativeButton.exists ? nativeButton : container
            // Native tap scrolls a realized UIKit control into view. Testing
            // wrapper isHittable first incorrectly scrolls past it on iOS 18.
            if target.exists { return target }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        let nativeButton = container.buttons.firstMatch
        let target = nativeButton.exists ? nativeButton : container
        XCTAssertTrue(target.exists, "Roster action must exist for \(playerID)")
        return target
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
