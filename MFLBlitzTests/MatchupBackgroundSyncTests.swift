import Foundation
import Testing
@testable import MFLBlitz

private final class SyncURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var sentBodies: [Data] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        var sent = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while sent.count < 16000 {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                sent.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.sentBodies.append(sent)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@Suite(.serialized) @MainActor struct MatchupBackgroundSyncTests {
    static let address = "https://test.example.ts.net:8444"

    private func client(status: Int = 200, response: String = "{}") throws -> MatchupSyncClient {
        SyncURLProtocol.requests = []; SyncURLProtocol.sentBodies = []; SyncURLProtocol.status = status
        SyncURLProtocol.body = Data(response.utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SyncURLProtocol.self]
        return try MatchupSyncClient(address: Self.address, session: URLSession(configuration: config))
    }

    @Test func acceptsOnlyPrivateHTTPSOrigins() throws {
        for address in ["http://test.example.ts.net", "https://example.com", "https://user:key@test.example.ts.net",
                        "https://test.example.ts.net?token=private", "https://test.example.ts.net/path",
                        "https://test.example.ts.net#fragment", "https://test.example.ts.net.evil.com"] {
            #expect(throws: (any Error).self) { try MatchupSyncClient.serverURL(address) }
        }
        #expect(try MatchupSyncClient.serverURL(Self.address).port == 8444)
    }

