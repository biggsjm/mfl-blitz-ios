import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

struct TransactionDetailsTests {
    @Test("An unknown minimum bid is explained without claiming the waiver window is closed")
    func waiverWording() throws {
        var league: [String: Any] = ["id": "99999", "name": "Synthetic", "currentWaiverType": "BBID_FCFS",
            "bbidConditional": "Yes", "maxWaiverRounds": "8", "bbidIncrement": "1", "bbidSeasonLimit": "100"]
        func decode(_ value: [String: Any]) throws -> MFLLeague {
            try MFLResponseDecoder().decode(MFLLeagueResponse.self, from: JSONSerialization.data(withJSONObject: ["league": value])).league
        }
        let reason = try #require(LiveMFLRepository.waiverAvailability(decode(league), season: 2026))
        #expect(reason.contains("minimum bid") && reason.contains("draft bids"))
        #expect(!reason.contains("window") && !reason.contains("format"))
        league["bbidMinimum"] = "0"
        #expect(try LiveMFLRepository.waiverAvailability(decode(league), season: 2026) == nil)
    }

    @Test("The confirmed $0 minimum applies only to this season and league, and MFL's explicit rule wins")
    func confirmedMinimum() throws {
        var fields: [String: Any] = ["id": "41333", "name": "Synthetic", "currentWaiverType": "BBID_FCFS",
            "bbidConditional": "Yes", "maxWaiverRounds": "8", "bbidIncrement": "1", "bbidSeasonLimit": "100"]
        func decode() throws -> MFLLeague {
            try MFLResponseDecoder().decode(MFLLeagueResponse.self, from: JSONSerialization.data(withJSONObject: ["league": fields])).league
        }
        #expect(try LeagueRuleOverrides.minimumBlindBid(for: decode(), season: 2026) == 0)
        #expect(try LiveMFLRepository.waiverAvailability(decode(), season: 2026) == nil)
        #expect(try LeagueRuleOverrides.minimumBlindBid(for: decode(), season: 2027) == nil)
        #expect(try LiveMFLRepository.waiverAvailability(decode(), season: 2027) != nil)
        fields["id"] = "99999"
        #expect(try LeagueRuleOverrides.minimumBlindBid(for: decode(), season: 2026) == nil)
        fields["id"] = "41333"
        fields["bbidMinimum"] = "2"
        #expect(try LeagueRuleOverrides.minimumBlindBid(for: decode(), season: 2026) == 2)
    }

    @Test("Blind-bid results separate amount from drop IDs, including zero-dollar no-drop bids")
    func blindBid() {
        let details = TransactionDetails(type: "BBID_WAIVER", fields: ["transaction": .string("101|5|17099,")])
        #expect(details.bid == 5)
        #expect(details.moves == [.init(label: "Added", codes: ["101"]), .init(label: "Dropped", codes: ["17099"])])
        let noDrop = TransactionDetails(type: "BBID_WAIVER", fields: ["transaction": .string("101|0|0000")])
        #expect(noDrop.bid == 0)
        #expect(noDrop.moves == [.init(label: "Added", codes: ["101"])])
        let blank = TransactionDetails(type: "BBID_WAIVER", fields: ["transaction": .string("101|3|")])
        #expect(blank.bid == 3 && blank.moves.count == 1)
    }

    @Test("Free-agent moves use their own add/drop format and never infer a bid")
    func freeAgent() {
        let details = TransactionDetails(type: "FREE_AGENT", fields: ["transaction": .string("101,102,|201,|")])
        #expect(details.moves == [.init(label: "Added", codes: ["101", "102"]), .init(label: "Dropped", codes: ["201"])])
        #expect(details.bid == nil)
        let unsupported = TransactionDetails(type: "WAIVER", fields: ["transaction": .string("101|3|201")])
        #expect(unsupported.moves.isEmpty && unsupported.bid == nil)
    }

    @Test("Trades, IR, and taxi use named fields and preserve the direction of each move")
    func namedFields() {
        let trade = TransactionDetails(type: "TRADE", fields: ["franchise2": .string("0002"),
            "franchise1_gave_up": .string("101,FP_0001_2027_1,"), "franchise2_gave_up": .string("201,BB_5,")])
        #expect(trade.partnerID == "0002")
        #expect(trade.moves == [.init(label: "Sent", codes: ["101", "FP_0001_2027_1"]), .init(label: "Received", codes: ["201", "BB_5"])])
        let ir = TransactionDetails(type: "IR", fields: ["activated": .string("101,"), "deactivated": .string("201,")])
        #expect(ir.moves.map(\.label) == ["Activated from IR", "Placed on IR"])
        let taxi = TransactionDetails(type: "TAXI", fields: ["promoted": .string("101,"), "demoted": .string("201,")])
        #expect(taxi.moves.map(\.label) == ["Promoted from taxi", "Moved to taxi"])
    }

    @Test("Activity and recent waiver results agree on real bid and dropped-player fields")
    func repositoryMapping() async throws {
        let store = MemoryPrivateStore()
        try store.encode(SavedSession(cookie: "synthetic-cookie", season: 2026, leagueID: "41333", franchiseID: "0001"), key: "session")
        let transport = MutationFixtureTransport()
        await transport.setActivity([
            ["id": "1", "type": "BBID_WAIVER", "franchise": "0001", "transaction": "101|5|201,"],
            ["id": "2", "type": "BBID_WAIVER", "franchise": "0002", "transaction": "102|0|0000"],
            ["id": "3", "type": "TRADE", "franchise": "0002", "franchise2": "0001",
             "franchise1_gave_up": "101,", "franchise2_gave_up": "201,"]
        ])
        let repository = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero)
        _ = try await repository.restoreSession()
        let activity = try await repository.loadTransactionActivity()
        let bid = try #require(activity.first { $0.id == "1" })
        #expect(bid.bid == 5)
        #expect(bid.moves.last?.names == "Player Three")
        #expect(activity.first { $0.id == "2" }?.moves.count == 1)
        let trade = try #require(activity.first { $0.id == "3" })
        #expect(trade.teamName == "Fixture Two" && trade.partnerName == "Fixture One")
        #expect(trade.moves.map(\.names) == ["Player One", "Player Three"])
        let results = try await repository.loadWaivers().results
        #expect(results.contains { $0.description.contains("Dropped Player Three") && $0.description.contains("$5.00") })
        #expect(!results.contains { $0.description.contains("Player 0") || $0.description.contains("$201.00") })
    }
}
