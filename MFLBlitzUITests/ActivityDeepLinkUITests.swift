import XCTest

final class ActivityDeepLinkUITests: XCTestCase {
    @MainActor func testColdLiveActivityLinkOpensScoresNavigationAndGameContext() {
        let app = start()
        // Explicitly terminate so every Xcode version exercises a cold URL
        // launch rather than reusing an already-running preview session.
        app.terminate()
        // Open through Safari, as a visible external caller would.
        // Xcode 16's XCUIApplication.open launches this app without delivering
        // the URL to its SwiftUI handler on the CI simulator.
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        if safari.buttons["Continue"].exists { safari.buttons["Continue"].tap() }
        let address = safari.textFields.matching(NSPredicate(format:
            "identifier == %@ OR identifier == %@ OR label == %@", "URL", "TabBarItemTitle", "Address")).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 8), safari.debugDescription)
        address.tap()
        safari.textFields.firstMatch.typeText("mflblitz://matchup?scope=2026.41333.0001&week=1&id=0001-0008\n")
        // Safari presents this confirmation as a sheet rather than an Alert.
        let open = safari.buttons["Open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), safari.debugDescription)
        // Safari's sheet can incorrectly ask XCTest to scroll this visible
        // button. Tap its measured center without invoking that AX action.
        let openFrame = open.frame
        XCTAssertTrue(safari.frame.contains(openFrame))
        safari.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: openFrame.midX, dy: openFrame.midY)).tap()
        // Preview is deliberately not persisted as a signed-in account;
        // verify the visible screen and resume it to consume the queued URL.
        // Querying UI also reconnects XCTest to the externally launched process.
        enterPreview(in: app)
        let opened = app.navigationBars["Week 1 Matchup"].waitForExistence(timeout: 8)
        XCTAssertTrue(opened)
        guard opened else { return }
        XCTAssertTrue(app.tabBars.buttons["Scores"].isSelected)
        XCTAssertFalse(app.buttons["Close"].exists)
        let player = app.buttons["matchup-player-0001-starter-0-away"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertTrue(player.label.contains("24") && player.label.contains("17"))
        capture(app, "Live Activity — normal Scores navigation and NFL context")
        player.tap()
        XCTAssertTrue(app.descendants(matching: .any)["player-nfl-game"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["player-game-stats"].exists)
        capture(app, "Player — NFL score clock and available stat line")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["matchup-0001-0008"].waitForExistence(timeout: 5))
    }

    @MainActor private func start(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = arguments; app.launch()
        enterPreview(in: app)
        XCTAssertTrue(app.buttons["matchup-0001-0008"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func enterPreview(in app: XCUIApplication) {
        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        // Unsigned simulator builds can report unavailable secure storage.
        let alert = app.alerts["Something went wrong"]
        if alert.exists {
            XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Couldn’t restore your MFL session")).firstMatch.exists)
            alert.buttons["OK"].tap()
        }
        preview.tap()
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
