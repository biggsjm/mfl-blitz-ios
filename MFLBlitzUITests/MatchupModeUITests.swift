import XCTest

final class MatchupModeUITests: XCTestCase {
    @MainActor func testTimelineGroupsTeamChangeAndContributingPlayers() {
        let app = start(arguments: ["--timeline-scores-preview"])
        app.buttons["matchup-0001-0008"].tap()
        let timeline = app.buttons["open-matchup-timeline"]
        for _ in 0..<6 where !timeline.isHittable { app.swipeUp() }
        timeline.tap()
        let update = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "+7.0 pts")).firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 5)); update.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Brenton Strange")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Dak Prescott")).firstMatch.exists)
        capture(app, "Matchup timeline — one team change with player contributions")
    }
    @MainActor func testLivePlayersFiltersCompletedStartersAndReturnsFromDetails() {
        walkthrough()
    }
    @MainActor func testLivePlayersAtLargestText() {
        walkthrough(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }
    @MainActor private func walkthrough(arguments: [String] = []) {
        let app = start(arguments: arguments)
        app.buttons["matchup-0001-0008"].tap()
        let mode = app.segmentedControls["matchup-view-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5)); mode.buttons["Live players"].tap()
        let player = app.buttons["matchup-player-12620-away"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertTrue(player.label.contains("311 pass yd"))
        XCTAssertTrue(player.label.contains("2 pass TD"))
        XCTAssertFalse(player.label.contains("pregame projection"))
        XCTAssertFalse(player.label.contains("Points:"))
        XCTAssertFalse(app.staticTexts["Points detail"].exists)
        XCTAssertFalse(app.buttons["matchup-player-0001-starter-6-away"].exists, "A final-game starter belongs in Lineups")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Completed")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bench scoring")).firstMatch.exists)
        let pinned = app.descendants(matching: .any)["pinned-matchup-score"].firstMatch
        XCTAssertTrue(pinned.exists, "Live players always keeps the official matchup totals visible")
        let homeSide = arguments.isEmpty ? "home" : "away"
        let areaIDs = ["12620-away", "0001-starter-2-away", "0008-starter-0-\(homeSide)", "0008-starter-2-\(homeSide)"]
        let areas = areaIDs.map { app.buttons["matchup-player-\($0)"] }
        for area in areas {
            XCTAssertTrue(area.exists)
            XCTAssertEqual(area.frame.height, areas[0].frame.height, accuracy: 1, "Every live player has the same tappable area, including injury/status content")
        }
        XCTAssertEqual(areas[1].frame.minY - areas[0].frame.minY, areas[3].frame.minY - areas[2].frame.minY, accuracy: 1)
        if arguments.isEmpty {
            XCTAssertEqual(areas[0].frame.minY, areas[2].frame.minY, accuracy: 1)
            XCTAssertEqual(areas[1].frame.minY, areas[3].frame.minY, accuracy: 1)
            let pointIDs = ["0001-12620", "0001-0001-starter-2", "0008-0008-starter-0", "0008-0008-starter-2"]
            let points = pointIDs.map { app.staticTexts["matchup-points-\($0)"] }
            for index in areas.indices {
                XCTAssertTrue(points[index].exists)
                XCTAssertEqual(points[index].frame.midY, areas[index].frame.midY, accuracy: 1, "Points stay centered in equal player areas")
            }
        }
        capture(app, "Live players — active players and persistent totals")
        for _ in 0..<8 where !player.isHittable { app.swipeUp() }
        player.tap()
        XCTAssertTrue(app.segmentedControls["player-scoring-segments"].waitForExistence(timeout: 5))
        let owner = app.staticTexts["player-week-owner"]
        XCTAssertTrue(owner.waitForExistence(timeout: 5))
        XCTAssertTrue(owner.label.contains("Uber Beasts"))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(mode.buttons["Live players"].isSelected)
        mode.buttons["Lineups"].tap()
        XCTAssertTrue(mode.buttons["Lineups"].isSelected)
        XCTAssertTrue(app.buttons["matchup-player-0001-starter-6-away"].exists)
        let lineupIDs = ["12620-away", "0001-starter-2-away", "0001-starter-6-away", "0008-starter-0-home"]
        let lineupAreas = lineupIDs.map { app.buttons["matchup-player-\($0)"] }
        for area in lineupAreas {
            XCTAssertTrue(area.exists)
            XCTAssertEqual(area.frame.height, lineupAreas[0].frame.height, accuracy: 1, "All lineup player areas share the same height")
        }
        capture(app, "Equal player areas — lineups")
        mode.buttons["Live players"].tap()
        XCTAssertTrue(player.exists)
        XCTAssertTrue(pinned.exists)
        XCTAssertFalse(app.buttons["matchup-player-0001-starter-6-away"].exists)
        mode.buttons["Lineups"].tap()
    }
    @MainActor func testPlayerWeekStatsAgreeFromSearchLineupRosterAndMatchup() {
        let app = start()
        app.buttons["global-player-search"].firstMatch.tap()
        let field = app.textFields["player-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Dak")
        let result = app.buttons["search-player-12620"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Rostered by Uber Beasts"))
        result.tap()
        checkWeek(app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(app.textFields["player-search-field"].value as? String, "Dak")
        app.buttons["close-player-search"].tap()
        app.buttons["matchup-0001-0008"].tap()
        let player = app.buttons["matchup-player-12620-away"]
        for _ in 0..<6 where !player.isHittable { app.swipeUp() }
        player.tap(); checkWeek(app)
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Lineup"].tap()
        let lineupPlayer = app.buttons["lineup-player-12620"]
        for _ in 0..<8 where !lineupPlayer.isHittable { app.swipeUp() }
        lineupPlayer.tap(); checkWeek(app)
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["My Team"].tap()
        let rosterPlayer = app.buttons["roster-player-12620"]
        for _ in 0..<8 where !rosterPlayer.isHittable { app.swipeUp() }
        rosterPlayer.tap(); checkWeek(app)
    }
    @MainActor func testLineupReadinessAndCompactTeamToolsRemainDiscoverable() {
        lineupToolbar()
    }
    @MainActor func testLineupToolbarAtLargestText() {
        lineupToolbar(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }
    @MainActor private func lineupToolbar(arguments: [String] = []) {
        let app = start(arguments: arguments)
        app.tabBars.buttons["Lineup"].tap()
        let bell = app.buttons["lineup-alerts-toolbar"]
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lineup-alert-coverage"].exists)
        capture(app, "Lineup — compact bell toolbar")
        bell.tap()
        let readiness = app.descendants(matching: .any)["lineup-readiness"].firstMatch
        XCTAssertTrue(readiness.waitForExistence(timeout: 5))
        let alerts = app.buttons["lineup-alert-coverage"]
        for _ in 0..<6 where !alerts.isHittable { app.swipeUp() }
        XCTAssertTrue(alerts.waitForExistence(timeout: 5)); alerts.tap()
        XCTAssertTrue(app.navigationBars["Lineup alerts"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["Incomplete lineup"].value as? String, "0")
        capture(app, "Lineup — coverage separate from preferences")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()
        app.tabBars.buttons["My Team"].tap()
        XCTAssertTrue(app.buttons["my-team-schedule"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["my-team-adds-drops"].exists)
        capture(app, "My Team — compact tools and pending actions")
        app.buttons["my-team-more-tools"].tap()
        for id in ["trades", "watchlist", "injured-reserve", "activity"] {
            XCTAssertTrue(app.buttons["my-team-\(id)"].exists)
        }
    }
    @MainActor private func checkWeek(_ app: XCUIApplication) {
        XCTAssertTrue(app.segmentedControls["player-scoring-segments"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.segmentedControls.buttons["Week 1"].isSelected)
        let owner = app.staticTexts["player-week-owner"]
        XCTAssertTrue(owner.waitForExistence(timeout: 5))
        XCTAssertTrue(owner.label.contains("Rostered by Uber Beasts"))
        XCTAssertTrue(owner.label.contains("Demo Owner 1"))
        let box = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "311")).firstMatch
        for _ in 0..<5 where !box.isHittable { app.swipeUp() }
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Q3 04:32")).firstMatch.exists)
        capture(app, "Weekly player detail — consistent NFL stats")
    }
    @MainActor private func start(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--nfl-scoring-preview", "--unified-player-preview", "--reset-matchup-mode"] + arguments
        app.launch()
        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8)); preview.tap()
        XCTAssertTrue(app.buttons["matchup-0001-0008"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        if name.contains("active players") {
            let size = app.launchArguments.contains("UICTContentSizeCategoryAccessibilityXXXL") ? "largest" : "normal"
            let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mfl-matchup-\(size)")
            try? app.screenshot().pngRepresentation.write(to: path.appendingPathExtension("png"))
            try? app.debugDescription.write(to: path.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
            print("Matchup capture: \(path.path)")
        }
    }
}
