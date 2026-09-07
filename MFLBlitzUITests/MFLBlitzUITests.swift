import XCTest

final class MFLBlitzUITests: XCTestCase {
    @MainActor
    func testLineupProjectionMarginUpdatesWithDraftAndStatusSitsBelowScore() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-current-lineup"]
        app.launch(); enterPreview(in: app)
        app.tabBars.buttons["Lineup"].firstMatch.tap()
        let projection = app.descendants(matching: .any)["lineup-summary-projection"].firstMatch
        let margin = app.descendants(matching: .any)["lineup-projected-margin"].firstMatch
        let status = app.descendants(matching: .any)["lineup-summary-status"].firstMatch
        let lock = app.descendants(matching: .any)["lineup-lock-message"].firstMatch
        XCTAssertTrue(margin.waitForExistence(timeout: 5))
        XCTAssertEqual(margin.label, "Projected 8.5 points ahead of GPT 5.0 now available")
        XCTAssertEqual(status.label, "Current lineup")
        XCTAssertGreaterThan(status.frame.minY, projection.frame.maxY)
        XCTAssertLessThan(abs(status.frame.midY - lock.frame.midY), 2)
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "Lineup — projection ahead and relocated status"; initial.lifetime = .keepAlways; add(initial)
        app.buttons["lineup-replace-12620"].tap()
        let kyler = app.buttons["lineup-replacement-14056"]
        XCTAssertTrue(kyler.waitForExistence(timeout: 3)); kyler.tap()
        XCTAssertTrue(app.buttons["Review & submit lineup"].waitForExistence(timeout: 3))
        XCTAssertEqual(margin.label, "Projected 6.7 points ahead of GPT 5.0 now available")
        XCTAssertEqual(status.label, "Unsaved changes")
        let edited = XCTAttachment(screenshot: app.screenshot())
        edited.name = "Lineup — edited projection margin"; edited.lifetime = .keepAlways; add(edited)
        let jacobs = app.buttons["lineup-replace-14073"]
        for _ in 0..<5 where !jacobs.isHittable { app.swipeUp() }
        XCTAssertTrue(jacobs.isHittable); jacobs.tap()
        let allgeier = app.buttons["lineup-replacement-15712"]
        XCTAssertTrue(allgeier.waitForExistence(timeout: 3)); allgeier.tap()
        XCTAssertTrue(app.buttons["Review & submit lineup"].waitForExistence(timeout: 3))
        for _ in 0..<5 where !margin.isHittable { app.swipeDown() }
        XCTAssertEqual(margin.label, "Projected 3.2 points behind GPT 5.0 now available")
        let trailing = XCTAttachment(screenshot: app.screenshot())
        trailing.name = "Lineup — negative projected margin"; trailing.lifetime = .keepAlways; add(trailing)
        // No submit: synthetic draft changes alone update the comparison.
    }

    @MainActor
    func testLineupProjectionCardAtLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-current-lineup", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); enterPreview(in: app)
        app.tabBars.buttons["Lineup"].firstMatch.tap()
        let projection = app.descendants(matching: .any)["lineup-summary-projection"].firstMatch
        let margin = app.descendants(matching: .any)["lineup-projected-margin"].firstMatch
        let status = app.descendants(matching: .any)["lineup-summary-status"].firstMatch
        let lock = app.descendants(matching: .any)["lineup-lock-message"].firstMatch
        XCTAssertTrue(margin.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(margin.frame.minY, projection.frame.maxY)
        XCTAssertGreaterThan(status.frame.minY, lock.frame.maxY)
        for element in [projection, margin, status, lock] {
            XCTAssertGreaterThanOrEqual(element.frame.minX, 0)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
        }
        let distance = max(0, projection.frame.minY - app.navigationBars.firstMatch.frame.maxY - 40)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let finish = start.withOffset(CGVector(dx: 0, dy: -min(distance, app.frame.height * 0.5)))
        start.press(forDuration: 0.1, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.2)
        let metrics = XCTAttachment(screenshot: app.screenshot())
        metrics.name = "Lineup — largest text projection and full opponent"; metrics.lifetime = .keepAlways; add(metrics)
        app.swipeUp()
        let large = XCTAttachment(screenshot: app.screenshot())
        large.name = "Lineup — projection card at largest text"; large.lifetime = .keepAlways; add(large)
    }

    @MainActor
    func testStandingsSummaryScopesAndConfirmedTies() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-ranked-standings"]
        app.launch(); enterPreview(in: app)
        app.tabBars.buttons["My Team"].firstMatch.tap()
        let summary = app.buttons["team-standing-0001"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "1–1 · 1st in Warner")
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "My Team — compact numeric standing"; home.lifetime = .keepAlways; add(home)
        summary.tap()
        XCTAssertTrue(app.navigationBars["Standings"].waitForExistence(timeout: 5))
        let owner = app.descendants(matching: .any)["standing-0001"].firstMatch
        XCTAssertTrue(owner.waitForExistence(timeout: 5))
        XCTAssertTrue(owner.label.contains("Division rank 1"))
        let tied = app.descendants(matching: .any)["standing-0008"].firstMatch
        XCTAssertTrue(tied.label.contains("Tied at Division rank 2"))
        let division = XCTAttachment(screenshot: app.screenshot())
        division.name = "Standings — division ranks and confirmed tie"; division.lifetime = .keepAlways; add(division)
        app.segmentedControls["standings-scope"].buttons["Overall"].tap()
        XCTAssertTrue(owner.label.contains("League rank 5"))
        owner.tap()
        XCTAssertTrue(app.buttons["team-standing-0001"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["team-standing-0001"].label, "1–1 · 1st in Warner")
    }

    @MainActor
    func testStandingsWithoutDivisionsUsesLeagueNameAtLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-ranked-standings", "--preview-no-divisions",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); enterPreview(in: app)
        app.tabBars.buttons["My Team"].firstMatch.tap()
        let summary = app.buttons["team-standing-0001"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "1–1 · 5th in Champion Hall")
        XCTAssertTrue(summary.isHittable)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "My Team — largest text league standing"; image.lifetime = .keepAlways; add(image)
        summary.tap()
        XCTAssertTrue(app.navigationBars["Standings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["standings-scope"].exists)
        let owner = app.descendants(matching: .any)["standing-0001"].firstMatch
        XCTAssertTrue(owner.waitForExistence(timeout: 5))
        XCTAssertTrue(owner.label.contains("League rank 5"))
        let standings = XCTAttachment(screenshot: app.screenshot())
        standings.name = "Standings — largest text readable row"; standings.lifetime = .keepAlways; add(standings)
    }

    @MainActor
    private func enterPreview(in app: XCUIApplication) {
        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let alert = app.alerts["Something went wrong"]
        if alert.exists { alert.buttons["OK"].tap() }
        preview.tap()
        XCTAssertTrue(app.tabBars.buttons["My Team"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func openTool(_ id: String, title: String, in app: XCUIApplication) {
        app.tabBars.buttons["My Team"].firstMatch.tap()
        if app.navigationBars[title].exists { return }
        for _ in 0..<5 where !app.navigationBars["My Team"].exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
        let entry = app.buttons["my-team-\(id)"]
        for _ in 0..<12 {
            if entry.exists && entry.isHittable &&
                entry.frame.minY >= app.navigationBars.firstMatch.frame.maxY &&
                entry.frame.maxY <= app.tabBars.firstMatch.frame.minY { break }
            if entry.exists && entry.frame.minY < app.navigationBars.firstMatch.frame.maxY {
                app.swipeDown()
            } else { app.swipeUp() }
        }
        XCTAssertTrue(entry.isHittable, "The \(title) shortcut must be accessible")
        entry.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCurrentScheduleMatchupKeepsIndependentWeekAndOpensPlayer() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        let week = app.buttons["week-picker"]
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        app.buttons["Week 2"].tap()
        app.tabBars.buttons["My Team"].firstMatch.tap()
        app.buttons["my-team-schedule"].tap()
        let weekOne = app.descendants(matching: .any).matching(identifier: "schedule-week-1").firstMatch
        let matchup = weekOne.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "schedule-matchup-")).firstMatch
        XCTAssertTrue(matchup.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Updated just now"].exists)
        let timeline = XCTAttachment(screenshot: app.screenshot())
        timeline.name = "My Team schedule — concise freshness"; timeline.lifetime = .keepAlways; add(timeline)
        matchup.tap()
        XCTAssertTrue(app.navigationBars["Week 1 Matchup"].waitForExistence(timeout: 5))
        let starters = app.staticTexts["Starting lineups"]
        XCTAssertTrue(starters.waitForExistence(timeout: 5))
        let player = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "matchup-player-")).firstMatch
        for _ in 0..<8 where !player.isHittable { app.swipeUp() }
        XCTAssertTrue(player.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Schedule matchup — independent Week 1 scoring"; screenshot.lifetime = .keepAlways; add(screenshot)
        player.tap()
        XCTAssertTrue(app.buttons["player-owner-0001"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["That preview player is unavailable."].exists)
        app.tabBars.buttons["Scores"].firstMatch.tap()
        XCTAssertEqual(app.buttons["week-picker"].label, "Week 2")
        app.tabBars.buttons["Lineup"].firstMatch.tap()
        XCTAssertEqual(app.buttons["week-picker"].label, "Week 2")
    }

    @MainActor
    func testMyTeamRosterPlayerAndFutureSchedulePreserveLineupDraft() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        app.tabBars.buttons["Lineup"].firstMatch.tap()
        let quarterback = app.buttons["lineup-replace-12620"]
        XCTAssertTrue(quarterback.waitForExistence(timeout: 5))
        quarterback.tap()
        app.buttons["lineup-replacement-14056"].tap()
        XCTAssertTrue(app.buttons["Review & submit lineup"].waitForExistence(timeout: 3))

        app.tabBars.buttons["My Team"].firstMatch.tap()
        let scheduleLink = app.buttons["my-team-schedule"]
        XCTAssertTrue(scheduleLink.waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["team-section-picker"].exists)
        XCTAssertFalse(app.buttons["Manage roster"].exists)
        XCTAssertFalse(app.buttons["my-team-transactions"].exists)
        let ids = ["schedule", "adds-drops", "trades", "watchlist", "injured-reserve", "activity"]
        let shortcuts = ids.map { app.buttons["my-team-\($0)"] }
        for shortcut in shortcuts {
            XCTAssertTrue(shortcut.isHittable)
            XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44)
        }
        for row in 0..<3 {
            XCTAssertEqual(shortcuts[row * 2].frame.midY, shortcuts[row * 2 + 1].frame.midY, accuracy: 2)
            XCTAssertLessThan(shortcuts[row * 2].frame.maxX, shortcuts[row * 2 + 1].frame.minX)
            if row > 0 { XCTAssertGreaterThan(shortcuts[row * 2].frame.minY, shortcuts[(row - 1) * 2].frame.maxY) }
        }
        let header = app.buttons["team-standing-0001"]
        XCTAssertEqual(header.label, "0–0 · Warner")
        XCTAssertFalse(header.label.contains("League standing"))
        XCTAssertFalse(app.staticTexts["Current roster · Week 1 assignments"].exists)
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "My Team — six direct shortcuts and official standing"; home.lifetime = .keepAlways; add(home)
        let rosterPlayer = app.buttons["roster-player-12620"]
        for _ in 0..<5 where !rosterPlayer.isHittable { app.swipeUp() }
        XCTAssertTrue(rosterPlayer.isHittable)
        let hub = XCTAttachment(screenshot: app.screenshot())
        hub.name = "My Team — position roster below shortcuts"; hub.lifetime = .keepAlways; add(hub)
        rosterPlayer.tap()
        XCTAssertTrue(app.navigationBars["Dak Prescott"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["player-owner-0001"].waitForExistence(timeout: 5))
        let player = XCTAttachment(screenshot: app.screenshot())
        player.name = "Player detail — league ownership and matching-week projection"; player.lifetime = .keepAlways; add(player)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<8 where !scheduleLink.isHittable { app.swipeDown() }
        scheduleLink.tap()
        let weekTwo = app.descendants(matching: .any).matching(identifier: "schedule-week-2").firstMatch
        let matchup = weekTwo.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "schedule-matchup-")).firstMatch
        for _ in 0..<6 where !matchup.isHittable { app.swipeUp() }
        XCTAssertTrue(matchup.isHittable)
        let timeline = XCTAttachment(screenshot: app.screenshot())
        timeline.name = "My Team — rest-of-season schedule"; timeline.lifetime = .keepAlways; add(timeline)
        matchup.tap()
        XCTAssertTrue(app.navigationBars["Week 2 Matchup"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Upcoming"].exists)
        XCTAssertFalse(app.staticTexts["Starting lineups"].exists)
        let future = XCTAttachment(screenshot: app.screenshot())
        future.name = "Future matchup — no invented live scores"; future.lifetime = .keepAlways; add(future)
        app.tabBars.buttons["Lineup"].firstMatch.tap()
        XCTAssertEqual(app.buttons["week-picker"].label, "Week 1")
        XCTAssertTrue(app.buttons["Review & submit lineup"].exists)
        XCTAssertTrue(app.buttons["lineup-replace-14056"].exists)
        app.tabBars.buttons["Scores"].firstMatch.tap()
        XCTAssertEqual(app.buttons["week-picker"].label, "Week 1")
    }

    @MainActor
    func testStandingsTeamAndLeagueScheduleNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Dark"]
        app.launch()
        enterPreview(in: app)
        app.tabBars.buttons["Standings"].firstMatch.tap()
        let team = app.buttons["standings-team-0004"]
        XCTAssertTrue(team.waitForExistence(timeout: 5))
        let standings = XCTAttachment(screenshot: app.screenshot())
        standings.name = "Standings — tappable team rows"; standings.lifetime = .keepAlways; add(standings)
        team.tap()
        XCTAssertTrue(app.segmentedControls["team-section-picker"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["my-team-adds-drops"].exists)
        XCTAssertFalse(app.buttons["my-team-trades"].exists)
        app.segmentedControls.buttons["Schedule"].tap()
        let league = app.buttons["open-league-schedule"]
        XCTAssertTrue(league.waitForExistence(timeout: 5))
        league.tap()
        XCTAssertTrue(app.navigationBars["Season schedule"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["schedule-team-picker"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "League season schedule — all teams"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func testDecliningPreviewOfferOpensDeclineReviewFirst() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        openTool("trades", title: "Trades", in: app)
        let incoming = app.buttons["trade-offer-demo-incoming"]
        XCTAssertTrue(incoming.waitForExistence(timeout: 5))
        incoming.tap()
        let decline = app.buttons["trade-review-decline"]
        for _ in 0..<4 where !decline.isHittable { app.swipeUp() }
        decline.tap() // Must work without opening acceptance first.
        XCTAssertTrue(app.navigationBars["Decline offer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["Message to the sender"].exists)
        let confirm = app.buttons["trade-confirm-response"]
        for _ in 0..<4 where !confirm.isHittable { app.swipeUp() }
        XCTAssertEqual(confirm.label, "Decline offer")
        XCTAssertFalse(app.navigationBars["Accept trade"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Decline offer — correct first-tap review"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Cancel"].tap()
        app.buttons["Draft counteroffer"].tap()
        XCTAssertTrue(app.navigationBars["Counteroffer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["trade-save-draft"].isEnabled)
        app.buttons["trade-cancel-draft"].tap()
        XCTAssertTrue(app.navigationBars["Trade offer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Draft counteroffer"].isEnabled)
        app.buttons["Done"].tap()
        XCTAssertTrue(incoming.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["trade-new"].exists) // Cancel didn't leave a counteroffer draft.
    }

    @MainActor
    func testTradeActionStaysVisibleWithLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        let preview = app.buttons["Preview Champion Hall"]
        for _ in 0..<6 where !preview.isHittable { app.swipeUp() }
        preview.tap()
        openTool("trades", title: "Trades", in: app)
        let create = app.buttons["trade-new"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(create.isHittable && create.isEnabled)
        XCTAssertEqual(create.label, "Create trade")
        XCTAssertGreaterThan(create.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(create.isHittable)
        XCTAssertLessThan(create.frame.maxY, app.tabBars.firstMatch.frame.minY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Trade inbox — large text and pinned action"; screenshot.lifetime = .keepAlways; add(screenshot)
        create.tap()
        XCTAssertTrue(app.navigationBars["Build a trade"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["trade-save-draft"].isEnabled)
        app.buttons["trade-cancel-draft"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 3))
    }

    @MainActor
    func testEmptyTradeInboxMakesCreatingAndResumingObvious() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-empty-trades"]
        app.launch()
        enterPreview(in: app)
        openTool("trades", title: "Trades", in: app)
        let create = app.buttons["trade-new"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(create.isEnabled && create.isHittable)
        XCTAssertEqual(create.label, "Create trade")
        XCTAssertGreaterThan(create.frame.width, app.frame.width * 0.8)
        XCTAssertGreaterThanOrEqual(create.frame.height, 44)
        XCTAssertGreaterThan(create.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThan(create.frame.minY - app.navigationBars.firstMatch.frame.maxY, 24)
        XCTAssertTrue(app.staticTexts["No active trades"].exists)
        XCTAssertFalse(app.staticTexts["No incoming offers"].exists)
        XCTAssertFalse(app.staticTexts["No sent offers"].exists)
        let externalLink = app.descendants(matching: .any).matching(identifier: "trade-open-mfl").firstMatch
        XCTAssertFalse(externalLink.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Empty trade inbox — prominent Create trade"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["trade-options"].tap()
        let menuScreenshot = XCTAttachment(screenshot: app.screenshot())
        menuScreenshot.name = "Trade options — secondary MFL link"; menuScreenshot.lifetime = .keepAlways; add(menuScreenshot)
        let menuTree = XCTAttachment(string: app.debugDescription)
        menuTree.name = "Trade options accessibility"; menuTree.lifetime = .keepAlways; add(menuTree)
        XCTAssertTrue(externalLink.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Refresh offers"].exists)
        // Refresh the offline inbox without opening the external site.
        app.buttons["Refresh offers"].tap()
        let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: create)
        wait(for: [enabled], timeout: 3)
        create.tap()
        XCTAssertTrue(app.navigationBars["Build a trade"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["trade-save-draft"].isEnabled)
        XCTAssertTrue(app.buttons["trade-cancel-draft"].isHittable)
        let blank = XCTAttachment(screenshot: app.screenshot())
        blank.name = "Blank trade — Cancel and disabled Save & close"; blank.lifetime = .keepAlways; add(blank)
        app.buttons["trade-cancel-draft"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["trade-resume-draft"].exists)
        create.tap()
        app.buttons["trade-partner"].tap()
        app.buttons["Route Runners"].tap()
        XCTAssertTrue(app.buttons["trade-save-draft"].isEnabled)
        app.buttons["Save & close"].tap()
        let resume = app.buttons["trade-resume-draft"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        XCTAssertEqual(resume.label, "Resume trade")
        XCTAssertTrue(resume.isHittable)
        resume.tap()
        XCTAssertTrue(app.navigationBars["Build a trade"].waitForExistence(timeout: 3))
        app.buttons["Save & close"].tap()
        app.buttons["trade-options"].tap()
        app.buttons["Discard draft"].tap()
        XCTAssertTrue(app.staticTexts["Sent offers won’t change."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.alerts["Discard trade draft?"].exists)
        let confirmation = XCTAttachment(screenshot: app.screenshot())
        confirmation.name = "Discard draft — centered confirmation"; confirmation.lifetime = .keepAlways; add(confirmation)
        app.alerts.buttons["Cancel"].tap()
        // On iOS 18 the alert can still obscure the inbox after tap() returns.
        // Await the actual interactive state; do not race the dismissal animation.
        let returnedToInbox = expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: resume)
        wait(for: [returnedToInbox], timeout: 5)
        XCTAssertFalse(app.alerts["Discard trade draft?"].exists)
        XCTAssertTrue(resume.isHittable)
        app.buttons["trade-options"].tap()
        app.buttons["Discard draft"].tap()
        XCTAssertTrue(app.alerts["Discard trade draft?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Discard draft"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No active trades"].exists)
        // No send or response actions are exercised against a live league.
    }

    @MainActor
    func testScoresToolbarKeepsWeekAndSettingsInCorners() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        let settings = app.navigationBars.buttons["scores-settings"]
        let week = app.navigationBars.buttons["week-picker"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertTrue(week.isHittable)
        XCTAssertEqual(week.label, "Week 1")
        XCTAssertLessThan(settings.frame.midX, app.frame.width * 0.25)
        XCTAssertGreaterThan(week.frame.midX, app.frame.width * 0.6)
        XCTAssertEqual(app.buttons.matching(identifier: "week-picker").count, 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Scores — Settings left, Week right"; screenshot.lifetime = .keepAlways; add(screenshot)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        week.tap()
        app.buttons["Week 2"].tap()
        XCTAssertEqual(week.label, "Week 2")
    }

    @MainActor
    func testLineupWeekControlShowsSelectedWeek() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        app.tabBars.buttons["Lineup"].firstMatch.tap()
        let week = app.navigationBars.buttons["week-picker"]
        XCTAssertTrue(week.waitForExistence(timeout: 3))
        XCTAssertEqual(week.label, "Week 1")
        XCTAssertGreaterThan(week.frame.width, 75) // Not an icon-only toolbar button.
        XCTAssertTrue(week.isHittable)
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "Lineup toolbar — Week 1 visible"; initial.lifetime = .keepAlways; add(initial)
        for value in [2, 18] {
            // UIKit sizes native toolbar menus. Exercise both visible parts:
            // tapping the calendar and tapping the week title must open it.
            week.coordinate(withNormalizedOffset: CGVector(dx: value == 2 ? 0.2 : 0.8, dy: 0.5)).tap()
            XCTAssertTrue(app.buttons["Week \(value)"].waitForExistence(timeout: 3))
            app.buttons["Week \(value)"].tap()
            XCTAssertTrue(week.waitForExistence(timeout: 3))
            XCTAssertEqual(week.label, "Week \(value)")
            XCTAssertGreaterThan(week.frame.width, 75)
        }
        let changed = XCTAttachment(screenshot: app.screenshot())
        changed.name = "Lineup toolbar — Week 18 visible"; changed.lifetime = .keepAlways; add(changed)
        app.tabBars.buttons["Scores"].firstMatch.tap()
        XCTAssertEqual(app.buttons["week-picker"].label, "Week 18")
    }

    @MainActor
    func testStarterCanSwapBetweenRunningBackAndFlexWithoutChangingMembership() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        app.tabBars.buttons["Lineup"].firstMatch.tap()
        let rb = app.buttons["lineup-replace-14073"]
        for _ in 0..<10 where !rb.isHittable { app.swipeUp() }
        rb.tap()
        XCTAssertTrue(app.navigationBars["Replace RB"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Slot swaps save on this device."].exists)
        XCTAssertFalse(app.staticTexts["Review & submit to save new starters."].exists)
        XCTAssertTrue(app.buttons["lineup-replacement-15712"].exists) // Bench RB.
        let flex = app.buttons["lineup-replacement-15256"]
        for _ in 0..<8 where !flex.isHittable { app.swipeUp() }
        XCTAssertTrue(flex.isHittable)
        XCTAssertTrue(flex.label.contains("FLEX → RB"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "RB replacements — bench and FLEX starters"; screenshot.lifetime = .keepAlways; add(screenshot)
        flex.tap()
        XCTAssertTrue(app.navigationBars["Lineup"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Review & submit lineup"].exists) // Same starters, only local slots change.
        let moved = app.buttons["lineup-replace-15256"]
        for _ in 0..<8 where !moved.isHittable { app.swipeDown() }
        moved.tap()
        XCTAssertTrue(app.navigationBars["Replace RB"].waitForExistence(timeout: 3))
        let reverse = app.buttons["lineup-replacement-14073"]
        for _ in 0..<8 where !reverse.isHittable { app.swipeUp() }
        XCTAssertTrue(reverse.label.contains("FLEX → RB"))
        reverse.tap()
        XCTAssertTrue(app.navigationBars["Lineup"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Review & submit lineup"].exists)
    }

    @MainActor
    func testCrossPositionStarterMoveCanCancelThenFillWithoutSubmitting() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        app.tabBars.buttons["Lineup"].firstMatch.tap()
        let flex = app.buttons["lineup-replace-15256"]
        for _ in 0..<10 where !flex.isHittable { app.swipeUp() }
        flex.tap()
        let wr = app.buttons["lineup-replacement-15284"]
        for _ in 0..<10 where !wr.isHittable { app.swipeUp() }
        XCTAssertTrue(wr.isHittable)
        XCTAssertTrue(wr.label.contains("WR → FLEX"))
        wr.tap()
        XCTAssertTrue(app.navigationBars["Fill WR"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Choose to apply to your draft."].exists)
        XCTAssertTrue(app.staticTexts["Jaylen Waddle → FLEX"].exists)
        XCTAssertFalse(app.staticTexts["Choose a player for Jaylen Waddle’s WR slot."].exists)
        XCTAssertTrue(app.buttons["lineup-fill-15757"].exists) // Bench WR.
        XCTAssertTrue(app.buttons["lineup-fill-16080"].exists) // WR currently in the other FLEX slot.
        XCTAssertTrue(app.buttons["lineup-fill-15757"].label.contains("Javonte Williams moves to the bench"))
        XCTAssertTrue(app.buttons["lineup-fill-16080"].label.contains("Javonte Williams moves to the other FLEX slot"))
        XCTAssertFalse(app.buttons["lineup-fill-15712"].exists) // Cannot put an RB in WR.
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Cross-position move — fill WR before applying"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Lineup"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Review & submit lineup"].exists)
        for _ in 0..<10 where !flex.isHittable { app.swipeUp() }
        flex.tap()
        for _ in 0..<10 where !wr.isHittable { app.swipeUp() }
        wr.tap()
        app.buttons["lineup-fill-15757"].tap()
        XCTAssertTrue(app.navigationBars["Lineup"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Review & submit lineup"].waitForExistence(timeout: 3))
        app.buttons["Review & submit lineup"].tap()
        XCTAssertTrue(app.navigationBars["Review lineup"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["lineup-confirm-submit"].isEnabled)
        app.buttons["Cancel"].tap() // Offline draft only; no league submissions.
    }

    @MainActor
    func testLineupPlayIconKeepsLabelAndSelection() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        let lineup = app.tabBars.buttons["Lineup"].firstMatch
        XCTAssertTrue(lineup.waitForExistence(timeout: 3))
        XCTAssertFalse(lineup.isSelected)
        XCTAssertEqual(lineup.label, "Lineup")
        let unselected = XCTAttachment(screenshot: app.tabBars.firstMatch.screenshot())
        unselected.name = "Play diagram — unselected"; unselected.lifetime = .keepAlways; add(unselected)
        lineup.tap()
        XCTAssertTrue(lineup.isSelected)
        XCTAssertTrue(app.navigationBars["Lineup"].waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(lineup.frame.width, 44)
        XCTAssertGreaterThanOrEqual(lineup.frame.height, 44)
        let selected = XCTAttachment(screenshot: app.tabBars.firstMatch.screenshot())
        selected.name = "Play diagram — selected"; selected.lifetime = .keepAlways; add(selected)
        app.tabBars.buttons["Scores"].firstMatch.tap()
        XCTAssertFalse(lineup.isSelected)
    }

    @MainActor
    func testTwoWeekManagerJourneyInOfflinePreview() throws {
        let app = XCUIApplication()
        app.launch()
        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        // Explicitly verify offline mode before exercising a final submit button.
        XCTAssertTrue(app.staticTexts["Preview mode. Changes stay on this device."].waitForExistence(timeout: 3))
        for week in 1...2 {
            app.tabBars.buttons["Lineup"].firstMatch.tap()
            if week == 2 {
                app.buttons["Week 1"].tap()
                app.buttons["Week 2"].tap()
            }
            let replace = app.buttons["lineup-replace-15256"]
            for _ in 0..<10 where !replace.isHittable { app.swipeUp() }
            XCTAssertTrue(replace.isHittable)
            replace.tap()
            XCTAssertTrue(app.navigationBars["Replace FLEX"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["lineup-replacement-starter-projection"].exists)
            app.buttons["lineup-replacement-15757"].tap()
            if week == 2 {
                XCTAssertTrue(app.staticTexts["Choose one bench tiebreaker before submitting changes"].firstMatch.exists)
                XCTAssertFalse(app.buttons["Review & submit lineup"].isEnabled)
                let tiebreaker = app.descendants(matching: .any).matching(identifier: "lineup-tiebreaker").firstMatch
                // A partially visible picker can report hittable underneath
                // the disabled sticky submit bar. Reveal the entire row first.
                let visibleBottom = app.buttons["Review & submit lineup"].frame.minY - 44
                for _ in 0..<10 {
                    if tiebreaker.exists && tiebreaker.isHittable && tiebreaker.frame.maxY < visibleBottom { break }
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                        .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
                }
                XCTAssertTrue(tiebreaker.isHittable)
                XCTAssertLessThan(tiebreaker.frame.maxY, visibleBottom)
                // On iOS 18 the menu's tappable value is trailing; the combined
                // accessibility frame also includes its noninteractive title.
                tiebreaker.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                let choice = app.buttons["Kyler Murray · QB"]
                XCTAssertTrue(choice.waitForExistence(timeout: 5))
                choice.tap()
            }
            app.buttons["Review & submit lineup"].tap()
            let submit = app.buttons["lineup-confirm-submit"]
            XCTAssertTrue(submit.waitForExistence(timeout: 3))
            XCTAssertTrue(submit.isEnabled && submit.isHittable)
            let review = XCTAttachment(screenshot: app.screenshot())
            review.name = "Synthetic manager Week \(week) lineup review"; review.lifetime = .keepAlways; add(review)
            submit.tap()
            XCTAssertTrue(app.alerts["All set"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Demo lineup saved on this device."].exists)
            app.alerts.buttons["OK"].tap()
            XCTAssertFalse(app.buttons["Review & submit lineup"].exists)

            app.tabBars.buttons["Scores"].firstMatch.tap()
            let matchup = app.buttons["matchup-0001-0008"]
            XCTAssertTrue(matchup.waitForExistence(timeout: 3))
            matchup.tap()
            XCTAssertTrue(app.navigationBars["Week \(week) Matchup"].waitForExistence(timeout: 3))
            let flex = app.staticTexts["position-FLEX"]
            for _ in 0..<12 where !flex.isHittable { app.swipeUp() }
            XCTAssertTrue(flex.isHittable)
            app.navigationBars.buttons.firstMatch.tap()

            openTool("adds-drops", title: "Adds / Drops", in: app)
            XCTAssertTrue(app.textFields["waiver-search"].waitForExistence(timeout: 3))
            openTool("trades", title: "Trades", in: app)
            XCTAssertTrue(app.buttons["trade-new"].waitForExistence(timeout: 3))
            openTool("activity", title: "League Activity", in: app)
            XCTAssertTrue(app.staticTexts["$3.00 bid"].waitForExistence(timeout: 3))
            app.tabBars.buttons["Standings"].firstMatch.tap()
            XCTAssertTrue(app.buttons["standings-order-info"].waitForExistence(timeout: 3))
            app.tabBars.buttons["Board"].firstMatch.tap()
            XCTAssertTrue(app.buttons["New thread"].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testFlexReplacementShowsLeagueEligiblePositions() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        app.tabBars.buttons["Lineup"].firstMatch.tap()
        let replace = app.buttons["lineup-replace-15256"]
        for _ in 0..<8 where !replace.isHittable { app.swipeUp() }
        XCTAssertTrue(replace.isHittable)
        replace.tap()
        XCTAssertTrue(app.navigationBars["Replace FLEX"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["lineup-replacement-15757"].exists) // WR
        XCTAssertTrue(app.buttons["lineup-replacement-15712"].exists) // RB
        XCTAssertTrue(app.buttons["lineup-replacement-16269"].exists) // TE
        XCTAssertFalse(app.buttons["lineup-replacement-14056"].exists) // QB not allowed here
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "League-aware FLEX replacement"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["lineup-replacement-15757"].tap()
        XCTAssertTrue(app.buttons["Review & submit lineup"].waitForExistence(timeout: 3))
        app.buttons["Review & submit lineup"].tap()
        XCTAssertTrue(app.navigationBars["Review lineup"].waitForExistence(timeout: 3))
        let confirm = app.buttons["lineup-confirm-submit"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertTrue(confirm.isHittable)
        let review = XCTAttachment(screenshot: app.screenshot())
        review.name = "Native lineup review modal"; review.lifetime = .keepAlways; add(review)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Review & submit lineup"].waitForExistence(timeout: 3))
        // Draft only: never submit an actual lineup in a UI regression test.
    }

    @MainActor
    func testAddsDropsSearchAndDirectActivityNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        openTool("adds-drops", title: "Adds / Drops", in: app)
        let sections = app.segmentedControls["adds-drops-sections"]
        let search = app.textFields["waiver-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(search.frame.minY, sections.frame.maxY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Adds and Drops — search below Available and My roster"; screenshot.lifetime = .keepAlways; add(screenshot)
        search.tap()
        search.typeText("test")
        sections.buttons["My roster"].tap()
        XCTAssertTrue(app.textFields["roster-search"].exists)
        XCTAssertFalse(search.exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        sections.buttons["Available"].tap()
        XCTAssertEqual(search.value as? String, "test")
        openTool("activity", title: "League Activity", in: app)
        XCTAssertTrue(app.switches["Trades only"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["$3.00 bid"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Braelon Allen"].exists)
        XCTAssertTrue(app.staticTexts["Jaylin Noel"].exists)
        XCTAssertFalse(app.textFields["waiver-search"].exists)
        XCTAssertFalse(app.buttons["trade-new"].exists)
        let activity = XCTAttachment(screenshot: app.screenshot())
        activity.name = "League Activity — independent destination"; activity.lifetime = .keepAlways; add(activity)
    }

    @MainActor
    func testAllSixShortcutsOpenDistinctDestinations() {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        let routes = [("schedule", "Schedule"), ("adds-drops", "Adds / Drops"), ("trades", "Trades"),
                      ("watchlist", "Watchlist"), ("injured-reserve", "Injured Reserve"), ("activity", "League Activity")]
        for (id, title) in routes {
            openTool(id, title: title, in: app)
            XCTAssertTrue(app.navigationBars[title].exists)
            XCTAssertFalse(app.buttons["Manage roster"].exists)
        }
    }

    @MainActor
    func testTransactionsReviewsIncomingOfferWithoutAccepting() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        openTool("trades", title: "Trades", in: app)
        let incoming = app.buttons["trade-offer-demo-incoming"]
        XCTAssertTrue(incoming.waitForExistence(timeout: 5))
        let create = app.buttons["trade-new"]
        XCTAssertTrue(create.isHittable)
        XCTAssertEqual(create.label, "Create trade")
        XCTAssertLessThan(create.frame.maxY, incoming.frame.minY)
        XCTAssertFalse(app.staticTexts["No active trades"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "trade-open-mfl").firstMatch.exists)
        let hub = XCTAttachment(screenshot: app.screenshot())
        hub.name = "Transactions trade inbox"; hub.lifetime = .keepAlways; add(hub)
        incoming.tap()
        XCTAssertTrue(app.navigationBars["Trade offer"].waitForExistence(timeout: 3))
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Received trade — full offer and response options"; detail.lifetime = .keepAlways; add(detail)
        let review = app.buttons["trade-review-accept"]
        for _ in 0..<4 where !review.isHittable { app.swipeUp() }
        review.tap()
        let confirm = app.buttons["trade-confirm-response"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertEqual(confirm.label, "Accept trade")
        XCTAssertTrue(app.staticTexts["You send"].exists || app.staticTexts["YOU SEND"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Review exact trade before acceptance"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(incoming.waitForExistence(timeout: 3))
        let outgoing = app.buttons["trade-offer-demo-sent"]
        for _ in 0..<4 where !outgoing.isHittable { app.swipeUp() }
        outgoing.tap()
        XCTAssertTrue(app.navigationBars["Trade offer"].waitForExistence(timeout: 3))
        let sent = XCTAttachment(screenshot: app.screenshot())
        sent.name = "Sent trade — full offer and withdraw option"; sent.lifetime = .keepAlways; add(sent)
        XCTAssertFalse(app.buttons["trade-review-accept"].exists)
        let withdraw = app.buttons["trade-review-withdraw"]
        for _ in 0..<4 where !withdraw.isHittable { app.swipeUp() }
        withdraw.tap()
        XCTAssertTrue(app.navigationBars["Withdraw offer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["trade-confirm-response"].exists)
        XCTAssertEqual(app.buttons["trade-confirm-response"].label, "Withdraw offer")
        let withdrawal = XCTAttachment(screenshot: app.screenshot())
        withdrawal.name = "Withdraw offer — correct first-tap review"; withdrawal.lifetime = .keepAlways; add(withdrawal)
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(outgoing.waitForExistence(timeout: 3)) // No offer changed.
    }

    @MainActor
    func testTradeDraftPersistsAndRequiresReview() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        openTool("trades", title: "Trades", in: app)
        let newTrade = app.buttons["trade-new"]
        XCTAssertTrue(newTrade.waitForExistence(timeout: 5))
        newTrade.tap()
        app.buttons["trade-partner"].tap()
        app.buttons["Route Runners"].tap()
        app.buttons["trade-choose-receive"].tap()
        app.buttons["trade-asset-demo-wr"].tap()
        let selectedAsset = XCTAttachment(screenshot: app.screenshot())
        selectedAsset.name = "Selected receiving asset"; selectedAsset.lifetime = .keepAlways; add(selectedAsset)
        XCTAssertTrue(app.buttons["trade-asset-demo-wr"].label.hasSuffix(", selected"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["CeeDee Lamb"].exists)
        app.buttons["trade-choose-send"].tap()
        let player = app.buttons["trade-asset-12620"]
        for _ in 0..<5 where !player.isHittable { app.swipeUp() }
        player.tap()
        XCTAssertTrue(player.label.hasSuffix(", selected"))
        app.buttons["trade-research-12620"].tap()
        XCTAssertTrue(app.buttons["player-watch-12620"].waitForExistence(timeout: 5))
        app.navigationBars["Dak Prescott"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Choose assets"].waitForExistence(timeout: 5))
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertTrue(player.label.hasSuffix(", selected"))
        app.buttons["Done"].tap()
        let beforeSaving = XCTAttachment(screenshot: app.screenshot())
        beforeSaving.name = "Trade draft before save"; beforeSaving.lifetime = .keepAlways; add(beforeSaving)
        app.buttons["Save & close"].tap()
        resumeTradeAfterDismissal(in: app)
        XCTAssertTrue(app.staticTexts["CeeDee Lamb"].exists)
        XCTAssertTrue(app.staticTexts["Dak Prescott"].exists)
        // Editing and canceling a resumed trade restores the saved terms.
        app.buttons["trade-partner"].tap()
        app.buttons["Croton Bug Eaters"].tap()
        app.buttons["trade-cancel-draft"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Keep editing"].tap()
        XCTAssertTrue(app.navigationBars["Build a trade"].exists)
        app.buttons["trade-cancel-draft"].tap()
        app.alerts.buttons["Discard changes"].tap()
        resumeTradeAfterDismissal(in: app)
        XCTAssertTrue(app.staticTexts["Route Runners"].exists)
        XCTAssertTrue(app.staticTexts["CeeDee Lamb"].exists)
        XCTAssertTrue(app.staticTexts["Dak Prescott"].exists)
        let review = app.buttons["trade-review-offer"]
        for _ in 0..<5 where !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(app.buttons["trade-send-offer"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Trade proposal final review"; screenshot.lifetime = .keepAlways; add(screenshot)
        // Deliberately do not press Send, even in the offline preview.
    }

    @MainActor
    private func resumeTradeAfterDismissal(in app: XCUIApplication) {
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["trade-cancel-draft"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        let resume = app.buttons["trade-resume-draft"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(app.buttons["trade-cancel-draft"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBoardDraftSurvivesClosingComposer() throws {
        let app = XCUIApplication()
        app.launch()
        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        let board = app.tabBars.buttons["Board"].firstMatch
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
        app.buttons["board-composer-close"].tap()
        XCTAssertTrue(app.alerts["Save draft?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Save draft"].tap()
        let resume = app.buttons["board-draft-new"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        let boardScreenshot = XCTAttachment(screenshot: app.screenshot())
        boardScreenshot.name = "Board — visible saved draft"; boardScreenshot.lifetime = .keepAlways; add(boardScreenshot)
        resume.tap()
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        XCTAssertEqual(subject.value as? String, "Week one test")
        XCTAssertEqual(body.value as? String, "A draft, not a league post.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Saved private board draft"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testBoardCloseEmptyKeepEditingAndDiscard() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        app.tabBars.buttons["Board"].firstMatch.tap()
        app.buttons["New thread"].tap()
        XCTAssertTrue(app.buttons["board-composer-close"].waitForExistence(timeout: 3))
        app.buttons["board-composer-close"].tap()
        XCTAssertTrue(app.buttons["New thread"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts["Save draft?"].exists)
        XCTAssertFalse(app.buttons["board-draft-new"].exists)
        app.buttons["New thread"].tap()
        let subject = app.textFields["What’s the topic?"]
        subject.tap(); subject.typeText("Subject only")
        app.buttons["board-composer-close"].tap()
        XCTAssertTrue(app.alerts["Save draft?"].waitForExistence(timeout: 3))
        let confirmation = XCTAttachment(screenshot: app.screenshot())
        confirmation.name = "Close composer — save, discard or keep editing"; confirmation.lifetime = .keepAlways; add(confirmation)
        app.alerts.buttons["Keep editing"].tap()
        XCTAssertEqual(subject.value as? String, "Subject only")
        app.buttons["board-composer-close"].tap()
        app.alerts.buttons["Discard draft"].tap()
        XCTAssertTrue(app.buttons["New thread"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["board-draft-new"].exists)
        app.buttons["New thread"].tap()
        XCTAssertEqual(subject.value as? String, "What’s the topic?")
        XCTAssertEqual(app.textViews["Message body"].value as? String, "")
    }

    @MainActor
    func testBoardReplyDraftIsAccessibleFromBoard() throws {
        let app = XCUIApplication()
        app.launch()
        enterPreview(in: app)
        app.tabBars.buttons["Board"].firstMatch.tap()
        let thread = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Week 1 is finally here")).firstMatch
        XCTAssertTrue(thread.waitForExistence(timeout: 3))
        thread.tap()
        let reply = app.buttons["board-reply-t1"]
        XCTAssertTrue(reply.waitForExistence(timeout: 3))
        reply.tap()
        let body = app.textViews["Message body"]
        XCTAssertTrue(body.waitForExistence(timeout: 3))
        body.tap(); body.typeText("Unsent reply draft")
        app.buttons["board-composer-close"].tap()
        app.alerts.buttons["Save draft"].tap()
        let composerClosed = expectation(for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.buttons["board-composer-close"])
        wait(for: [composerClosed], timeout: 5)
        XCTAssertEqual(reply.label, "Resume reply")
        // Do not target a transitioning or covered navigation bar after sheet dismissal.
        let back = app.navigationBars["Week 1 is finally here"].buttons["Board"]
        let backReady = expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: back)
        wait(for: [backReady], timeout: 5)
        back.tap()
        XCTAssertTrue(app.navigationBars["Board"].waitForExistence(timeout: 3))
        let resume = app.buttons["board-draft-t1"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        resume.tap()
        XCTAssertEqual(body.value as? String, "Unsent reply draft")
        XCTAssertTrue(app.staticTexts["Week 1 is finally here"].exists)
        app.buttons["board-composer-close"].tap()
        app.alerts.buttons["Discard draft"].tap()
        XCTAssertTrue(app.buttons["New thread"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["board-draft-t1"].exists)
    }

    @MainActor
    func testPreviewShowsPriorityTabs() throws {
        let app = XCUIApplication()
        app.launch()

        enterPreview(in: app)

        XCTAssertTrue(app.tabBars.buttons["Scores"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Lineup"].firstMatch.exists)
        XCTAssertTrue(app.tabBars.buttons["My Team"].firstMatch.exists)
        XCTAssertFalse(app.tabBars.buttons["Transactions"].firstMatch.exists)
        XCTAssertTrue(app.tabBars.buttons["Standings"].firstMatch.exists)
        XCTAssertTrue(app.tabBars.buttons["Board"].firstMatch.exists)
    }

    @MainActor
    func testScoreCardOpensPositionByPositionMatchup() throws {
        let app = XCUIApplication()
        app.launch()

        enterPreview(in: app)

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
        let flex = app.staticTexts["position-FLEX"]
        for _ in 0..<12 where !flex.isHittable { app.swipeUp() }
        XCTAssertTrue(flex.isHittable)
        XCTAssertTrue(app.staticTexts["UB Flex Receiver"].exists)
        XCTAssertTrue(app.staticTexts["UB Flex Back"].exists)
        let flexScreenshot = XCTAttachment(screenshot: app.screenshot())
        flexScreenshot.name = "Live scoring FLEX comparison"; flexScreenshot.lifetime = .keepAlways; add(flexScreenshot)
    }

    @MainActor
    func testStandingsExplainsOfficialLeagueOrder() throws {
        let app = XCUIApplication()
        app.launch()

        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        preview.tap()
        let standingsTab = app.tabBars.buttons["Standings"].firstMatch
        XCTAssertTrue(standingsTab.waitForExistence(timeout: 3))
        standingsTab.tap()

        let ownerRow = app.descendants(matching: .any).matching(identifier: "standing-0004").firstMatch
        XCTAssertTrue(ownerRow.waitForExistence(timeout: 3))
        XCTAssertTrue(ownerRow.label.contains("Owner: Demo Owner 4"))
        let owners = XCTAttachment(screenshot: app.screenshot())
        owners.name = "Standings with owner names"; owners.lifetime = .keepAlways; add(owners)
        app.segmentedControls.buttons["Overall"].tap()
        let overallOwner = app.descendants(matching: .any).matching(identifier: "standing-0004").firstMatch
        XCTAssertTrue(overallOwner.waitForExistence(timeout: 3))
        XCTAssertTrue(overallOwner.label.contains("Owner: Demo Owner 4"))

        let orderInfo = app.buttons["standings-order-info"]
        XCTAssertTrue(orderInfo.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Standings order"].exists)
        orderInfo.tap()

        XCTAssertTrue(app.staticTexts["Standings order"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["standings-order-rule"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Standings order info"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Done"].tap()
        XCTAssertFalse(app.staticTexts["Standings order"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testLineupRowsExposeDirectStartAndReplacementButtons() throws {
        let app = XCUIApplication()
        app.launch()

        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        preview.tap()
        let lineupTab = app.tabBars.buttons["Lineup"].firstMatch
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
        let lineupTab = app.tabBars.buttons["Lineup"].firstMatch
        XCTAssertTrue(lineupTab.waitForExistence(timeout: 3))
        lineupTab.tap()
        let replaceDak = app.buttons["lineup-replace-12620"]
        XCTAssertTrue(replaceDak.waitForExistence(timeout: 3))
        replaceDak.tap()

        XCTAssertTrue(app.navigationBars["Replace QB"].waitForExistence(timeout: 3))
        let starterProjection = app.staticTexts["lineup-replacement-starter-projection"]
        XCTAssertTrue(starterProjection.exists)
        XCTAssertEqual(starterProjection.label, "22.4")
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
