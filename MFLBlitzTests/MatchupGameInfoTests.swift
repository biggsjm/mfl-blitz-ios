import Foundation
import Testing
@testable import MFLBlitz

struct MatchupGameInfoTests {
    private let locale = Locale(identifier: "en_US")
    private let chicago = TimeZone(identifier: "America/Chicago")!
    private let kickoff = Date(timeIntervalSince1970: 1_789_318_800) // Sep 13, 2026, 17:00 UTC

    private func player(seconds: Int?) -> MatchupPlayer {
        MatchupPlayer(id: "p", name: "Player", position: "QB", nflTeam: "DAL", livePoints: 0,
            lineupStatus: .starter, gameSecondsRemaining: seconds)
    }

    private func snapshot(kickoff: Date?, home: Bool? = false) -> PlayerAvailabilitySnapshot {
        PlayerAvailabilitySnapshot(scope: "league", week: 1,
            games: ["DAL": NFLGameContext(opponent: "NYG", isHome: home, kickoff: kickoff)])
    }

    @Test("Pregame rows use home/away and localized kickoff; time zone is explained once")
    func scheduledGame() {
        let info = MatchupGameInfo(player: player(seconds: 3_600), availability: snapshot(kickoff: kickoff), scope: "league", week: 1)
        let label = info.label(locale: locale, timeZone: chicago)
        #expect(label.hasPrefix("@ NYG · Sun "))
        #expect(label.contains("12:00") && label.contains("PM"))
        #expect(!label.contains("CST") && !label.contains("CDT"))
        #expect(MatchupGameInfo.timeZoneLabel(locale: locale, timeZone: chicago) == "Times in CT")
        let home = MatchupGameInfo(player: player(seconds: 3_600), availability: snapshot(kickoff: kickoff, home: true), scope: "league", week: 1)
        #expect(home.label(locale: locale, timeZone: chicago).hasPrefix("vs NYG · "))
    }

    @Test("Kickoff honors 24-hour locale and time zones across daylight saving")
    func localTime() {
        let british = Locale(identifier: "en_GB")
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        let summer = MatchupGameInfo(player: player(seconds: 3_600), availability: snapshot(kickoff: kickoff), scope: "league", week: 1)
        #expect(summer.label(locale: british, timeZone: chicago).contains("12:00"))
        #expect(summer.label(locale: british, timeZone: pacific).contains("10:00"))
        let winter = MatchupGameInfo(player: player(seconds: 3_600), availability: snapshot(kickoff: kickoff.addingTimeInterval(70 * 86_400)), scope: "league", week: 1)
        #expect(winter.label(locale: british, timeZone: chicago).contains("11:00"))
        #expect(winter.label(locale: british, timeZone: pacific).contains("9:00"))
    }

    @Test("Live and final labels use scoring state, never zero points or elapsed kickoff")
    func scoringState() {
        let schedule = snapshot(kickoff: kickoff)
        let live = MatchupGameInfo(player: player(seconds: 900), availability: schedule, scope: "league", week: 1)
        #expect(live.isLive && live.label(locale: locale, timeZone: chicago) == "@ NYG · Live")
        let final = MatchupGameInfo(player: player(seconds: 0), availability: schedule, scope: "league", week: 1, now: kickoff.addingTimeInterval(14_400))
        #expect(!final.isLive && final.label(locale: locale, timeZone: chicago) == "@ NYG · Final")
        let futureZero = MatchupGameInfo(player: player(seconds: 0), availability: schedule, scope: "league", week: 1, now: kickoff.addingTimeInterval(-60))
        #expect(futureZero.kickoff == kickoff && futureZero.status == nil)
        let unknown = MatchupGameInfo(player: player(seconds: nil), availability: schedule, scope: "league", week: 1, now: kickoff.addingTimeInterval(14_400))
        #expect(!unknown.isLive && unknown.status == nil && unknown.kickoff == kickoff)
    }

    @Test("Only an explicit matching-week bye is called a bye; an active scoring clock wins conflicts")
    func byes() {
        var data = PlayerAvailabilitySnapshot(scope: "league", week: 1, byeWeeks: ["DAL": 1])
        let bye = MatchupGameInfo(player: player(seconds: 0), availability: data, scope: "league", week: 1)
        #expect(bye.label(locale: locale, timeZone: chicago) == "Bye week")
        let live = MatchupGameInfo(player: player(seconds: 900), availability: data, scope: "league", week: 1)
        #expect(live.label(locale: locale, timeZone: chicago) == "Live")
        data.byeWeeks["DAL"] = 2
        let otherWeek = MatchupGameInfo(player: player(seconds: nil), availability: data, scope: "league", week: 1)
        #expect(otherWeek.status == "Status unavailable")
    }

    @Test("Missing game/time and wrong-week or wrong-league caches remain honest fallbacks")
    func missingData() {
        let data = snapshot(kickoff: nil)
        let tbd = MatchupGameInfo(player: player(seconds: 3_600), availability: data, scope: "league", week: 1)
        #expect(tbd.label(locale: locale, timeZone: chicago) == "@ NYG · Time TBD")
        for (scope, week) in [("other", 1), ("league", 2)] {
            let wrong = MatchupGameInfo(player: player(seconds: 3_600), availability: data, scope: scope, week: week)
            #expect(wrong.label(locale: locale, timeZone: chicago) == "Yet to play")
        }
        let noWeek = MatchupGameInfo(player: player(seconds: 0), availability: data, scope: "league", week: nil)
        #expect(noWeek.label(locale: locale, timeZone: chicago) == "Final / no game")
        let missing = MatchupGameInfo(player: player(seconds: nil), availability: nil, scope: "league", week: 1)
        #expect(missing.label(locale: locale, timeZone: chicago) == "Status unavailable")
    }

    @Test("Repeated matchup and player visits reuse the cached weekly read") @MainActor
    func cacheReuse() async {
        let tools = PlayerToolsModel()
        tools.reset(scope: "league")
        var reads = 0
        await tools.loadAvailability(week: 1, refresh: false) {
            reads += 1
            return snapshot(kickoff: kickoff)
        }
        await tools.loadAvailability(week: 1, refresh: false) {
            reads += 1
            return snapshot(kickoff: kickoff)
        }
        #expect(reads == 1)
        #expect(tools.availability[1]?.games["DAL"]?.opponent == "NYG")
    }
}
