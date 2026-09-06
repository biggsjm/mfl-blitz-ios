import Foundation
import Testing
@testable import MFLCore

@Suite("MFL flexible JSON decoding")
struct ModelDecodingTests {
    private let decoder = MFLResponseDecoder()

    @Test("League settings and nested singleton collections decode")
    func league() throws {
        let response = try decoder.decode(MFLLeagueResponse.self, from: fixture("league"))

        #expect(response.league.id == "41366")
        #expect(response.league.name == "Saturday Legends")
        #expect(response.league.serverHost?.name == "www42.myfantasyleague.com")
        #expect(response.league.endWeek == 18)
        #expect(response.league.franchises.count == 2)
        #expect(response.league.franchises[0].blindBidAvailableBalance == Decimal(string: "74.50"))
        #expect(response.league.divisions.map(\.name) == ["North"])
        #expect(response.league.starterCount == 9)
        #expect(response.league.maxWaiverRounds == 8)
        #expect(response.league.tiebreakerCount == 1)
        #expect(response.league.starterRequirements[1].minimum == 2)
        #expect(response.league.starterRequirements[1].maximum == 3)
        #expect(response.league.starterRequirements[2].maximum == nil)
    }

    @Test("Singleton player and roster players normalize to arrays")
    func playerAndRosterSingletons() throws {
        let players = try decoder.decode(MFLPlayersResponse.self, from: fixture("players-singleton")).players
        let rosters = try decoder.decode(MFLRostersResponse.self, from: fixture("rosters")).rosters
        let freeAgents = try decoder.decode(
            MFLFreeAgentsResponse.self,
            from: fixture("free-agents")
        ).freeAgents

        #expect(players.players.count == 1)
        #expect(players.players[0].displayName == "Riley Receiver")
        #expect(players.players[0].jerseyNumber == "18")
        #expect(rosters.rosters[0].players.count == 1)
        #expect(rosters.rosters[0].players[0].salary == Decimal(string: "12.50"))
        #expect(rosters.rosters[1].players[0].status == .injuredReserve)
        #expect(freeAgents.players.map(\.id) == ["17001", "17002"])
    }

    @Test("Live matchup handles string, number, and boolean scalars")
    func liveScoring() throws {
        let live = try decoder.decode(MFLLiveScoringResponse.self, from: fixture("live-scoring")).liveScoring

        #expect(live.week == 7)
        #expect(live.matchups.count == 1)
        #expect(live.matchups[0].franchises[0].isInProgress)
        #expect(live.matchups[0].franchises[0].players[0].isStarter)
        #expect(live.matchups[0].franchises[1].isHome == true)
        #expect(live.matchups[0].franchises[1].score == Decimal(string: "99.2"))
    }

    @Test("Variable standings columns remain available")
    func standings() throws {
        let standings = try decoder.decode(
            MFLLeagueStandingsResponse.self,
            from: fixture("standings")
        ).leagueStandings

        #expect(standings.franchises[0].wins == 6)
        #expect(standings.franchises[0].pointsFor == Decimal(string: "812.45"))
        #expect(standings.franchises[0].blindBidBalance == Decimal(string: "74.50"))
        #expect(standings.franchises[0].stringValue(for: "custom_metric") == "11.4")
        #expect(standings.columns.map(\.abbreviation) == ["W-L-T", "PF"])
    }

    @Test("Message board and thread text-object variants decode")
    func messages() throws {
        let board = try decoder.decode(MFLMessageBoardResponse.self, from: fixture("message-board")).messageBoard
        let thread = try decoder.decode(
            MFLMessageBoardThreadResponse.self,
            from: fixture("message-thread")
        ).messageBoardThread

        #expect(board.threads[0].subject == "Week 7 trash talk")
        #expect(board.threads[0].replyCount == 4)
        #expect(thread.messages.map(\.body) == ["Good luck this week!", "You will need it."])
        #expect(thread.messages[1].franchiseID == "0002")
    }

    @Test("Pending blind bids decode nested and compact pick forms")
    func waivers() throws {
        let pending = try decoder.decode(
            MFLPendingWaiversResponse.self,
            from: fixture("pending-waivers")
        ).pendingWaivers

        #expect(pending.requests.count == 2)
        #expect(pending.requests[0].claims[0].bidAmount == Decimal(17))
        #expect(pending.requests[0].claims[1].dropPlayerID == nil)
        #expect(pending.requests[1].claims.map(\.playerID) == ["17003", "17004"])
        #expect(pending.requests[1].claims[1].bidAmount == Decimal(2))
    }
}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}
