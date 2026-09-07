import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MFLCore

struct LeagueExtrasTests {
    @Test("Trading Block accepts owner-provided empty and camel-case singleton shapes")
    func tradingBlockShapes() throws {
        let empty = try decodeBlock(#"{"tradeBaits":{},"version":"1.0"}"#)
        #expect(empty.listings.isEmpty)
        let listing = try decodeBlock(#"{"tradeBaits":{"tradeBait":{"willGiveUp":"101","franchise_id":"0001","inExchangeFor":"","timestamp":"1788807495"}}}"#)
        #expect(listing.listings.first?.codes == ["101"])
        #expect(listing.listings.first?.lookingFor == "")
        let roundTrip = try JSONDecoder().decode(MFLTradingBlock.self, from: JSONEncoder().encode(listing))
        #expect(roundTrip == listing)
    }

    @Test("Arrays preserve unknown assets; malformed listings never become empty", arguments: [
        #"{"tradeBaits":{"unexpected":[]}}"#,
        #"{"tradeBaits":{"tradeBait":{"franchise_id":"0001","willGiveUp":"101"}}}"#,
        #"{"tradeBaits":{"tradeBait":{"franchise_id":"0001","willGiveUp":"101,101","inExchangeFor":""}}}"#
    ])
    func malformedBlock(_ json: String) {
        #expect(throws: (any Error).self) { try decodeBlock(json) }
    }

    @Test func blockArray() throws {
        let source = #"{"tradeBaits":{"tradeBait":[{"franchise_id":"0001","willGiveUp":"101,UNKNOWN_CODE","inExchangeFor":"RB & WR"},{"franchise_id":"0002","willGiveUp":"DP_02_05,FP_0001_2027_2,BB_10","inExchangeFor":"Picks"}]}}"#
        let result = try decodeBlock(source)
        #expect(result.listings.count == 2)
        #expect(result.listings[0].codes.contains("UNKNOWN_CODE"))
        #expect(result.listings[1].codes.count == 3)
    }

    @Test("Calendar JSON round trips and validates exact epoch dates")
    func calendarShapes() throws {
        let source = #"{"calendar":{"event":{"id":"1","type":"WAIVER_BBID","start_time":"1789578000","end_time":"","happens":"16","title":""}}}"#
        let calendar = try JSONDecoder().decode(MFLLeagueCalendarResponse.self, from: Data(source.utf8)).calendar
        #expect(calendar.events.first?.start == Date(timeIntervalSince1970: 1789578000))
        #expect(calendar.events.first?.repetitions == 16)
        #expect(try JSONDecoder().decode(MFLLeagueCalendar.self, from: JSONEncoder().encode(calendar)) == calendar)
    }

    @Test("Invalid dates or repetition counts are rejected", arguments: ["nan", "inf", "-1", "1e100", "wrong"])
    func malformedCalendar(_ date: String) {
        let json = "{\"calendar\":{\"event\":{\"id\":\"1\",\"type\":\"TRADE\",\"start_time\":\"\(date)\"}}}"
        #expect(throws: (any Error).self) { try JSONDecoder().decode(MFLLeagueCalendarResponse.self, from: Data(json.utf8)) }
    }

    @Test("Explicit ICS occurrences preserve the published DST shift without recurrence guessing")
    func publishedDST() throws {
        let date = Date(timeIntervalSince1970: 1793206800) // 2026-10-28 17:00 UTC
        let calendar = MFLLeagueCalendar(events: [.init(id: "1", type: "WAIVER_BBID", start: date, repetitions: 2)])
        let ics = Self.ics([("1", "20261028T170000"), ("generated-a", "20261104T180000"), ("generated-b", "20261111T180000")])
        let result = MFLCalendarOccurrences(calendar: calendar, ics: ics)
        #expect(result.recurrenceVerified)
        #expect(result.events.count == 3)
        #expect(result.events[1].start.timeIntervalSince(result.events[0].start) == 7 * 86_400 + 3600)
        #expect(result.events.map(\.id) == ["1:0", "1:1", "1:2"])
        let regenerated = ics.replacingOccurrences(of: "generated-a", with: "new-a").replacingOccurrences(of: "generated-b", with: "new-b")
        #expect(MFLCalendarOccurrences(calendar: calendar, ics: regenerated).events == result.events)
    }

    @Test("Mismatched anchors, missing occurrences and unsupported time zones stay partial")
    func unsafeRecurrence() {
        let source = MFLLeagueCalendar(events: [.init(id: "1", type: "WAIVER_BBID", start: Date(timeIntervalSince1970: 1793206800), repetitions: 1)])
        let valid = Self.ics([("1", "20261028T170000"), ("2", "20261104T180000")])
        for ics in [valid.replacingOccurrences(of: "20261028T170000", with: "20261028T160000"),
                    Self.ics([("1", "20261028T170000")]),
                    valid.replacingOccurrences(of: "DTSTART:", with: "DTSTART;TZID=America/New_York:"),
                    valid.replacingOccurrences(of: "END:VEVENT", with: "RRULE:FREQ=WEEKLY\nEND:VEVENT")] {
            let result = MFLCalendarOccurrences(calendar: source, ics: ics)
            #expect(!result.recurrenceVerified)
            #expect(result.events.count == 1)
        }
    }

    @Test("Import is encoded in one POST; empty removals and new cash assets are rejected")
    func blockImport() async throws {
        let transport = ExtrasCoreTransport()
        let client = try client(transport)
        try await client.publishTradingBlock(codes: ["101", "DP_02_05"], lookingFor: "RB & WR + picks")
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.query?.contains("WILL_GIVE_UP") == false)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("RB%20%26%20WR%20%2B%20picks") || body.contains("RB+%26+WR+%2B+picks"))
        for codes: Set<String> in [[], ["BB_10"], ["unsupported"]] {
            await #expect(throws: (any Error).self) { try await client.publishTradingBlock(codes: codes, lookingFor: "") }
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("Calendar display, typed reader and refresh use one cached endpoint")
    func sharedCalendarRead() async throws {
        let transport = ExtrasCoreTransport()
        let client = try client(transport)
        _ = try await client.calendar()
        _ = try await client.leagueCalendar()
        _ = try await client.calendarOccurrences()
        #expect(await transport.requests.count == 1)
        _ = try await client.leagueCalendar(refreshPolicy: .reloadIgnoringCache)
        #expect(await transport.requests.count == 2)
    }

    private func decodeBlock(_ text: String) throws -> MFLTradingBlock {
        try JSONDecoder().decode(MFLTradingBlockResponse.self, from: Data(text.utf8)).tradeBaits
    }
    private func client(_ transport: ExtrasCoreTransport) throws -> MFLClient {
        MFLClient(configuration: MFLClientConfiguration(league: try MFLLeagueReference(season: 2026, leagueID: "12345", host: MFLAPIHost("www45.myfantasyleague.com")), userAgent: "Tests", minimumRequestInterval: .zero), transport: transport,
            authenticationCookie: try MFLAuthenticationCookie(value: "synthetic-cookie"))
    }
    static func ics(_ rows: [(String, String)]) -> String {
        "BEGIN:VCALENDAR\nVERSION:2.0\n" + rows.map { id, date in
            "BEGIN:VEVENT\nUID:\(id)@myfantasyleague.com\nSUMMARY:Process Blind Bid Waivers\nDTSTART:\(date)\nDTEND:\(date)\nEND:VEVENT\n"
        }.joined() + "END:VCALENDAR\n"
    }
}

private actor ExtrasCoreTransport: MFLHTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) -> MFLHTTPResponse {
        requests.append(request)
        let json = request.httpMethod == "POST" ? #"{"status":"OK"}"# : #"{"calendar":{}}"#
        return MFLHTTPResponse(data: Data(json.utf8), statusCode: 200, url: request.url)
    }
}
