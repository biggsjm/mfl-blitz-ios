import Foundation
import Testing
@testable import MFLBlitz

private final class BetaAccessProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var receipt = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.receipt)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct BetaServiceAccessTests {
    @Test func accessCodeOnlyGoesToIssuingOriginWhileUnexpired() throws {
        let store = MemoryPrivateStore()
        let access = BetaServiceAccess(origin: "https://test.example.ts.net:10000", code: String(repeating: "a", count: 43),
            season: 2026, leagueID: "12345", franchiseID: "0001", expiresAt: 20000)
        try store.encode(access, key: BetaServiceAccess.key)
        for url in ["https://test.example.ts.net:8444/v1/status", "https://other.example.ts.net:10000/v1/status",
                    "http://test.example.ts.net:10000/v1/status", "https://test.example.ts.net.evil.invalid:10000/v1/status"] {
            var request = URLRequest(url: URL(string: url)!)
            BetaServiceAccess.authorize(&request, store: store, now: Date(timeIntervalSince1970: 10000))
            #expect(request.value(forHTTPHeaderField: "X-Blitz-Access") == nil)
        }
        var request = URLRequest(url: URL(string: "https://test.example.ts.net:10000/v1/status")!)
        BetaServiceAccess.authorize(&request, store: store, now: Date(timeIntervalSince1970: 20001))
        #expect(request.value(forHTTPHeaderField: "X-Blitz-Access") == nil)
        BetaServiceAccess.authorize(&request, store: store, now: Date(timeIntervalSince1970: 10000))
        #expect(request.value(forHTTPHeaderField: "X-Blitz-Access") == access.code)
    }

    @Test @MainActor func enrollmentCredentialIsStableForRetryAndSeparateForTeams() throws {
        let store = MemoryPrivateStore()
        let first = try BetaServiceAccess.deviceCredential(workspace: SampleData.workspace, store: store)
        let second = try BetaServiceAccess.deviceCredential(workspace: SampleData.workspace, store: store)
        #expect(first == second)
        #expect(first.count == 43)
        #expect(first.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
    }

    @Test @MainActor func automaticConnectionUsesOnlyTrustedOriginAndMatchingSession() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BetaAccessProtocol.self]
        let session = URLSession(configuration: config)
        let workspace = SampleData.workspace
        let saved = SavedSession(cookie: "synthetic-session", season: workspace.season, leagueID: workspace.leagueID, franchiseID: workspace.franchiseID)
        BetaAccessProtocol.receipt = try JSONSerialization.data(withJSONObject: ["season": workspace.season,
            "leagueID": workspace.leagueID, "franchiseID": workspace.franchiseID,
            "expiresAt": Date().addingTimeInterval(3600).timeIntervalSince1970])
        let access = try await BetaServiceAccess.connect(savedSession: saved, deviceCredential: String(repeating: "a", count: 43),
            address: BetaServiceAccess.trustedOrigin, workspace: workspace, session: session)
        #expect(access.franchiseID == workspace.franchiseID)
        #expect(BetaAccessProtocol.lastRequest?.url?.path == "/v1/access")
        #expect(BetaAccessProtocol.lastRequest?.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(BetaAccessProtocol.lastRequest?.httpMethod == "POST")
        await #expect(throws: BetaServiceAccess.AccessError.connection) {
            try await BetaServiceAccess.connect(savedSession: saved, deviceCredential: String(repeating: "a", count: 43),
                address: "https://other.example.ts.net:10000", workspace: workspace, session: session)
        }
        var other = saved; other.franchiseID = "other"
        await #expect(throws: BetaServiceAccess.AccessError.wrongTeam) {
            try await BetaServiceAccess.connect(savedSession: other, deviceCredential: String(repeating: "a", count: 43),
                address: BetaServiceAccess.trustedOrigin, workspace: workspace, session: session)
        }
        BetaAccessProtocol.receipt = try JSONSerialization.data(withJSONObject: ["season": workspace.season,
            "leagueID": workspace.leagueID, "franchiseID": "other", "expiresAt": Date().addingTimeInterval(3600).timeIntervalSince1970])
        await #expect(throws: BetaServiceAccess.AccessError.wrongTeam) {
            try await BetaServiceAccess.connect(savedSession: saved, deviceCredential: String(repeating: "a", count: 43),
                address: BetaServiceAccess.trustedOrigin, workspace: workspace, session: session)
        }
    }
}
