import XCTest

final class ScoringSystemUITests: XCTestCase {
    @MainActor func testCompactDataStatusAndProjectionHelp() {
        dataStatus()
    }
    @MainActor func testDataStatusAtLargestTextSize() {
        dataStatus(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }
    @MainActor func testMissingStatsDoNotShowAnInventedZeroTotal() {
        let app = start()
        app.buttons["matchup-0001-0008"].tap()
        let player = app.buttons["matchup-player-0001-starter-0-away"]
        for _ in 0..<8 where !player.isHittable { app.swipeUp() }
        player.tap()
        let breakdown = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Points breakdown")).firstMatch
        for _ in 0..<6 where !breakdown.isHittable { app.swipeUp() }
        breakdown.tap()
        let official = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "MFL points")).firstMatch
        XCTAssertTrue(official.waitForExistence(timeout: 3))
        XCTAssertTrue(official.label.contains("22.5"))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Shown stats total")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Not yet explained")).firstMatch.exists)
        capture(app, "Data status — missing stats preserve official points")
    }
    @MainActor private func dataStatus(arguments: [String] = []) {
        let app = start(arguments: arguments)
        app.buttons["score-freshness"].tap()
        XCTAssertTrue(app.navigationBars["Data status"].waitForExistence(timeout: 5))
        capture(app, "Data status — compact service summary")
        for title in ["MFL scores", "NFL player stats", "Background updates"] {
            for _ in 0..<5 where !app.staticTexts[title].isHittable { app.swipeUp() }
            XCTAssertTrue(app.staticTexts[title].exists)
        }
        let nfl = app.buttons["data-status-nfl"]
        for _ in 0..<5 where !nfl.isHittable { app.swipeDown() }
        nfl.tap()
        XCTAssertTrue(app.staticTexts["Sample NFL stats; no live connection."].waitForExistence(timeout: 3))
        capture(app, "Data status — brief source detail")
        let about = app.buttons["about-projections"]
        for _ in 0..<6 where !about.isHittable { app.swipeUp() }
        XCTAssertTrue(about.isHittable); about.tap()
        XCTAssertTrue(app.navigationBars["About projections"].waitForExistence(timeout: 3))
        capture(app, "Data status — separate projection explanation")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["score-freshness"].waitForExistence(timeout: 3))
    }
    @MainActor func testPointsBreakdownAndPersistentTimeline() {
        gameDayFeatures()
    }
    @MainActor func testGameDayFeaturesAtLargestTextSize() {
        gameDayFeatures(arguments:["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"])
    }
    @MainActor private func gameDayFeatures(arguments:[String] = []) {
        let app=start(arguments:["--nfl-scoring-preview", "--timeline-gaps-preview"]+arguments)
        app.buttons["matchup-0001-0008"].tap()
        let timeline=app.buttons["open-matchup-timeline"]
        for _ in 0..<8 where !timeline.isHittable { app.swipeUp() }
        XCTAssertTrue(timeline.waitForExistence(timeout:5));timeline.tap()
        XCTAssertTrue(app.navigationBars["Matchup timeline"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["No score changes yet"].exists)
        XCTAssertTrue(app.staticTexts["Some updates weren’t recorded"].exists)
        XCTAssertFalse(app.staticTexts["Tracking started"].exists)
        XCTAssertFalse(app.staticTexts["Gap in updates"].exists)
        capture(app,"Game day — saved matchup timeline")
        let details=app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Recording details")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout:5));details.tap()
        XCTAssertTrue(app.staticTexts["Tracking started"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Gap in updates")).count, 4)
        capture(app,"Game day — optional recording details")
        app.navigationBars.buttons.firstMatch.tap()
        let receiver=app.buttons["matchup-player-0001-starter-6-away"]
        revealControl(receiver, in: app)
        XCTAssertTrue(receiver.isHittable);receiver.tap()
        let breakdown=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Points breakdown")).firstMatch
        for _ in 0..<8 where !breakdown.isHittable { app.swipeUp() }
        XCTAssertTrue(breakdown.waitForExistence(timeout:5));breakdown.tap()
        let td=app.staticTexts["Receiving touchdowns"]
        for _ in 0..<8 where !td.isHittable { app.swipeUp() }
        XCTAssertTrue(td.waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["1 × 6"].exists)
        capture(app,"Game day — league scoring includes receiving touchdown")
    }
    @MainActor func testLineupAlertsStartOffAndOfferIncompleteOption() {
        let app=start()
        app.tabBars.buttons["My Team"].tap()
        app.buttons["Settings"].tap()
        let alerts=app.buttons["Lineup alerts"]
        for _ in 0..<5 where !alerts.isHittable { app.swipeUp() }
        XCTAssertTrue(alerts.waitForExistence(timeout:5));alerts.tap()
        for title in ["Pre-kickoff reminder","Unavailable starters","Incomplete lineup"] {
            XCTAssertEqual(app.switches[title].value as? String,"0")
        }
        capture(app,"Game day — opt-in lineup notification options")
    }
    @MainActor func testReceivingTouchdownVisibleInMatchupAndFullBox() {
        receivingTouchdown()
    }
    @MainActor func testReceivingTouchdownVisibleAtLargestTextSize() {
        receivingTouchdown(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }
    @MainActor private func receivingTouchdown(arguments: [String] = []) {
        let app = start(arguments: ["--nfl-scoring-preview"] + arguments)
        app.buttons["matchup-0001-0008"].tap()
        let receiver = app.buttons["matchup-player-0001-starter-6-away"]
        var visible = CGRect.null
        for _ in 0..<30 {
            let top = app.segmentedControls["matchup-view-mode"].frame.maxY + 12
            let bottom = app.tabBars.firstMatch.frame.minY - 12
            let viewport = CGRect(x: 0, y: top, width: app.frame.width, height: bottom - top)
            visible = receiver.frame.intersection(viewport)
            if !visible.isNull && visible.height >= 44 { break }
            let up = receiver.frame.midY > viewport.midY
            let from = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: viewport.midX, dy: top + viewport.height * (up ? 0.8 : 0.2)))
            let to = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: viewport.midX, dy: top + viewport.height * (up ? 0.2 : 0.8)))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        XCTAssertFalse(visible.isNull)
        XCTAssertGreaterThanOrEqual(visible.height, 44)
        guard !visible.isNull, visible.height >= 44 else { capture(app, "NFL — player scrolling failed"); return }
        let scoringLine = NSPredicate(format: "label CONTAINS %@", "2 rec · 23 rec yd · 1 rec TD")
        expectation(for: scoringLine, evaluatedWith: receiver)
        waitForExpectations(timeout: 8)
        capture(app, "NFL — receiving touchdown visible in compact matchup")
        // Large text can make a row taller than the visible scroll area.
        // Tap its visible portion, not a center point covered by the pinned header.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
        XCTAssertTrue(app.segmentedControls["player-scoring-segments"].waitForExistence(timeout: 5))
        let touchdown = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Receiving TDs")).firstMatch
        for _ in 0..<5 where !touchdown.isHittable { app.swipeUp() }
        XCTAssertTrue(touchdown.waitForExistence(timeout: 5))
        capture(app, "NFL — receiving touchdown retained in full box")
    }

    @MainActor func testNFLBoxScoreAppearsInMatchupAndPlayerWeek() {
        let app = start(arguments: ["--nfl-scoring-preview"])
        app.buttons["matchup-0001-0008"].tap()
        let player = app.buttons["matchup-player-0001-starter-0-away"]
        XCTAssertTrue(player.waitForExistence(timeout: 8))
        let enriched = NSPredicate(format: "label CONTAINS %@", "311 pass yd")
        expectation(for: enriched, evaluatedWith: player)
        waitForExpectations(timeout: 8)
        capture(app, "NFL — matchup player summary and actual quarter")
        player.tap()
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "NFL player accessibility tree"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "311")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "24/31")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Passing TDs")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Q3 04:32")).firstMatch.exists)
        capture(app, "NFL — full player passing and rushing box score")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(player.waitForExistence(timeout: 5))
    }

    @MainActor func testMatchupAlignsTeamColumnsAndShowsLiveEstimate() {
        let app = start()
        app.buttons["matchup-0001-0008"].tap()
        let awayOwner = app.staticTexts["matchup-owner-0001"]
        let homeOwner = app.staticTexts["matchup-owner-0008"]
        let awayRecord = app.staticTexts["matchup-record-0001"]
        let homeRecord = app.staticTexts["matchup-record-0008"]
        XCTAssertTrue(awayOwner.waitForExistence(timeout: 5))
        XCTAssertTrue(homeOwner.exists && awayRecord.exists && homeRecord.exists)
        XCTAssertEqual(awayOwner.frame.minY, homeOwner.frame.minY, accuracy: 1)
        XCTAssertEqual(awayRecord.frame.minY, homeRecord.frame.minY, accuracy: 1)
        XCTAssertEqual(awayOwner.frame.minX, awayRecord.frame.minX, accuracy: 1)
        XCTAssertEqual(homeOwner.frame.maxX, homeRecord.frame.maxX, accuracy: 1)
        let awayPoints = app.descendants(matching: .any)["hero-metrics-0001"].firstMatch
        let homePoints = app.descendants(matching: .any)["hero-metrics-0008"].firstMatch
        XCTAssertEqual(awayPoints.frame.minY, homePoints.frame.minY, accuracy: 1)
        XCTAssertLessThan(awayPoints.frame.maxX, homePoints.frame.minX)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Estimated final score")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Leading by")).firstMatch.exists)
        capture(app, "Matchup — aligned team columns and live estimates")
    }

    @MainActor func testLivePlayerDefaultsToWeekAndCanSwitchToCard() {
        let app = start()
        app.buttons["matchup-0001-0008"].tap()
        let player = app.buttons["matchup-player-0001-starter-0-away"]
        XCTAssertTrue(player.waitForExistence(timeout: 5)); player.tap()
        XCTAssertTrue(app.segmentedControls["player-scoring-segments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Week 1"].isSelected)
        XCTAssertTrue(app.staticTexts["player-game-stats"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["player-week-points"].firstMatch.exists)
        capture(app, "Scoring — active player's week points and stats")
        app.segmentedControls.buttons["Player"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["player-detail-0001-starter-0"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["player-game-stats"].exists)
        app.segmentedControls.buttons["Week 1"].tap()
        XCTAssertTrue(app.staticTexts["player-game-stats"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Week 1 Matchup"].waitForExistence(timeout: 3))
    }

    @MainActor func testPregamePlayerOpensCardWithoutSegments() {
        let app = start()
        let matchup = app.buttons["matchup-0003-0007"]
        for _ in 0..<6 where !matchup.isHittable { app.swipeUp() }
        matchup.tap()
        // DAL's synthetic NFL game is already live elsewhere in the league.
        // GB's game is consistently upcoming in both scoring and schedule data.
        let player = app.buttons["matchup-player-0003-starter-1-away"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        for _ in 0..<8 where !player.isHittable { app.swipeUp() }
        XCTAssertTrue(player.label.contains("pregame projection"))
        player.tap()
        XCTAssertTrue(app.descendants(matching: .any)["player-detail-0003-starter-1"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.segmentedControls["player-scoring-segments"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Week 1 Matchup"].waitForExistence(timeout: 3))
    }

    @MainActor func testFinalPlayerOffersWeekAndMissingStatsFallback() {
        let app = start(arguments: ["--synthetic-final-game"])
        let matchup = app.buttons["matchup-0004-0009"]
        for _ in 0..<8 where !matchup.isHittable { app.swipeUp() }
        matchup.tap()
        let player = app.buttons["matchup-player-0004-starter-0-away"]
        XCTAssertTrue(player.waitForExistence(timeout: 5)); player.tap()
        XCTAssertTrue(app.segmentedControls["player-scoring-segments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["player-game-stats-unavailable"].exists)
        capture(app, "Scoring — final player and missing stat breakdown")
    }

    @MainActor func testRecentChangesAreSeparateFromRefreshAndProjection() {
        let app = start(arguments: ["--synthetic-scoring-change"])
        capture(app, "Scoring — aligned score blocks with change badges")
        let recent = app.descendants(matching: .any)["recent-scoring-changes"].firstMatch
        revealControl(recent, in: app)
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        recent.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "→")).firstMatch.waitForExistence(timeout: 3))
        capture(app, "Scoring — recent changes and signed badges")
    }

    @MainActor func testCollapsedBenchPreviewsBothTotals() {
        let app = start()
        app.buttons["matchup-0001-0008"].tap()
        let summary = app.descendants(matching: .any)["bench-score-summary"].firstMatch
        for _ in 0..<10 where !summary.isHittable { app.swipeUp() }
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        for team in ["0001", "0008"] {
            let total = app.descendants(matching: .any)["bench-total-\(team)"].firstMatch
            XCTAssertTrue(total.exists)
            XCTAssertTrue(total.label.contains("bench points"))
            XCTAssertFalse(total.label.contains("not fully reported"))
        }
        XCTAssertFalse(app.staticTexts["Bench points do not count toward the matchup total"].exists)
        capture(app, "Scoring — collapsed bench totals")
        let toggle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bench scoring")).firstMatch
        XCTAssertTrue(toggle.isHittable); toggle.tap()
        XCTAssertFalse(summary.exists)
        XCTAssertTrue(app.buttons["matchup-player-0001-bench-0-away"].waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
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
