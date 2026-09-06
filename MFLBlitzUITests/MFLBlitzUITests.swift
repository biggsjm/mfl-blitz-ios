import XCTest

final class MFLBlitzUITests: XCTestCase {
    @MainActor
    func testBoardDraftSurvivesClosingComposer() throws {
        let app = XCUIApplication()
        app.launch()
        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        let board = app.tabBars.buttons["Board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        board.tap()
        app.buttons["New thread"].tap()
        let subject = app.textFields["What’s the topic?"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        subject.tap()
        subject.typeText("Week one test")
        let body = app.textViews["Message body"]
        body.tap()
        body.typeText("A draft, not a league post.")
        app.buttons["Save & close"].tap()
        app.buttons["New thread"].tap()
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        XCTAssertEqual(subject.value as? String, "Week one test")
        XCTAssertEqual(body.value as? String, "A draft, not a league post.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Saved private board draft"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

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

    @MainActor
    func testStandingsExplainsOfficialLeagueOrder() throws {
        let app = XCUIApplication()
        app.launch()

        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        preview.tap()
        let standingsTab = app.tabBars.buttons["Standings"]
        XCTAssertTrue(standingsTab.waitForExistence(timeout: 3))
        standingsTab.tap()

        let orderInfo = app.buttons["standings-order-info"]
        XCTAssertTrue(orderInfo.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Official league order"].exists)
        orderInfo.tap()

        XCTAssertTrue(app.staticTexts["Official league order"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["standings-order-rule"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Standings order info"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Done"].tap()
        XCTAssertFalse(app.staticTexts["Official league order"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testLineupRowsExposeDirectStartAndReplacementButtons() throws {
        let app = XCUIApplication()
        app.launch()

        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        preview.tap()
        let lineupTab = app.tabBars.buttons["Lineup"]
        XCTAssertTrue(lineupTab.waitForExistence(timeout: 3))
        lineupTab.tap()

        let replacementButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "lineup-replace-")
        )
        XCTAssertTrue(replacementButtons.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(replacementButtons.firstMatch.isHittable)
        XCTAssertFalse(
            app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Actions for ")
            ).firstMatch.exists
        )

        let startButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "lineup-start-")
        )
        for _ in 0 ..< 10 where !startButtons.firstMatch.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(startButtons.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(startButtons.firstMatch.isHittable)
        XCTAssertFalse(
            app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Actions for ")
            ).firstMatch.exists
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Direct lineup arrows"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertFalse(app.buttons["Review & submit lineup"].exists)
        startButtons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Review & submit lineup"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testQuarterbackReplacementPickerCancelsAndSwapsWithoutSubmitting() throws {
        let app = XCUIApplication()
        app.launch()
        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        let lineupTab = app.tabBars.buttons["Lineup"]
        XCTAssertTrue(lineupTab.waitForExistence(timeout: 3))
        lineupTab.tap()
        let replaceDak = app.buttons["lineup-replace-12620"]
        XCTAssertTrue(replaceDak.waitForExistence(timeout: 3))
        replaceDak.tap()

        XCTAssertTrue(app.navigationBars["Replace QB"].waitForExistence(timeout: 3))
        let kyler = app.buttons["lineup-replacement-14056"]
        XCTAssertTrue(kyler.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lineup-replacement-")).count, 1)
        XCTAssertFalse(app.buttons["lineup-replacement-15712"].exists) // RB
        XCTAssertFalse(app.buttons["lineup-replacement-15757"].exists) // WR
        XCTAssertFalse(app.buttons["lineup-replacement-16269"].exists) // TE

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Same-position replacement picker"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Cancel"].tap()
        XCTAssertTrue(replaceDak.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Review & submit lineup"].exists)
        replaceDak.tap()
        XCTAssertTrue(kyler.waitForExistence(timeout: 3))
        kyler.tap()
        XCTAssertTrue(app.buttons["Review & submit lineup"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Replace QB"].exists)
        let replaceKyler = app.buttons["lineup-replace-14056"]
        for _ in 0..<8 where !replaceKyler.isHittable { app.swipeUp() }
        XCTAssertTrue(replaceKyler.isHittable)
        XCTAssertFalse(app.buttons["lineup-replace-12620"].exists)
        // Do not tap Review & submit; this test verifies a local draft only.
    }
}
