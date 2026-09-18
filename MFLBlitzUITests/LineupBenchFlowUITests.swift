import XCTest

@MainActor
final class LineupBenchFlowUITests: XCTestCase {
    func testStartFromFullBenchCanCancelReopenAndSwapIntoFlex() {
        let app = previewLineup()
        let start = app.buttons["lineup-start-15757"]
        reveal(start, in: app)
        start.tap()
        let picker = app.navigationBars["Choose a starter"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Review & submit lineup"].exists)
        XCTAssertFalse(app.buttons["lineup-start-replacing-12620"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Review & submit lineup"].exists)
        reveal(start, in: app)
        start.tap()
        let flex = app.buttons["lineup-start-replacing-15256"]
        reveal(flex, in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Start from bench — choose an eligible starter"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        flex.tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 3))
        let review = app.buttons["Review & submit lineup"]
        XCTAssertTrue(review.waitForExistence(timeout: 3))
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(app.buttons["lineup-confirm-submit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["lineup-confirm-submit"].label.contains("Submit 9 starters"))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["lineup-confirm-submit"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(review.exists) // Review cancellation retains the draft.
    }

    func testBenchStarterThenFillTheOpenSpot() {
        let app = previewLineup()
        let replace = app.buttons["lineup-replace-15256"]
        reveal(replace, in: app)
        replace.tap()
        let bench = app.buttons["lineup-bench-15256"]
        XCTAssertTrue(bench.waitForExistence(timeout: 3))
        bench.tap()
        XCTAssertTrue(app.navigationBars["Replace FLEX"].waitForNonExistence(timeout: 3))
        let review = app.buttons["Review & submit lineup"]
        XCTAssertTrue(review.waitForExistence(timeout: 3))
        XCTAssertFalse(review.isEnabled)
        let start = app.buttons["lineup-start-16269"]
        reveal(start, in: app)
        start.tap()
        XCTAssertFalse(app.navigationBars["Choose a starter"].exists)
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(app.buttons["lineup-confirm-submit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["lineup-confirm-submit"].label.contains("Submit 9 starters"))
    }

    func testExistingOverfilledDraftCanBenchWithoutAnyFlexReplacements() {
        let app = previewLineup(overfilled: true)
        let replace = app.buttons["lineup-replace-15256"]
        reveal(replace, in: app)
        replace.tap()
        XCTAssertTrue(app.staticTexts["No eligible FLEX replacements"].waitForExistence(timeout: 3))
        let bench = app.buttons["lineup-bench-15256"]
        XCTAssertTrue(bench.isEnabled)
        bench.tap()
        XCTAssertTrue(app.navigationBars["Replace FLEX"].waitForNonExistence(timeout: 3))
        let review = app.buttons["Review & submit lineup"]
        XCTAssertTrue(review.waitForExistence(timeout: 3))
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(app.buttons["lineup-confirm-submit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["lineup-confirm-submit"].label.contains("Submit 9 starters"))
    }

    func testStartPickerSupportsLargestText() {
        let app = previewLineup(launchArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let start = app.buttons["lineup-start-15757"]
        reveal(start, in: app)
        start.tap()
        let flex = app.buttons["lineup-start-replacing-15256"]
        reveal(flex, in: app)
        XCTAssertGreaterThanOrEqual(flex.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(flex.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(flex.frame.height, 44)
        let name = app.staticTexts["lineup-candidate-name-15256"]
        XCTAssertTrue(name.exists)
        let projection = flex.staticTexts["11.2"]
        XCTAssertTrue(projection.exists)
        // Text reports its intrinsic bounds, not the available column width.
        // Stacking the score below the name prevents the original squeeze.
        XCTAssertLessThanOrEqual(name.frame.maxY, projection.frame.minY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Choose a starter — largest text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        flex.tap()
        XCTAssertTrue(app.navigationBars["Choose a starter"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Review & submit lineup"].isEnabled)
    }

    private func previewLineup(overfilled: Bool = false, launchArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-current-lineup"] + launchArguments
        if overfilled { app.launchArguments.append("--synthetic-overfilled-lineup") }
        app.launch()
        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        let tab = app.tabBars.buttons["Lineup"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        tab.tap()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        revealControl(element, in: app, above: app.buttons["Review & submit lineup"])
    }
}
