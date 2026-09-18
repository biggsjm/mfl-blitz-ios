import Foundation
import Testing
@testable import MFLBlitz

struct ScoringDataStatusTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var shakir: MatchupPlayer {
        .init(id: "1431", name: "Khalil Shakir", position: "WR", nflTeam: "BUF", livePoints: 3,
              lineupStatus: .starter, gameSecondsRemaining: 2700, statLine: nil)
    }
    func game(status: String = "Q2", age: Double = 0, players: [NFLFeedPlayer]? = nil) -> NFLFeedGame {
        .init(id: 21529, season: 2026, week: 2, kickoff: now.timeIntervalSince1970 - 3600,
            status: status, timer: "10:20", home: "BUF", away: "DET", homeScore: 21, awayScore: 0,
            checkedAt: now.timeIntervalSince1970, stale: false,
            players: players ?? [.init(providerID: 1431, name: "Khalil Shakir", team: "BUF", position: "WR",
                groups: [.init(name: "Receiving", stats: [.init(name: "receptions", value: "2"), .init(name: "yards", value: "10")])])],
            statsCheckedAt: now.timeIntervalSince1970 - age, statsStale: false)
    }
    func status(players: [MatchupPlayer]? = nil, games: [NFLFeedGame]? = nil, failures: Int = 0,
                mflDate: Date? = nil, loading: Bool = false, configured: Bool = true,
                mflGames: NFLScoringSnapshot? = nil) -> ScoringDataStatus {
        .nfl(players: players ?? [shakir], week: 2,
            feed: games.map { .init(schema: 1, provider: "API-NFL", season: 2026, week: 2,
                fetchedAt: now.timeIntervalSince1970, warming: false, retryAfter: 20, games: $0) },
            scoringGames: mflGames, availability: nil, scope: "league", mflCheckedAt: mflDate ?? now,
            configured: configured, failures: failures, loading: loading, preview: false, now: now)
    }
    @Test func successfulResponseDoesNotHideAnUnstartedProviderGame() {
        let result = status(games: [game(status: "NS", players: [])])
        #expect(result.state == .delayed)
        #expect(result.detail.contains("haven’t arrived"))
    }
    @Test func missingPlayerAndEmptyOrStaleBoxesAreDelayed() {
        let other = NFLFeedPlayer(providerID: 9, name: "Someone Else", team: "BUF", position: "WR",
            groups: [.init(name: "Receiving", stats: [.init(name: "yards", value: "1")])])
        for game in [game(players: []), game(players: [other]), game(age: 151)] {
            #expect(status(games: [game]).state == .delayed)
        }
    }
    @Test func healthyBoxUsesStatReceiptInsteadOfLatestHTTPTime() {
        let result = status(games: [game(age: 90)])
        #expect(result.state == .updating)
        #expect(result.checkedAt == now.addingTimeInterval(-90))
    }
    @Test func zeroStatsAreUsableButEmptyPlaceholdersAreNot() {
        let zero = NFLFeedPlayer(providerID: 1431, name: "Khalil Shakir", team: "BUF", position: "WR",
            groups: [.init(name: "Receiving", stats: [.init(name: "receptions", value: "0")])])
        #expect(zero.hasUsableStats)
        #expect(status(games: [game(players: [zero])]).state == .updating)
        let empty = NFLFeedPlayer(providerID: 1431, name: "Khalil Shakir", team: "BUF", position: "WR",
            groups: [.init(name: "Receiving", stats: [.init(name: "receptions", value: "—")])])
        #expect(!empty.hasUsableStats)
        #expect(status(games: [game(players: [empty])]).state == .delayed)
    }
    @Test func noGamesAndPostponementsAreIdleWithoutInventingLivePlay() {
        var upcoming = shakir; upcoming.gameSecondsRemaining = 3600; upcoming.livePoints = nil
        #expect(status(players: [upcoming]).state == .idle)
        #expect(status(players: [upcoming], games: [game(status: "NS", players: [])]).state == .idle)
        for state in ["PST", "CANC", "SUSP", "INT"] {
            #expect(status(games: [game(status: state, players: [])]).state == .idle)
        }
    }
    @Test func unknownGameStateIsNotReportedAsIdle() {
        var unknown = shakir; unknown.gameSecondsRemaining = nil
        #expect(status(players: [unknown]).state == .checking)
        #expect(status(players: []).state == .checking)
    }
    @Test func oldFinalStatsDoNotExpireAndNoLongerCountAsActive() {
        var final = shakir; final.gameSecondsRemaining = 0
        #expect(status(players: [final], games: [game(status: "FT", age: 86400)]).state == .current)
    }
    @Test func oldUnconfirmedLiveScoresCannotTurnTheFeedGreenOrIdle() {
        #expect(status(games: [game(status: "NS", players: [])], mflDate: now.addingTimeInterval(-600)).state == .delayed)
    }
    @Test func unviewedPlayersAndOtherWeeksDoNotDetermineStatus() {
        var unrelated = shakir; unrelated.nflTeam = "DAL"; unrelated.gameSecondsRemaining = 3600
        #expect(status(players: [unrelated], games: [game(players: [])]).state == .idle)
        var upcoming = shakir; upcoming.gameSecondsRemaining = 3600
        let wrongWeek = NFLScoringSnapshot(scope: "league", week: 1,
            games: ["BUF": .init(opponent: "DET", isHome: true, kickoff: nil, gameSecondsRemaining: 2700)], checkedAt: now)
        #expect(status(players: [upcoming], games: [game(status: "NS")], mflGames: wrongWeek).state == .idle)
        let currentWeek = NFLScoringSnapshot(scope: "league", week: 2, games: wrongWeek.games, checkedAt: now)
        #expect(status(players: [upcoming], games: [game(status: "NS")], mflGames: currentWeek).state == .delayed)
    }
    @Test func repeatedFailuresRequireNoUsableStatsToBecomeUnavailable() {
        #expect(status(failures: 1).state == .delayed)
        #expect(status(failures: 3).state == .unavailable)
        #expect(status(games: [game()], failures: 3).state == .delayed)
        #expect(status(configured: false).state == .off)
    }
    @Test func defenseStatsUseTheirOwnReceiptAndCoverage() {
        var defense = shakir; defense.position = "DEF"; defense.name = "Bills"
        #expect(status(players: [defense], games: [game()]).state == .delayed)
        var box = game()
        box.defenses = [.init(providerID: 20, name: "Bills", team: "BUF", position: "DEF",
            groups: [.init(name: "Defense", stats: [.init(name: "points allowed", value: "0")])])]
        box.defenseCheckedAt = now.timeIntervalSince1970; box.defenseStale = false
        #expect(status(players: [defense], games: [box]).state == .updating)
    }
    @Test func scoreFreshnessOnlyAgesDuringLivePlay() {
        let snapshot = ScoresSnapshot(week: 2, matchups: [], lastUpdated: now, isLive: false, checkedAt: now.addingTimeInterval(-600))
        func mfl(live: Bool, preview: Bool = false) -> ScoringDataStatus {
            .mfl(snapshot: snapshot, live: live, refreshing: false, failed: false, offline: false, saved: false, preview: preview, now: now)
        }
        #expect(mfl(live: false).state == .idle)
        #expect(mfl(live: true).state == .delayed)
        #expect(mfl(live: true, preview: true).state == .preview)
    }
    @Test func backgroundRegistrationMustBeCurrentAndWithoutAConnectionFailure() {
        func background(expiry: Date?, attention: Bool = false) -> ScoringDataStatus {
            .background(enabled: true, configured: true, tracking: true, registered: true,
                attention: attention, expiresAt: expiry, checkedAt: now, now: now)
        }
        #expect(background(expiry: now.addingTimeInterval(60)).state == .connected)
        #expect(background(expiry: now).state == .attention)
        #expect(background(expiry: now.addingTimeInterval(60), attention: true).state == .attention)
        #expect(background(expiry: nil).state == .checking)
    }
    @Test func alertRegistrationRequiresPermissionAndTheCurrentWeek() {
        func alerts(week: Int = 2, permission: Bool = false, expires: Date? = nil) -> ScoringDataStatus {
            .alerts(permissionKnown: true, permissionRequired: permission, busy: false, week: 2,
                acknowledgedWeek: week, expiresAt: expires ?? now.addingTimeInterval(60), now: now)
        }
        #expect(alerts().state == .connected)
        #expect(alerts(week: 1).state == .attention)
        #expect(alerts(permission: true).state == .attention)
        #expect(alerts(expires: now).state == .attention)
    }
}
