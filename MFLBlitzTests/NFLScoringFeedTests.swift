import Foundation
import Testing
@testable import MFLBlitz

struct NFLScoringFeedTests {
    func player(name: String = "UB Quarterback", position: String = "QB", team: String = "DAL") -> MatchupPlayer {
        MatchupPlayer(id: "mfl-1", name: name, position: position, nflTeam: team, livePoints: 20,
            lineupStatus: .starter, gameSecondsRemaining: 900, statLine: nil)
    }
    @Test func compactStatsKeepCompletionsTouchdownsTurnoversAndMixedYardage() {
        let box = NFLFeedPlayer(providerID: 1, name: "Player", team: "DAL", position: "QB", groups: [
            NFLFeedGroup(name: "Passing", stats: [.init(name: "comp att", value: "24/31"), .init(name: "yards", value: "311"),
                .init(name: "passing touch downs", value: "2"), .init(name: "interceptions", value: "1")]),
            NFLFeedGroup(name: "Rushing", stats: [.init(name: "total rushes", value: "3"), .init(name: "yards", value: "18"),
                .init(name: "rushing touch downs", value: "1")]),
            NFLFeedGroup(name: "Receiving", stats: [.init(name: "total receptions", value: "2"), .init(name: "yards", value: "23"),
                .init(name: "receiving touch downs", value: "1"), .init(name: "two pt", value: "1")]),
            NFLFeedGroup(name: "Fumbles", stats: [.init(name: "lost", value: "1")])])
        #expect(box.compactSummary == "24/31 · 311 PYD · 2 PTD · 1 INT · 3 CAR · 18 RYD · 1 RTD · 2 REC · 23 YDS · 1 TD · 1 REC2PT · 1 FL")
        #expect(box.summary?.components(separatedBy: " · ").count == box.compactSummary?.components(separatedBy: " · ").count)
    }
    @Test func compactGameScoresKeepThePlayersTeamFirstOnEitherSide() {
        let game = NFLFeedPreview.make().games[0]
        let home = MatchupGameInfo(player: player(team: "DAL"), availability: nil, scope: "league", week: 1, nflGame: game)
        let away = MatchupGameInfo(player: player(team: "NYG"), availability: nil, scope: "league", week: 1, nflGame: game)
        #expect(home.compactScoreLabel == "vs NYG 20–14")
        #expect(away.compactScoreLabel == "@ DAL 14–20")
    }
    @Test func matchesOnlyUniqueNameTeamAndPosition() {
        var game = NFLFeedPreview.make().games[0]
        #expect(game.player(matching: player())?.providerID == 999001)
        #expect(game.player(matching: player(team: "NYG")) == nil)
        #expect(game.player(matching: player(position: "RB")) == nil)
        #expect(game.player(matching: player(name: "UB Quarterback Jr.")) == nil)
        game.players.append(game.players[0])
        #expect(game.player(matching: player()) == nil)
    }
    @Test func rejectsWrongWeekSeasonAndDuplicateGame() throws {
        let feed = NFLFeedPreview.make()
        #expect(throws: (any Error).self) { try feed.validated(season: 2025, week: 1) }
        #expect(throws: (any Error).self) { try feed.validated(season: 2026, week: 2) }
        var duplicate = feed; duplicate.games.append(feed.games[0])
        #expect(throws: (any Error).self) { try duplicate.validated(season: 2026, week: 1) }
    }
    @Test func camTranslationDecodesAndExplainsHisFourteenPoints() throws {
        let data = Data(#"{"providerID":31107,"name":"Cameron Skattebo","team":"NYG","position":"RB","mflID":"17045","mflName":"Cam Skattebo","groups":[{"name":"Rushing","stats":[{"name":"total rushes","value":"18"},{"name":"yards","value":"81"},{"name":"rushing touch downs","value":"1"}]}]}"#.utf8)
        let box = try JSONDecoder().decode(NFLFeedPlayer.self, from: data)
        var game = NFLFeedPreview.make().games[0]; game.players = [box]
        let cam = MatchupPlayer(id: "17045", name: "Cam Skattebo", position: "RB", nflTeam: "NYG", livePoints: 14,
            lineupStatus: .starter, gameSecondsRemaining: 0, statLine: nil)
        let matched = try #require(game.player(matching: cam))
        #expect(matched.summary == "18 carries · 81 rush yd · 1 rush TD")
        let breakdown = ScoringBreakdown(rules: [
            .init(id: 0, positions: ["RB"], event: "RY", label: "Rushing yards", range: "0-999", points: "1/10"),
            .init(id: 1, positions: ["RB"], event: "#R", label: "Rushing TDs", range: "0-99", points: "*6")],
            position: "RB", player: matched, official: 14)
        #expect(breakdown.contributions.map(\.points) == [8, 6]); #expect(breakdown.difference == 0)
        // A familiar name cannot override a conflicting ID or metadata.
        for bad in [player(name: "Cam Skattebo", position: "RB", team: "NYG"),
                    MatchupPlayer(id: "17045", name: "Cam Ward", position: "RB", nflTeam: "NYG", livePoints: 0, lineupStatus: .starter, gameSecondsRemaining: 0, statLine: nil)] {
            #expect(game.player(matching: bad) == nil)
        }
        game.players[0].mflName = nil
        #expect(game.player(matching: cam) == nil)
        game.players = [box, box]; #expect(game.player(matching: cam) == nil)
    }
    @Test func translationValidationRejectsConflictsAndIncompletePairs() throws {
        var feed = NFLFeedPreview.make()
        feed.games[0].players[0].mflID = "17045"
        #expect(throws: (any Error).self) { try feed.validated(season: 2026, week: 1) }
        feed.games[0].players[0].mflName = "Cam Skattebo"
        _ = try feed.validated(season: 2026, week: 1)
        var second = feed.games[1].players[0]; second = NFLFeedPlayer(providerID: second.id, name: second.name, team: "DAL", position: second.position, groups: second.groups, mflID: "17045", mflName: "Cam Skattebo")
        feed.games[0].players.append(second)
        #expect(throws: (any Error).self) { try feed.validated(season: 2026, week: 1) }
        feed.games[0].players.removeLast(); feed.games[0].players[0].mflID = "not-an-id"
        #expect(throws: (any Error).self) { try feed.validated(season: 2026, week: 1) }
    }
    @Test func boxScoreAgeIsIndependentOfFreshScore() {
        let game = NFLFeedPreview.make().games[0]
        let now = Date(timeIntervalSince1970: game.checkedAt + 110)
        #expect(!game.gameIsStale(now: now))
        #expect(game.statsAreStale(now: now.addingTimeInterval(30)))
    }
    @Test func exactQuarterOverridesMFLApproximationWithoutChangingFantasyPoints() {
        let game = NFLFeedPreview.make().games[0], player = player()
        let info = MatchupGameInfo(player: player, availability: nil, scope: "league", week: 1, nflGame: game)
        #expect(info.status == "Q3 04:32")
        #expect(info.scoreLabel == "DAL 20 · NYG 14")
        #expect(player.livePoints == 20)
        var missingClock = player; missingClock.gameSecondsRemaining = nil
        #expect(PlayerScoringContext.isEligible(missingClock, game: info))
        #expect(game.player(matching: player)?.summary == "24/31 pass · 311 pass yd · 2 pass TD · 3 carries · 18 rush yd")
    }
    private func kickoffGame(now: Date) -> NFLFeedGame {
        NFLFeedGame(id: 21529, season: 2026, week: 2, kickoff: now.timeIntervalSince1970 - 300,
            status: "NS", timer: nil, home: "BUF", away: "DET", homeScore: nil, awayScore: nil,
            checkedAt: now.timeIntervalSince1970, stale: false, players: [], statsCheckedAt: nil, statsStale: true)
    }
    @Test(arguments: [nil, 3600, 3249] as [Int?])
    func delayedNFLKickoffCannotHideMFLPlay(seconds: Int?) {
        let now = Date(), nfl = kickoffGame(now: now)
        var active = player(team: "BUF"); active.gameSecondsRemaining = 3249; active.livePoints = 3
        let mfl = NFLScoringSnapshot(scope: "league", week: 2, games: ["BUF":
            NFLGameContext(opponent: "DET", isHome: true, kickoff: now.addingTimeInterval(-300),
                score: seconds == 3249 ? 7 : nil, opponentScore: seconds == 3249 ? 0 : nil,
                gameSecondsRemaining: seconds)], checkedAt: now)
        let info = MatchupGameInfo(player: active, availability: nil, scope: "league", week: 2,
            scoringGames: mfl, nflGame: nfl, now: now)
        #expect(info.isLive && info.kickoff == nil)
        #expect(info.opponent == "vs DET")
        #expect(info.scoreLabel == (seconds == 3249 ? "BUF 7 · DET 0" : nil))
        #expect(info.status == "Live")
        #expect(active.livePoints == 3)
        #expect(nfl.player(matching: active) == nil)
    }
    @Test func pendingProviderRetainsOpponentWithoutInventingAScoreOrClock() {
        let now = Date()
        let info = MatchupGameInfo(player: player(team: "DET"), availability: nil, scope: "league", week: 2,
            nflGame: kickoffGame(now: now), now: now)
        #expect(info.isLive && info.status == "Live")
        #expect(info.opponent == "@ BUF")
        #expect(info.scoreLabel == nil && info.gameCheckedAt == nil && info.kickoff == nil)
    }
    @Test func kickoffTimeAndFantasyPointsAloneDoNotProveLivePlay() {
        let now = Date()
        var upcoming = player(team: "BUF"); upcoming.gameSecondsRemaining = 3600
        let unrelated = NFLScoringSnapshot(scope: "other", week: 2, games: ["BUF":
            NFLGameContext(opponent: "DET", isHome: true, kickoff: now.addingTimeInterval(-300),
                gameSecondsRemaining: 3000)], checkedAt: now)
        let info = MatchupGameInfo(player: upcoming, availability: nil, scope: "league", week: 2,
            scoringGames: unrelated, nflGame: kickoffGame(now: now), now: now)
        #expect(!info.isLive && info.kickoff != nil && info.scoreLabel == nil)
    }
    func summary(_ groups: [(String, [(String, String?)])]) -> String? {
        NFLFeedPlayer(providerID: 1, name: "Test Player", team: "JAC", position: "TE", groups: groups.map { name, stats in
            NFLFeedGroup(name: name, stats: stats.map { NFLFeedStat(name: $0.0, value: $0.1) })
        }).summary
    }
    @Test func strangeReceivingLineIncludesHisTouchdown() {
        // Values and field names observed in the cached Week 1 Strange box.
        #expect(summary([("Receiving", [("total receptions", "2"), ("yards", "23"),
            ("receiving touch downs", "1"), ("two pt", "0")])]) == "2 rec · 23 rec yd · 1 rec TD")
    }
    @Test func keepsScoringEventsBeyondTheFirstTwoGroups() {
        let line = summary([("Passing", [("yards", "200"), ("passing touch downs", "2"), ("interceptions", "1")]),
            ("Rushing", [("yards", "-2"), ("rushing touch downs", "1"), ("two pt", "1")]),
            ("Receiving", [("total receptions", "1"), ("yards", "0"), ("receiving touch downs", "1")]),
            ("Fumbles", [("total", "2"), ("lost", "1")])])
        #expect(line == "200 pass yd · 2 pass TD · 1 INT thrown · -2 rush yd · 1 rush TD · 1 rush 2PT · 1 rec · 0 rec yd · 1 rec TD · 1 fumble lost")
    }
    @Test func missingYardageCannotHideATouchdownAndNullIsNotZero() {
        #expect(summary([("Receiving", [("yards", nil), ("receiving touch downs", "2")])]) == "2 rec TD")
        #expect(summary([("Receiving", [("yards", nil), ("receiving touch downs", nil)])]) == nil)
        #expect(summary([("Rushing", [("yards", "0"), ("rushing touch downs", "0")])]) == "0 rush yd")
    }
    @Test func includesKickerConversionsAndAvailableDistanceBuckets() {
        #expect(summary([("Kicking", [("field goals", "2/3"), ("extra point", "1/2"),
            ("field goals from 40 49 yards", "1"), ("field goals from 50 yards", "1"),
            ("field goals from 20 29 yards", "0")])]) == "2/3 FG · 1/2 XP · 1 FG 40–49 yd · 1 FG 50+ yd")
    }
    @Test func returnAndDefensiveEventsAppearOnceWithoutAddingDuplicateTotals() {
        let line = summary([("Rushing", [("kick return td", "1")]),
            ("Kick_returns", [("td", nil), ("kick return td", "1"), ("yards", "100")]),
            ("Punt_returns", [("td", "1")]),
            ("Defensive", [("interceptions for touch downs", "1"), ("sacks", "0.5"), ("ff", "1")]),
            ("Interceptions", [("intercepted touch downs", "1"), ("total interceptions", "1")]),
            ("Fumbles", [("rec", "1"), ("rec td", "1")])])
        #expect(line == "0.5 sacks · 1 forced fumble · 1 INT · 1 INT TD · 1 fumble recovered · 1 fumble TD · 100 kick return yd · 1 kick return TD · 1 punt return TD")
    }
    @Test func archivedFinalKeepsItsReceiptWithoutExpiringOnThePhone() {
        let original = NFLFeedPreview.make().games[0]
        var game = NFLFeedGame(id: original.id, season: original.season, week: original.week, kickoff: original.kickoff,
            status: "FT", timer: nil, home: original.home, away: original.away, homeScore: 20, awayScore: 14,
            checkedAt: original.checkedAt, stale: false, players: original.players,
            statsCheckedAt: original.statsCheckedAt, statsStale: false)
        let later = Date(timeIntervalSince1970: original.checkedAt + 30 * 86400)
        #expect(!game.gameIsStale(now: later)); #expect(!game.statsAreStale(now: later))
        #expect(game.statsCheckedAt == original.statsCheckedAt)
        game.statsStale = true
        #expect(game.statsAreStale(now: later))
    }
    @Test func validatesPrivateAddressAndDoesNotAcceptKeysInURL() throws {
        for address in ["http://a.b.ts.net", "https://api-sports.io", "https://key@a.b.ts.net", "https://a.b.ts.net?key=x", "https://a.b.ts.net/v1"] {
            #expect(throws: (any Error).self) { try NFLFeedClient(address: address) }
        }
        let client = try NFLFeedClient(address: "https://a.b.ts.net:8445")
        #expect(client.session.configuration.httpCookieStorage == nil)
        #expect(client.session.configuration.urlCredentialStorage == nil)
    }
    @Test func cadenceIsFastDuringPlayAndBacksOffOnFailure() {
        #expect(ScoringRefreshCadence.interval(live: true, currentWeek: true, failed: false) == 60)
        #expect(ScoringRefreshCadence.interval(live: false, currentWeek: false, failed: false) == 300)
        #expect(ScoringRefreshCadence.interval(live: true, currentWeek: true, failed: true) == 180)
    }
}

