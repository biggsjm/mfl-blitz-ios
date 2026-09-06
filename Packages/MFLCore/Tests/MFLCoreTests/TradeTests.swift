import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MFLCore

struct TradeTests {
    @Test("Pending trade direction, trailing commas and singleton/array containers are preserved", arguments: [true, false])
    func pending(singleton: Bool) throws {
        let trade = #"{"trade_id":"0009","offeringteam":"0002","offeredto":"0001","will_give_up":"101,FP_0002_2027_1,","will_receive":"201,BB_10.50,","comments":"A & B","expires":"2000000000"}"#
        let json = "{\"pendingTrades\":{\"pendingTrade\":\(singleton ? trade : "[\(trade)]")}}"
        let value = try JSONDecoder().decode(MFLPendingTradesResponse.self, from: Data(json.utf8))
        let offer = try #require(value.pendingTrades.offers.first)
        #expect(offer.id == "0009")
        #expect(offer.offeredBy == "0002" && offer.offeredTo == "0001")
        #expect(offer.giving == ["101", "FP_0002_2027_1"])
        #expect(offer.receiving == ["201", "BB_10.50"])
        #expect(offer.expires == Date(timeIntervalSince1970: 2_000_000_000))
    }

    @Test("Known empty trade feeds are empty", arguments: [#"{"pendingTrades":{}}"#, #"{"pendingTrades":""}"#, #"{"pendingTrades":{"pendingTrade":[]}}"#, #"{"pendingTrades":{"pendingTrade":""}}"#])
    func empty(json: String) throws { #expect(try JSONDecoder().decode(MFLPendingTradesResponse.self, from: Data(json.utf8)).pendingTrades.offers.isEmpty) }

    @Test("Malformed or unknown trade feeds cannot masquerade as no pending offers", arguments: [
        #"{}"#, #"{"pendingTrades":{"unexpected":[{"id":"1"}]}}"#, #"{"pendingTrades":{"trade":{"id":"1"}}}"#,
        #"{"pendingTrades":{"trade":false}}"#, #"{"pendingTrades":null}"#
    ])
    func malformed(json: String) { #expect(throws: (any Error).self) { try JSONDecoder().decode(MFLPendingTradesResponse.self, from: Data(json.utf8)) } }

    @Test("Asset export preserves ownership, current/future picks, and supported FAAB balance")
    func assets() throws {
        let json = #"{"assets":{"franchise":{"id":"0001","players":{"player":{"id":"001"}},"currentYearDraftPicks":{"draftPick":{"pick":"DP_02_05"}},"futureYearDraftPicks":{"draftPick":{"pick":"FP_0001_2027_2"}},"blindBiddingDollars":{"amount":"18.50"}}}}"#
        let value = try JSONDecoder().decode(MFLTradeAssetsResponse.self, from: Data(json.utf8))
        let assets = try #require(value.assets.franchises.first)
        #expect(assets.codes == ["001", "DP_02_05", "FP_0001_2027_2"])
        #expect(assets.owns("BB_18.50"))
        #expect(!assets.owns("BB_19") && !assets.owns("BB_-1") && !assets.owns("BB_0"))
        #expect(!assets.owns("002"))
    }

    @Test("Unknown trade tokens are not allowed in an import", arguments: ["BB_-1", "BB_1.001", "1,2", "DP_2", "FP_0001_2027_0", "X_123", "<script>"])
    func unsupported(code: String) { #expect(!MFLTradeAssetCode.isSupported(code)) }

    @Test("Trade imports use exact MFL parameters, recipient direction and encoded private messages")
    func proposal() async throws {
        let transport = TradeStub()
        let client = try client(transport)
        try await client.proposeTrade(to: "0002", giving: ["101", "FP_0001_2027_2"], receiving: ["201", "BB_10.50"],
            comments: "A+B & C", expires: Date(timeIntervalSince1970: 2_000_000_000), actingFranchiseID: "0001")
        let request = try #require(await transport.requests.first)
        let body = try #require(String(data: request.httpBody!, encoding: .utf8))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.query?.contains("TYPE=tradeProposal") == true)
        #expect(!request.url!.absoluteString.contains("A+B"))
        #expect(body.contains("OFFEREDTO=0002") && body.contains("FRANCHISE_ID=0001"))
        #expect(body.contains("WILL_GIVE_UP=101%2CFP_0001_2027_2"))
        #expect(body.contains("WILL_RECEIVE=201%2CBB_10.50"))
        #expect(body.contains("COMMENTS=A%2BB+%26+C"))
    }

    @Test("All three trade responses are distinct and only a decline carries comments", arguments: [MFLTradeResponse.accept, .reject, .revoke])
    func response(action: MFLTradeResponse) async throws {
        let transport = TradeStub()
        try await client(transport).respondToTrade(id: "0009", response: action, comments: "No thanks", actingFranchiseID: "0001")
        let request = try #require(await transport.requests.first)
        let body = try #require(String(data: request.httpBody!, encoding: .utf8))
        #expect(body.contains("TRADE_ID=0009") && body.contains("RESPONSE=\(action.rawValue)"))
        #expect(body.contains("COMMENTS=") == (action == .reject))
    }

    @Test("Trade timeouts never retry the write")
    func noRetry() async throws {
        let transport = TradeStub(fail: true)
        await #expect(throws: (any Error).self) { try await client(transport).respondToTrade(id: "9", response: .accept, actingFranchiseID: "0001") }
        #expect(await transport.requests.count == 1)
    }

    private func client(_ transport: TradeStub) throws -> MFLClient {
        MFLClient(configuration: MFLClientConfiguration(league: try MFLLeagueReference(season: 2026, leagueID: "41333", host: MFLAPIHost("www45.myfantasyleague.com")),
            userAgent: "Synthetic trade tests", minimumRequestInterval: .zero), transport: transport,
            authenticationCookie: try MFLAuthenticationCookie(value: "synthetic-cookie"))
    }
}

private actor TradeStub: MFLHTTPTransport {
    var requests: [URLRequest] = []
    let fail: Bool
    init(fail: Bool = false) { self.fail = fail }
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        requests.append(request)
        if fail { throw URLError(.timedOut) }
        return MFLHTTPResponse(data: Data(#"{"status":"OK"}"#.utf8), statusCode: 200, url: request.url)
    }
}