    @Test func registrationIncludesOnlyStarterProjectionInputs() throws {
        var matchup = SampleData.scores.matchups[0]
        matchup.home.starters[0].projectedPoints = 18.5
        matchup.home.bench[0].projectedPoints = 999
        let attributes = MatchupActivityAttributes(scope: "test", week: 1, matchupID: matchup.id,
            homeName: "H", awayName: "A", homeAbbreviation: "H", awayAbbreviation: "A")
        let state = MatchupActivityAttributes.ContentState(homeScore: "3.0", awayScore: "4.0", activePlayers: 2, updatedAt: .now)
        let registration = MatchupSyncRegistration(workspace: SampleData.workspace, matchup: matchup,
            precision: 1, attributes: attributes, state: state)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(registration)) as? [String: Any])
        let projections = try #require(object["starterProjections"] as? [String: Double])
        #expect(projections[matchup.home.starters[0].id] == 18.5)
        #expect(projections[matchup.home.bench[0].id] == nil)
        #expect(object["homeStarterIDs"] as? [String] == matchup.home.starters.map(\.id).sorted())
    }

    private func artworkRegistration() -> MatchupSyncRegistration {
        let matchup = SampleData.scores.matchups[0]
        let attributes = MatchupActivityAttributes(scope: "synthetic", week: 1, matchupID: matchup.id,
            homeName: "Home", awayName: "Away", homeAbbreviation: "H", awayAbbreviation: "A")
        return MatchupSyncRegistration(workspace: SampleData.workspace, matchup: matchup, precision: 1,
            attributes: attributes, state: .init(homeScore: "3.0", awayScore: "4.0", activePlayers: 2, updatedAt: .now))
    }

    @Test func preparedArtworkReachesHTTPWhileActivityKitReadbackStillHasNoArtwork() async throws {
        let client = try client(response: "{\"registered\":true,\"pushReady\":true,\"expiresAt\":\(Date().timeIntervalSince1970 + 3600)}")
        let sync = MatchupBackgroundSync(store: PreviewPrivateStore())
        let registration = artworkRegistration()
        sync.prepareRegistration(registration, activityID: "one")
        let laggingReadback = registration.state
        var prepared = registration.state
        let red = MatchupActivityAttributes.Artwork(imageData: Data("home-logo".utf8), red: 0.7, green: 0.1, blue: 0.2)
        let orange = MatchupActivityAttributes.Artwork(imageData: Data("away-logo".utf8), red: 0.7, green: 0.3, blue: 0.1)
        prepared.homeArtwork = red; prepared.awayArtwork = orange
        var rendered: MatchupActivityAttributes.ContentState?
        await sync.publishArtwork(content: .init(state: prepared, staleDate: .now.addingTimeInterval(210)),
            updateActivity: { content in
                rendered = content.state
                // Model ActivityKit accepting/rendering the update before its
                // observable content property has caught up, as on the phone.
                #expect(laggingReadback.homeArtwork == nil)
            }, isCurrent: { true }, sendRegistration: { value in
                _ = try await client.register(id: "one", secret: "synthetic", value: value)
            })
        #expect(SyncURLProtocol.requests.last?.httpMethod == "PUT")
        let body = try #require(SyncURLProtocol.sentBodies.last)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let posted = try #require(json["state"] as? [String: Any])
        let decoded = try JSONDecoder().decode(MatchupActivityAttributes.ContentState.self, from: JSONSerialization.data(withJSONObject: posted))
        #expect(rendered?.homeArtwork == red && rendered?.awayArtwork == orange)
        #expect(decoded.homeArtwork == red && decoded.awayArtwork == orange)
        #expect(decoded.updatedAt == prepared.updatedAt)
    }

    @Test func newerScoreDuringArtworkPublicationKeepsArtworkInNextRegistration() async throws {
        let client = try client(response: "{\"registered\":true,\"pushReady\":true,\"expiresAt\":\(Date().timeIntervalSince1970 + 3600)}")
        let sync = MatchupBackgroundSync(store: PreviewPrivateStore())
        let initial = artworkRegistration()
        sync.prepareRegistration(initial, activityID: "one")
        var prepared = initial.state
        prepared.homeArtwork = .init(imageData: Data("logo".utf8), red: 0.7, green: 0.1, blue: 0.2)
        await sync.publishArtwork(content: .init(state: prepared, staleDate: nil), updateActivity: { _ in
            var newer = initial
            newer.state.updatedAt = initial.state.updatedAt.addingTimeInterval(90)
            newer.state.homeScore = "9.0"
            sync.prepareRegistration(newer, activityID: "one")
        }, isCurrent: { true }, sendRegistration: { value in
            _ = try await client.register(id: "one", secret: "synthetic", value: value)
        })
        let body = try #require(SyncURLProtocol.sentBodies.last)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        #expect(state["homeScore"] as? String == "9.0")
        #expect((state["homeArtwork"] as? [String: Any])?["thumbnail"] != nil)
    }

    @Test func artworkPublicationCannotCrossAnActivityReplacement() async {
        let sync = MatchupBackgroundSync(store: PreviewPrivateStore())
        let initial = artworkRegistration()
        sync.prepareRegistration(initial, activityID: "one")
        var prepared = initial.state
        prepared.homeArtwork = .init(imageData: Data("logo".utf8), red: 0.7, green: 0.1, blue: 0.2)
        var current = true, sent = false
        await sync.publishArtwork(content: .init(state: prepared, staleDate: nil), updateActivity: { _ in
            sync.prepareRegistration(initial, activityID: "two")
            current = false
        }, isCurrent: { current }, sendRegistration: { _ in sent = true })
        #expect(!sent)
        await sync.publishArtwork(content: .init(state: initial.state, staleDate: nil), updateActivity: { _ in },
            isCurrent: { true }, sendRegistration: { value in
                #expect(value.state.homeArtwork == nil)
                sent = true
            })
        #expect(sent)
    }

    @Test func statusAndRemovalDoNotSendMFLCookies() async throws {
        let client = try client(response: "{\"pushReady\":true,\"subscriptions\":1,\"acceptedPushes\":2}")
        let status = try await client.status()
        #expect(status.pushReady)
        try await client.remove(id: "activity-1", secret: String(repeating: "a", count: 64))
        #expect(SyncURLProtocol.requests.count == 2)
        let request = try #require(SyncURLProtocol.requests.last)
        #expect(request.url?.path == "/v1/activities/activity-1")
        #expect(request.httpMethod == "DELETE")
        #expect(request.value(forHTTPHeaderField: "X-Blitz-Sync") == "1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(String(repeating: "a", count: 64))")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.url?.query == nil)
    }

    @Test func HTTPFailuresAndRedirectsAreNotSuccess() async throws {
        for status in [302, 400, 403, 429, 503] {
            let client = try client(status: status)
            await #expect(throws: (any Error).self) { try await client.remove(id: "one", secret: "key") }
            #expect(SyncURLProtocol.requests.count == 1)
        }
    }

    @Test func decodesServerAPNsContentStateUsingAppleReferenceDate() throws {
        let json = #"{"aps":{"timestamp":1789322400,"event":"update","stale-date":1789322610,"content-state":{"homeScore":"9.0","awayScore":"4.0","activePlayers":2,"updatedAt":811015200,"latestChange":{"text":"First Player +6.0 pts · HOME","checkedAt":811015200},"phase":"live","homeArtwork":{"red":0.7,"green":0.1,"blue":0.2,"thumbnail":"eA=="}}}}"#
        struct Envelope: Decodable {
            struct APS: Decodable {
                var state: MatchupActivityAttributes.ContentState
                enum CodingKeys: String, CodingKey { case state = "content-state" }
            }
            var aps: APS
        }
        let value = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).aps.state
        #expect(value.updatedAt.timeIntervalSince1970 == 1789322400)
        #expect(value.latestChange?.checkedAt == value.updatedAt)
        #expect(value.homeArtwork?.imageData == Data("x".utf8))
        #expect(value.phase == "live")
    }

    @Test func pendingDeletionSurvivesFailureAndRetries() async throws {
        let store = PreviewPrivateStore()
        let defaults = try #require(UserDefaults(suiteName: "sync-tests-\(UUID())"))
        let client = try client(status: 503)
        let entry = MatchupBackgroundSync.Pending(id: "old-activity", address: Self.address)
        try store.encode([entry], key: "matchup-background-sync.registrations.v1")
        store.write(Data(String(repeating: "a", count: 64).utf8), key: "matchup-background-sync.secret.v1")
        let sync = MatchupBackgroundSync(defaults: defaults, store: store, makeClient: { _ in client })
        await sync.stop()
        #expect(try store.decode([MatchupBackgroundSync.Pending].self, key: "matchup-background-sync.registrations.v1")?.count == 1)
        SyncURLProtocol.status = 200
        await sync.stop()
        #expect(try store.decode([MatchupBackgroundSync.Pending].self, key: "matchup-background-sync.registrations.v1")?.isEmpty == true)
        #expect(SyncURLProtocol.requests.map(\.httpMethod) == ["DELETE", "DELETE"])
    }

    @Test func endingWithoutRegistrationDoesNotCreateCredentialsOrContactServer() async throws {
        let store = PreviewPrivateStore()
        let client = try client()
        let sync = MatchupBackgroundSync(store: store, makeClient: { _ in client })
        await sync.stop()
        #expect(store.read("matchup-background-sync.secret.v1") == nil)
        #expect(SyncURLProtocol.requests.isEmpty)
    }

    @Test func expiredDeletionQueueIsPurgedWithoutNetwork() async throws {
        let store = PreviewPrivateStore()
        let client = try client()
        let entry = MatchupBackgroundSync.Pending(id: "expired", address: Self.address, expiresAt: .distantPast)
        try store.encode([entry], key: "matchup-background-sync.registrations.v1")
        let sync = MatchupBackgroundSync(store: store, makeClient: { _ in client })
        await sync.stop()
        #expect(SyncURLProtocol.requests.isEmpty)
        #expect(try store.decode([MatchupBackgroundSync.Pending].self, key: "matchup-background-sync.registrations.v1")?.isEmpty == true)
    }
}
