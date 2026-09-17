import XCTest

final class PlayerSearchUITests: XCTestCase {
    @MainActor func testLastNameSearchFindsMasonIncludingAfterScrollingOtherResults() {
        let app = preview(arguments: ["--synthetic-search-names"])
        app.buttons["global-player-search"].firstMatch.tap()
        let field = app.textFields["player-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let mason = app.buttons["search-player-15972"]
        for query in ["Mason", "Jordan", "Jordan Mason"] {
            if app.buttons["clear-player-search"].exists { app.buttons["clear-player-search"].tap() }
            field.tap(); field.typeText(query)
            XCTAssertTrue(mason.waitForExistence(timeout: 5), "Query: \(query)")
            XCTAssertTrue(mason.isHittable, "Query: \(query)")
        }
        app.buttons["clear-player-search"].tap(); field.typeText("WR")
        let firstResult = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search-player-'")).firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5))
        let results = app.scrollViews.matching(NSPredicate(format: "identifier == 'player-search-results'")).firstMatch
        XCTAssertTrue(results.exists)
        for _ in 0..<3 { results.swipeUp() }
        app.buttons["clear-player-search"].tap(); field.typeText("Mason")
        XCTAssertTrue(mason.waitForExistence(timeout: 5))
        XCTAssertTrue(mason.isHittable, "A last-name result must be visible after changing a scrolled search")
        capture(app, "Player search — Mason after a longer scrolled query")
    }

    @MainActor func testHunterSearchPrioritizesOwnedPlayerAndRetainsBothNameMatches() {
        let app = preview(arguments: ["--synthetic-search-names"])
        app.buttons["global-player-search"].firstMatch.tap()
        let field = app.textFields["player-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Jordan Mason")
        let mason = app.buttons["search-player-15972"]
        XCTAssertTrue(mason.waitForExistence(timeout: 5))
        // Wait for the independent membership read before deliberately editing.
        let owned = NSPredicate(format: "label CONTAINS 'Rostered by'")
        expectation(for: owned, evaluatedWith: mason)
        waitForExpectations(timeout: 5)
        app.buttons["clear-player-search"].tap(); field.typeText("Hunter")
        let travis = app.buttons["search-player-search-travis"]
        let henry = app.buttons["search-player-search-henry"]
        XCTAssertTrue(travis.waitForExistence(timeout: 5))
        XCTAssertTrue(henry.exists)
        XCTAssertTrue(travis.isHittable && henry.isHittable)
        XCTAssertLessThan(travis.frame.minY, henry.frame.minY)
        capture(app, "Hunter search — own player first, first and last names matched equally")
        app.buttons["clear-player-search"].tap(); field.typeText("Hunter Henry")
        XCTAssertTrue(henry.waitForExistence(timeout: 5))
        XCTAssertFalse(travis.exists)
    }

    @MainActor func testKeyboardCanDismissWithoutClosingSearchAndFieldCanRefocus() {
        let app = preview()
        app.buttons["global-player-search"].firstMatch.tap()
        let field = app.textFields["player-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let guidance = app.staticTexts["Search by name, team or position."]
        XCTAssertTrue(guidance.waitForExistence(timeout: 3)); guidance.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(field.exists)

        field.tap(); field.typeText("Dak")
        let result = app.buttons["search-player-12620"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let done = app.keyboards.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3)); done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "Dak")
        XCTAssertTrue(result.exists)

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["clear-player-search"].tap(); field.typeText("WR")
        let firstResult = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search-player-'")).firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5))
        firstResult.swipeUp()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "WR")
        XCTAssertTrue(app.buttons["close-player-search"].exists)
        capture(app, "Player search — keyboard dismissed with query and results retained")
    }

    @MainActor func testTappingOutsideSearchClosesItWithoutOpeningTheCoveredPage() {
        let app = preview()
        for isMatchup in [false, true] {
            if isMatchup {
                app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'matchup-'")).firstMatch.tap()
            }
            let title = isMatchup ? "Week 1 Matchup" : "Champion Hall"
            app.buttons["global-player-search"].firstMatch.tap()
            let field = app.textFields["player-search-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Dak")
            let result = app.buttons["search-player-12620"]
            XCTAssertTrue(result.waitForExistence(timeout: 5))
            // Tap the visible page below the bounded panel, above the keyboard.
            let top = result.frame.maxY + 32
            let bottom = app.keyboards.firstMatch.frame.minY - 12
            XCTAssertGreaterThan(bottom, top)
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.midX, dy: (top + bottom) / 2)).tap()
            XCTAssertTrue(field.waitForNonExistence(timeout: 3))
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
            XCTAssertTrue(app.navigationBars[title].exists)
            XCTAssertTrue(app.tabBars.buttons["Scores"].isSelected)
            XCTAssertTrue(app.buttons["global-player-search"].exists)
        }
        capture(app, "Player search — outside tap returns to the same matchup")
    }

    @MainActor func testPatriotsSearchShowsPlayersNotUnsupportedTeamUnits() {
        let app = preview(arguments: ["--synthetic-search-teams"])
        app.buttons["global-player-search"].firstMatch.tap()
        let field = app.textFields["player-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("patriots")
        XCTAssertTrue(app.buttons["search-player-search-ne-wr"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search-player-search-ne-qb"].exists)
        XCTAssertFalse(app.buttons["search-player-search-ne-team-wr"].exists)
        XCTAssertFalse(app.buttons["search-player-search-ne-team-rb"].exists)
        XCTAssertFalse(app.buttons["search-player-search-ne-def"].exists)
        XCTAssertFalse(app.buttons["search-player-search-sea-wr"].exists)
        capture(app, "Patriots search — individual players in league positions")
        field.typeText(" wr")
        XCTAssertTrue(app.buttons["search-player-search-ne-wr"].exists)
        XCTAssertFalse(app.buttons["search-player-search-ne-qb"].exists)
    }
    @MainActor func testSearchOnEveryTabAndPlayerBackKeepsQuery() {
        let app = preview()
        for tab in ["Scores", "Lineup", "My Team", "Standings", "Board"] {
            app.tabBars.buttons[tab].firstMatch.tap()
            let search = app.buttons["global-player-search"].firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            XCTAssertTrue(search.isHittable)
            search.tap()
            XCTAssertEqual(app.sheets.count, 0, "Global search stays inside the current page")
            let field = app.textFields["player-search-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            if tab == "Scores" || tab == "Board" {
                field.tap(); field.typeText("Dak")
                let result = app.buttons["search-player-12620"]
                XCTAssertTrue(result.waitForExistence(timeout: 5))
                XCTAssertTrue(result.label.contains("Uber Beasts"))
                capture(app, "Player search — owner directly in results")
                result.tap()
                XCTAssertTrue(app.navigationBars["Dak Prescott"].waitForExistence(timeout: 5))
                app.navigationBars["Dak Prescott"].buttons.firstMatch.tap()
                XCTAssertTrue(app.navigationBars[tab == "Scores" ? "Champion Hall" : "Board"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.textFields["player-search-field"].value as? String, "Dak")
                XCTAssertTrue(app.buttons["search-player-12620"].exists)
                XCTAssertTrue(app.tabBars.buttons[tab].firstMatch.isSelected)
            }
            let close = app.buttons["close-player-search"]
            XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
            XCTAssertTrue(app.tabBars.buttons[tab].firstMatch.isSelected)
        }
    }

    @MainActor func testMatchupSearchReturnsToSameMatchup() {
        let app = preview()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'matchup-'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Week 1 Matchup"].waitForExistence(timeout: 5))
        app.buttons["global-player-search"].firstMatch.tap()
        let field = app.textFields["player-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Isaiah Bond")
        let result = app.buttons["search-player-w1"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Free agent"))
        result.tap()
        XCTAssertTrue(app.navigationBars["Isaiah Bond"].waitForExistence(timeout: 5))
        app.navigationBars["Isaiah Bond"].buttons.firstMatch.tap()
        app.buttons["close-player-search"].tap()
        XCTAssertTrue(app.navigationBars["Week 1 Matchup"].waitForExistence(timeout: 5))
        capture(app, "Player search — returns to original matchup")
    }

    @MainActor func testSearchWorksWhileOwnershipIsDelayed() {
        let app = preview(arguments: ["--synthetic-slow-search-ownership"])
        app.buttons["global-player-search"].firstMatch.tap()
        let field = app.textFields["player-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Dak")
        let result = app.buttons["search-player-12620"]
        XCTAssertTrue(result.waitForExistence(timeout: 3), "A held 20-second ownership read must not block catalog search")
        XCTAssertTrue(result.label.contains("Checking ownership"))
        capture(app, "Player search — immediate names with delayed ownership")
        result.tap()
        XCTAssertTrue(app.navigationBars["Dak Prescott"].waitForExistence(timeout: 5))
    }

    @MainActor func testOwnershipFailureDoesNotLabelPlayerFreeAgent() {
        let app = preview(arguments: ["--synthetic-search-ownership-offline"])
        app.buttons["global-player-search"].firstMatch.tap()
        let field = app.textFields["player-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Dak")
        let result = app.buttons["search-player-12620"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Ownership unavailable"))
        XCTAssertFalse(result.label.contains("Free agent"))
        XCTAssertTrue(app.buttons["Retry player ownership"].exists)
        capture(app, "Player search — honest offline ownership")
    }

    @MainActor func testLargeTextSearch() {
        let app = preview(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["global-player-search"].firstMatch.tap()
        let field = app.textFields["player-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Dak")
        let result = app.buttons["search-player-12620"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.isHittable)
        XCTAssertTrue(app.buttons["close-player-search"].isHittable)
        capture(app, "Player search — accessibility text")
    }

    @MainActor private func preview(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = arguments; app.launch()
        let enter = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(enter.waitForExistence(timeout: 8))
        let alert = app.alerts["Something went wrong"]
        if alert.exists { alert.buttons["OK"].tap() }
        enter.tap()
        XCTAssertTrue(app.tabBars.buttons["Scores"].firstMatch.waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