private actor FeedLoader {
    var calls = 0
    var fail = false
    func setFailure() { fail = true }
    func load(_ season: Int, _ week: Int) async throws -> NFLWeekFeed {
        calls += 1
        try await Task.sleep(for: .milliseconds(50))
        if fail { throw URLError(.notConnectedToInternet) }
        return NFLFeedPreview.make(season: season, week: week)
    }
}
@MainActor struct NFLScoringStoreTests {
    @Test func readersCoalesceAndRepeatedReadsUsePhoneCache() async {
        let loader = FeedLoader(), store = NFLScoringStore(loader: { season, week, _, _ in try await loader.load(season, week) })
        async let a: Void = store.refresh(season: 2026, week: 1)
        async let b: Void = store.refresh(season: 2026, week: 1)
        _ = await (a,b)
        await store.refresh(season: 2026, week: 1)
        #expect(await loader.calls == 1)
        #expect(store.feed(season: 2026, week: 1)?.games.count == 2)
        #expect(store.feed(season: 2025, week: 1) == nil)
    }
    @Test func failureKeepsStatsAndOriginalReceiptAndBacksOffRepeatedRefresh() async throws {
        let loader = FeedLoader(), store = NFLScoringStore(loader: { season, week, _, _ in try await loader.load(season, week) })
        await store.refresh(season: 2026, week: 1)
        let first = try #require(store.feed(season: 2026, week: 1))
        await loader.setFailure()
        await store.refresh(season: 2026, week: 1, force: true)
        #expect(store.failed(season: 2026, week: 1))
        #expect(store.feed(season: 2026, week: 1)?.fetchedAt == first.fetchedAt)
        #expect(store.feed(season: 2026, week: 1)?.games[0].players == first.games[0].players)
        #expect(store.feed(season: 2026, week: 1)?.games[0].statsStale == true)
        await store.refresh(season: 2026, week: 1, force: true)
        #expect(await loader.calls == 2)
    }
}
