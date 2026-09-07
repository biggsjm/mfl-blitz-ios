import XCTest

final class PlayerToolsUITests: XCTestCase {
    @MainActor
    func testIneligibleIRIsHiddenInDetailAndIRDestination() {
        let app = preview()
        app.tabBars.buttons["My Team"].firstMatch.tap()
        let player = app.buttons["roster-player-13319"]
        for _ in 0..<6 where !player.isHittable { app.swipeUp() }
        player.tap()
        let move = app.buttons["player-action-reserve-13319"]
        let drop = app.buttons["player-action-drop-13319"]
        XCTAssertTrue(drop.waitForExistence(timeout: 5))
        XCTAssertTrue(drop.isHittable && drop.isEnabled)
        XCTAssertFalse(move.exists)
        XCTAssertFalse(app.staticTexts["Requires Out or IR"].exists)
        XCTAssertGreaterThanOrEqual(drop.frame.height, 44)
        // A single native List action can expose the padded row as its
        // accessibility target. Its visible circle remains fixed at 48 pt;
        // the retained screenshot verifies compactness, not that larger hit area.
        XCTAssertFalse(drop.staticTexts["Drop"].exists)
        XCTAssertEqual(drop.label, "Drop player, Aaron Jones")
        capture(app, "Player Detail — symbol-only Drop, ineligible IR omitted")
        app.navigationBars["Aaron Jones"].buttons.firstMatch.tap()
        openTool("injured-reserve", title: "Injured Reserve", in: app)
        XCTAssertTrue(app.buttons["roster-reserve-12620"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roster-reserve-13319"].exists)
        capture(app, "Injured Reserve — only eligible owned players")

    }

    @MainActor
    func testEligibleIRAppearsBesideSymbolOnlyDrop() {
        let app = preview()
        app.tabBars.buttons["Lineup"].firstMatch.tap()
        let player = app.buttons["lineup-player-12620"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        player.tap()
        let move = app.buttons["player-action-reserve-12620"]
        let drop = app.buttons["player-action-drop-12620"]
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilEnabled(move))
        XCTAssertTrue(drop.isHittable && drop.isEnabled)
        XCTAssertFalse(move.staticTexts["Move to IR"].exists)
        XCTAssertEqual(move.label, "Move to IR, Dak Prescott")
        XCTAssertFalse(drop.staticTexts["Drop"].exists)
        XCTAssertGreaterThanOrEqual(move.frame.height, 44)
        XCTAssertGreaterThanOrEqual(drop.frame.height, 44)
        XCTAssertLessThanOrEqual(move.frame.height, 64)
        XCTAssertLessThanOrEqual(drop.frame.height, 64)
        XCTAssertEqual(move.frame.midY, drop.frame.midY, accuracy: 2)
        capture(app, "Player Detail — eligible IR and symbol-only Drop")
    }

    @MainActor
    func testFreeAgentAddReviewDoesNotChangeRosterOnCancel() {
        let app = preview()
        openTool("adds-drops", title: "Adds / Drops", in: app)
        let search = app.textFields["waiver-search"]
        search.tap(); search.typeText("Isaiah Bond\n")
        let add = revealAction("acquire-player-w1", in: app)
        app.buttons["waiver-player-w1"].tap()
        XCTAssertTrue(app.buttons["player-watch-w1"].waitForExistence(timeout: 5))
        let detailAdd = app.buttons["player-action-add-w1"]
        XCTAssertTrue(detailAdd.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilEnabled(detailAdd))
        XCTAssertFalse(detailAdd.staticTexts["Add player"].exists)
        XCTAssertEqual(detailAdd.label, "Add player, Isaiah Bond")
        capture(app, "Player Detail — available symbol-only Add")
        app.navigationBars["Isaiah Bond"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Adds / Drops"].waitForExistence(timeout: 5))
        tapAction(revealAction("acquire-player-w1", in: app), in: app, useMeasuredTouch: true)
        XCTAssertTrue(app.buttons["Place waiver bid"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Add now"].exists)
        capture(app, "Person-plus — choose immediate add or waiver bid")
        app.buttons["Add now"].tap()
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
        let retained = revealAction("roster-drop-12620", in: app)
        XCTAssertTrue(retained.exists)
    }

    @MainActor
    func testLockedFreeAgentCannotOpenImmediateAdd() {
        let app = preview()
        openTool("adds-drops", title: "Adds / Drops", in: app)
        let search = app.textFields["waiver-search"]
        search.tap(); search.typeText("Bhayshul Tuten\n")
        let player = app.buttons["waiver-player-w2"]
        _ = revealAction("acquire-player-w2", in: app)
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        player.tap()
        let add = app.buttons["player-action-add-w2"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled)
        XCTAssertTrue(app.staticTexts["Locked for adds"].exists)
        XCTAssertFalse(app.buttons["confirm-roster-move"].exists)
        capture(app, "Player Detail — locked free agent cannot be added")
    }

    @MainActor
    func testLargeTextPlayerActionsStayCompactAndDropStillRequiresReview() {
        let app = preview(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.tabBars.buttons["Lineup"].firstMatch.tap()
        let player = app.buttons["lineup-player-12620"]
        for _ in 0..<8 where !player.isHittable { app.swipeUp() }
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        player.tap()
        let move = app.buttons["player-action-reserve-12620"]
        let drop = app.buttons["player-action-drop-12620"]
        for _ in 0..<8 where !drop.isHittable { app.swipeUp() }
        XCTAssertTrue(drop.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilEnabled(drop))
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        XCTAssertEqual(drop.frame.midY, move.frame.midY, accuracy: 2)
        XCTAssertGreaterThanOrEqual(drop.frame.height, 44)
        XCTAssertLessThanOrEqual(drop.frame.maxX, app.frame.maxX)
        capture(app, "Player Detail — accessible compact action group")
        drop.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        let confirm = app.buttons["confirm-roster-move"]
        for _ in 0..<10 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(waitUntilEnabled(confirm))
        confirm.tap()
        XCTAssertTrue(app.alerts["Drop player?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["player-action-drop-12620"].waitForExistence(timeout: 5))
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
        let watchlist = app.buttons["my-team-watchlist"]
        for _ in 0..<8 where !watchlist.isHittable { app.swipeDown() }
        watchlist.tap()
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
        openTool("adds-drops", title: "Adds / Drops", in: app)
        app.segmentedControls.buttons["My roster"].tap()
        let drop = revealAction("roster-drop-12620", in: app)
        tapAction(drop, in: app)
        let confirm = app.buttons["confirm-roster-move"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilEnabled(confirm))
        capture(app, "Roster move — explicit review and Close")
        confirm.tap()
        XCTAssertTrue(app.alerts["Drop player?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(drop.waitForExistence(timeout: 5))
        openTool("injured-reserve", title: "Injured Reserve", in: app)
        let reserve = revealAction("roster-reserve-12620", in: app)
        XCTAssertTrue(waitUntilEnabled(reserve))
        tapAction(reserve, in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilEnabled(confirm))
        confirm.tap()
        app.alerts.buttons["Move to IR"].tap()
        XCTAssertTrue(app.staticTexts["Preview roster updated"].waitForExistence(timeout: 15))
        capture(app, "Roster move — confirmed synthetic IR move")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Injured Reserve"].exists)
        let activate = revealAction("roster-activate-12620", in: app)
        XCTAssertTrue(waitUntilEnabled(activate))
        XCTAssertFalse(app.buttons["roster-reserve-12620"].exists)
        capture(app, "Injured Reserve — readback updates capacity and activation")
        tapAction(activate, in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilEnabled(confirm))
        confirm.tap()
        XCTAssertTrue(app.alerts["Activate player?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(activate.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLargeTextRosterReview() {
        let app = preview(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openTool("adds-drops", title: "Adds / Drops", in: app)
        app.segmentedControls.buttons["My roster"].tap()
        let drop = revealAction("roster-drop-12620", in: app)
        XCTAssertGreaterThanOrEqual(drop.frame.height, 44)
        tapAction(drop, in: app)
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        capture(app, "Roster review — largest text identity")
        let confirm = app.buttons["confirm-roster-move"]
        for _ in 0..<10 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.isHittable)
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        capture(app, "Roster review — largest text action")
        app.buttons["Close"].tap()
    }

    @MainActor private func revealAction(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let container = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        for _ in 0..<12 {
            // iOS 18 exposes a labeled accessibility wrapper around the actual
            // UIKit menu button. The wrapper itself has no hittable point.
            let nativeButton = container.buttons.firstMatch
            let target = nativeButton.exists ? nativeButton : container
            // Existence alone can include an offscreen row at large text.
            // Use measured visibility, not the wrapper's unreliable hit point.
            if target.exists && actionIsVisible(target, in: app) { return target }
            let aboveContent = target.exists && target.frame.minY < app.navigationBars.firstMatch.frame.maxY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: aboveContent ? 0.45 : 0.7))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: aboveContent ? 0.7 : 0.45))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        let nativeButton = container.buttons.firstMatch
        let target = nativeButton.exists ? nativeButton : container
        XCTAssertTrue(target.exists, "Roster action must exist: \(identifier)")
        return target
    }

    @MainActor private func actionIsVisible(_ menu: XCUIElement, in app: XCUIApplication) -> Bool {
        let top = app.navigationBars.firstMatch.frame.maxY
        let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
        let frame = menu.frame
        return frame.width >= 44 && frame.height >= 44 &&
            frame.minX >= app.frame.minX && frame.maxX <= app.frame.maxX &&
            frame.minY >= top && frame.maxY <= bottom
    }

    @MainActor private func tapAction(_ menu: XCUIElement, in app: XCUIApplication, useMeasuredTouch: Bool = false) {
        XCTAssertTrue(menu.exists && menu.isEnabled)
        guard actionIsVisible(menu, in: app) else {
            XCTFail("Roster menu must be fully visible before tapping: \(menu.frame)")
            return
        }
        if menu.isHittable && !useMeasuredTouch {
            menu.tap()
            return
        }
        // Xcode 16.4 / iOS 18.5 can expose the visible UIKit Menu button but
        // report no accessibility hit point, even after scroll-to-visible.
        // Exercise a real touch at its measured center (not an action hook).
        // Require the whole target to be inside unobscured content first;
        // the callers must still verify the menu and its actual actions.
        capture(app, "Roster menu — visible target before native touch")
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor private func openTool(_ id: String, title: String, in app: XCUIApplication) {
        app.tabBars.buttons["My Team"].firstMatch.tap()
        if app.navigationBars[title].exists { return }
        for _ in 0..<5 where !app.navigationBars["My Team"].exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
        tapAction(revealAction("my-team-\(id)", in: app), in: app)
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    @MainActor private func preview(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        let enterPreview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(enterPreview.waitForExistence(timeout: 5))
        // Fixture sessions left by app-unit tests may fail restoration on launch.
        // Dismiss that alert deliberately so XCTest's interruption handler cannot
        // replay a stale onboarding tap onto the newly presented tab content.
        let restoreAlert = app.alerts["Something went wrong"]
        if restoreAlert.exists { restoreAlert.buttons["OK"].tap() }
        enterPreview.tap()
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
