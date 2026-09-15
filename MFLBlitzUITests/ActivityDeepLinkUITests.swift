import XCTest

final class ActivityDeepLinkUITests: XCTestCase {
    @MainActor func testColdLiveActivityLinkOpensScoresNavigationAndGameContext() {
        let app = start(arguments: ["--deep-link-diagnostics"])
        // Explicitly terminate so every Xcode version exercises a cold URL
        // launch rather than reusing an already-running preview session.
        app.terminate()
        app.open(URL(string: "mflblitz://matchup?scope=2026.41333.0001&week=1&id=0001-0008")!)
        // Xcode opens URLs through a fresh launch. Preview is deliberately not
        // persisted as a signed-in account; resume it to consume the pending URL.
        let preview = app.buttons["Preview Champion Hall"]
        let diagnostics = app.staticTexts["deep-link-diagnostics"]
        print("Cold URL before preview: \(diagnostics.exists ? diagnostics.label : "diagnostics absent")")
        if preview.waitForExistence(timeout: 3) { preview.tap() }
        let opened = app.navigationBars["Week 1 Matchup"].waitForExistence(timeout: 8)
        XCTAssertTrue(opened, "Cold URL after preview: \(diagnostics.exists ? diagnostics.label : "diagnostics absent")")
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
        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8)); preview.tap()
        XCTAssertTrue(app.buttons["matchup-0001-0008"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
