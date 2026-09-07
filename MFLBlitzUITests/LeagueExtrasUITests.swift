import XCTest

final class LeagueExtrasUITests: XCTestCase {
    @MainActor func testTradingBlockFirstEditDraftRecoveryAndOfflinePublication() {
        let app = preview()
        openTool("trades", title: "Trades", in: app)
        app.segmentedControls["trades-section"].buttons["Trading Block"].tap()
        let edit = app.buttons["block-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(enabled(edit))
        capture(app, "Trading Block — league listings and visible owner action")
        edit.tap()
        let publish = app.buttons["block-publish"]
        XCTAssertTrue(publish.waitForExistence(timeout: 5))
        XCTAssertFalse(publish.isEnabled)
        app.buttons["block-choose-assets"].tap()
        let player = app.buttons["trade-asset-12620"]
        for _ in 0..<5 where !player.isHittable { app.swipeUp() }
        XCTAssertTrue(player.isHittable)
        player.tap()
        app.navigationBars["Choose assets"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["My trading block"].waitForExistence(timeout: 5))
        XCTAssertTrue(publish.isEnabled)
        app.navigationBars["My trading block"].buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Save draft"].waitForExistence(timeout: 5))
        app.buttons["Save draft"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertEqual(edit.label, "Resume draft")
        edit.tap()
        XCTAssertTrue(publish.waitForExistence(timeout: 5))
        XCTAssertTrue(publish.isEnabled)
        capture(app, "Trading Block — recovered owner draft, explicit publication")
        // This app was explicitly placed in its offline Demo repository above.
        // Publishing here changes only synthetic in-memory league state.
        publish.tap()
        let alert = app.alerts["Trading Block"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Trading block published."].exists)
        alert.buttons["OK"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertEqual(edit.label, "Edit block")
        edit.tap()
        XCTAssertTrue(publish.waitForExistence(timeout: 5))
        XCTAssertFalse(publish.isEnabled, "Unchanged published terms cannot be sent again")
        app.navigationBars["My trading block"].buttons["Close"].tap()
    }

    @MainActor func testBlockOfferPreservesExistingTradeDraft() {
        let app = preview()
        openTool("trades", title: "Trades", in: app)
        let create = app.buttons["trade-new"]
        XCTAssertTrue(enabled(create)); create.tap()
        let message = app.textViews["trade-message"].exists ? app.textViews["trade-message"] : app.textFields["trade-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5)); message.tap(); message.typeText("Existing offer draft")
        app.buttons["trade-save-draft"].tap()
        XCTAssertTrue(app.segmentedControls["trades-section"].waitForExistence(timeout: 5))
        app.segmentedControls["trades-section"].buttons["Trading Block"].tap()
        let offer = app.buttons["block-offer-0008"]
        XCTAssertTrue(offer.waitForExistence(timeout: 5))
        for _ in 0..<4 where !offer.isHittable { app.swipeUp() }
        offer.tap()
        XCTAssertTrue(app.buttons["Resume existing draft"].waitForExistence(timeout: 5))
        capture(app, "Trading Block — existing offer draft protected")
        app.buttons["Resume existing draft"].tap()
        XCTAssertTrue(app.navigationBars["Build a trade"].waitForExistence(timeout: 5))
        let restored = app.textViews["trade-message"].exists ? app.textViews["trade-message"] : app.textFields["trade-message"]
        XCTAssertEqual(restored.value as? String, "Existing offer draft")
        app.buttons["trade-cancel-draft"].tap()
    }

    @MainActor func testCalendarEventReminderAndModeNavigation() {
        let app = preview()
        openTool("schedule", title: "Schedule", in: app)
        app.segmentedControls["schedule-section"].buttons["Calendar"].tap()
        let event = app.buttons["calendar-event-demo-bids:0"]
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        capture(app, "Calendar — concise dated agenda")
        event.tap()
        let remind = app.buttons["calendar-remind-me"]
        XCTAssertTrue(remind.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Manage bids"].exists)
        XCTAssertFalse(app.buttons["Add to Apple Calendar"].isEnabled, "Offline tests cannot create personal calendar entries")
        remind.tap()
        let enable = app.buttons["calendar-enable-reminder"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Remind me"].frame.contains(enable.frame), "The primary action stays visible without scrolling the sheet")
        XCTAssertTrue(enable.isHittable)
        capture(app, "Calendar — contextual opt-in reminder timing")
        enable.tap() // Preview notification service never asks iOS or schedules a real alert.
        XCTAssertTrue(app.navigationBars["League event"].waitForExistence(timeout: 5))
        XCTAssertTrue(remind.label.contains("1 hour before"))
        app.navigationBars["League event"].buttons.firstMatch.tap()
        XCTAssertTrue(app.segmentedControls["schedule-section"].waitForExistence(timeout: 5))
        app.segmentedControls["schedule-section"].buttons["Matchups"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["team-schedule-0001"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["calendar-reminder-settings"].exists)
        app.segmentedControls["schedule-section"].buttons["Calendar"].tap()
        XCTAssertTrue(event.waitForExistence(timeout: 5))
    }

    @MainActor func testBlockAndCalendarWithLargeText() {
        let app = preview(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"])
        openTool("trades", title: "Trades", in: app)
        app.segmentedControls["trades-section"].buttons["Trading Block"].tap()
        let edit = app.buttons["block-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(edit.isHittable)
        capture(app, "Trading Block — maximum Dynamic Type")
        app.navigationBars["Trades"].buttons.firstMatch.tap()
        openTool("schedule", title: "Schedule", in: app)
        app.segmentedControls["schedule-section"].buttons["Calendar"].tap()
        let event = app.buttons["calendar-event-demo-bids:0"]
        for _ in 0..<6 where !event.exists || !event.isHittable { app.swipeUp() }
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        XCTAssertTrue(event.isHittable)
        capture(app, "Calendar — maximum Dynamic Type")
    }

    @MainActor private func preview(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments; app.launch()
        let button = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        if app.alerts["Something went wrong"].exists { app.alerts["Something went wrong"].buttons["OK"].tap() }
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        button.tap()
        XCTAssertTrue(app.tabBars.buttons["My Team"].firstMatch.waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func openTool(_ id: String, title: String, in app: XCUIApplication) {
        app.tabBars.buttons["My Team"].firstMatch.tap()
        let button = app.buttons["my-team-\(id)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        button.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }
    @MainActor private func enabled(_ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)], timeout: 5) == .completed
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
