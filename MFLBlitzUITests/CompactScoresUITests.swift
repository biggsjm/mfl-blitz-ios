import XCTest

final class CompactScoresUITests: XCTestCase {
    @MainActor func testLeagueAndAllStarterPairsUseCompactRows() {
        let app = XCUIApplication()
        app.launch()
        let preview = app.buttons["Preview Champion Hall"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8)); preview.tap()
        let hero = app.buttons["matchup-0001-0008"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        XCTAssertLessThan(hero.frame.height, 300, "Keep the hero featured with legible identity and labeled projections")
        let awayMetrics = app.descendants(matching: .any)["hero-metrics-0001"].firstMatch
        let homeMetrics = app.descendants(matching: .any)["hero-metrics-0008"].firstMatch
        XCTAssertTrue(awayMetrics.exists)
        XCTAssertTrue(homeMetrics.exists)
        XCTAssertEqual(awayMetrics.frame.minY, homeMetrics.frame.minY, accuracy: 1,
            "Team names with different line counts must not misalign the score rows")
        XCTAssertEqual(awayMetrics.frame.width, homeMetrics.frame.width, accuracy: 1,
            "The two mirrored matchup halves should have equal widths")
        let leagueGames = ["0002-0011", "0003-0007", "0004-0009", "0005-0010", "0006-0012"]
        for id in leagueGames {
            let game = app.buttons["matchup-\(id)"]
            for _ in 0..<5 where !game.exists { app.swipeUp() }
            XCTAssertTrue(game.exists)
            guard game.exists else { continue }
            XCTAssertLessThan(game.frame.height, hero.frame.height,
                "League rows remain more compact than the featured matchup while allowing complete names and projections")
        }
        for _ in 0..<6 where !hero.isHittable { app.swipeDown() }
        capture(app, "Compact scores — featured matchup and the league")
        hero.tap()
        XCTAssertTrue(app.navigationBars["Week 1 Matchup"].waitForExistence(timeout: 5))
        let first = app.buttons["matchup-player-0001-starter-0-away"]
        let last = app.buttons["matchup-player-0001-starter-8-away"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "vs CHI")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["DAL · vs CHI"].exists)
        XCTAssertTrue(last.exists)
        XCTAssertLessThan(last.frame.maxY - first.frame.minY, 1100,
            "Prefer legible points and projection labels to squeezing every starter onto one screen")
        for index in 0..<9 {
            for side in ["away", "home"] {
                let team = side == "away" ? "0001" : "0008"
                let player = app.buttons["matchup-player-\(team)-starter-\(index)-\(side)"]
                XCTAssertTrue(player.exists)
                XCTAssertGreaterThanOrEqual(player.frame.height + 0.01, 44)
                XCTAssertGreaterThanOrEqual(player.frame.width, 44)
                XCTAssertEqual(player.frame.height, first.frame.height, accuracy: 1,
                    "Every starter uses the same player area")
            }
        }
        capture(app, "Compact matchup — nine starter pairs")
        first.tap()
        XCTAssertTrue(app.descendants(matching: .any)["player-detail-0001-starter-0"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Week 1 Matchup"].waitForExistence(timeout: 5))
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
