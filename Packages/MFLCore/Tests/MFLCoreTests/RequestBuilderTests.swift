import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MFLCore

@Suite("MFL request construction")
struct RequestBuilderTests {
    private let builder = MFLAPIRequestBuilder(
        season: 2026,
        userAgent: "MFL Blitz Tests/1.0",
        timeout: 12
    )

    @Test("League URL supplies season, league id, and host")
    func leagueReference() throws {
        let url = try #require(URL(string: "https://www45.myfantasyleague.com/2026/home/41366#0"))
        let reference = try MFLLeagueReference(leagueURL: url)

        #expect(reference.season == 2026)
        #expect(reference.leagueID == "41366")
        #expect(reference.host?.name == "www45.myfantasyleague.com")
    }

    @Test("Login is an HTTPS POST with credentials in the body")
    func loginRequest() throws {
        let request = try builder.makeLoginRequest(username: "coach@example.com", password: "p+a ss&")
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "api.myfantasyleague.com")
        #expect(request.url?.path == "/2026/login")
        #expect(request.url?.query == nil)
        #expect(request.httpMethod == "POST")
        #expect(body.contains("PASSWORD=p%2Ba+ss%26"))
        #expect(body.contains("USERNAME=coach%40example.com"))
        #expect(body.contains("XML=1"))
    }

    @Test("Export has case-sensitive MFL query names and a manual cookie")
    func exportRequest() throws {
        let cookie = try MFLAuthenticationCookie(value: "abc+/==")
        let request = try builder.makeExportRequest(
            endpoint: .liveScoring,
            host: MFLAPIHost.api,
            leagueID: "41366",
            parameters: ["DETAILS": "1", "W": "7"],
            cookie: cookie
        )
        let url = try #require(request.url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(query["TYPE"] == "liveScoring")
        #expect(query["JSON"] == "1")
        #expect(query["L"] == "41366")
        #expect(query["DETAILS"] == "1")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "MFL_USER_ID=abc+/==")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MFL Blitz Tests/1.0")
    }

    @Test("Blind-bid import uses POST form data")
    func importRequest() throws {
        let request = try builder.makeImportRequest(
            endpoint: .blindBidWaiverRequest,
            host: try MFLAPIHost("www45.myfantasyleague.com"),
            leagueID: "41366",
            parameters: [
                "PICKS": "17001_17_16001,17002_8_0000",
                "REPLACE": "1",
                "ROUND": "1",
            ],
            cookie: try MFLAuthenticationCookie(value: "cookie-value")
        )
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        #expect(request.httpMethod == "POST")
        #expect(request.url?.query?.contains("TYPE=blindBidWaiverRequest") == true)
        #expect(request.url?.query?.contains("L=41366") == true)
        #expect(!body.contains("L=41366"))
        #expect(body.contains("PICKS=17001_17_16001%2C17002_8_0000"))
        #expect(body.contains("REPLACE=1"))
    }

    @Test("Non-MFL and insecure hosts are rejected")
    func hostValidation() {
        #expect(throws: MFLCoreError.self) { try MFLAPIHost("https://example.com") }
        #expect(throws: MFLCoreError.self) { try MFLAPIHost("http://www45.myfantasyleague.com") }
    }
}
