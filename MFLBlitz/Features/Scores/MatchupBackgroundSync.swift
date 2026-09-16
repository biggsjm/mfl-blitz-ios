@preconcurrency import ActivityKit
import Foundation
import Observation
import Security

struct MatchupSyncRegistration: Encodable, Sendable {
    var season: Int
    var leagueID: String
    var week: Int
    var homeID: String
    var awayID: String
    var homeAbbreviation: String
    var awayAbbreviation: String
    var precision: Int
    var attributeBytes: Int
    var playerNames: [String: String]
    var playerProfiles: [String: [String: String]] = [:]
    var starterProjections: [String: Double]
    var homeStarterIDs: [String]
    var awayStarterIDs: [String]
    var state: MatchupActivityAttributes.ContentState
    var token = ""
    var revision: Int64 = 0
    var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    enum CodingKeys: String, CodingKey {
        case season, leagueID, week, homeID, awayID, homeAbbreviation, awayAbbreviation
        case precision, attributeBytes, playerNames, state, token, environment, revision
        case starterProjections, homeStarterIDs, awayStarterIDs, playerProfiles
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(season, forKey: .season); try c.encode(leagueID, forKey: .leagueID)
        try c.encode(week, forKey: .week); try c.encode(homeID, forKey: .homeID); try c.encode(awayID, forKey: .awayID)
        try c.encode(homeAbbreviation, forKey: .homeAbbreviation); try c.encode(awayAbbreviation, forKey: .awayAbbreviation)
        try c.encode(attributeBytes, forKey: .attributeBytes); try c.encode(precision, forKey: .precision); try c.encode(playerNames, forKey: .playerNames)
        try c.encode(playerProfiles,forKey:.playerProfiles)
        try c.encode(starterProjections, forKey: .starterProjections)
        try c.encode(homeStarterIDs, forKey: .homeStarterIDs); try c.encode(awayStarterIDs, forKey: .awayStarterIDs)
        try c.encode(state, forKey: .state); try c.encode(token, forKey: .token); try c.encode(environment, forKey: .environment); try c.encode(revision, forKey: .revision)
    }

    init(workspace: LeagueWorkspace, matchup: Matchup, precision: Int, attributes: MatchupActivityAttributes,
         state: MatchupActivityAttributes.ContentState) {
        season = workspace.season; leagueID = workspace.leagueID; week = attributes.week
        homeID = matchup.home.id; awayID = matchup.away.id
        homeAbbreviation = attributes.homeDisplayAbbreviation; awayAbbreviation = attributes.awayDisplayAbbreviation
        self.precision = precision; self.state = state
        attributeBytes = (try? JSONEncoder().encode(attributes).count) ?? 2048
        playerNames = [:]; starterProjections = [:]
        homeStarterIDs = matchup.home.starters.map(\.id).sorted()
        awayStarterIDs = matchup.away.starters.map(\.id).sorted()
        for player in matchup.home.starters + matchup.away.starters {
            playerNames[player.id] = String(player.name.prefix(48))
            playerProfiles[player.id] = ["team":NFLFeedGame.team(player.nflTeam),"position":player.position.uppercased()]
            if let projection = player.projectedPoints, projection.isFinite {
                starterProjections[player.id] = projection
            }
        }
    }
}

private final class MatchupSyncRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct MatchupSyncClient: Sendable {
    struct Receipt: Decodable { var registered: Bool; var pushReady: Bool; var expiresAt: Double }
    struct Status: Decodable {
        var pushReady: Bool
        var productionPushReady: Bool?
        var readyForBuild: Bool {
            #if DEBUG
            pushReady
            #else
            productionPushReady == true
            #endif
        }
        var subscriptions: Int; var acceptedPushes: Int; var issue: String? }
    let origin: URL
    private let session: URLSession

    static func serverURL(_ address: String) throws -> URL {
        guard let parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, host.hasSuffix(".ts.net"),
              host.split(separator: ".").count >= 4, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
              let url = parts.url else { throw SyncError.address }
        return url
    }

    init(address: String, session: URLSession? = nil) throws {
        origin = try Self.serverURL(address)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        self.session = session ?? URLSession(configuration: config, delegate: MatchupSyncRedirectDelegate(), delegateQueue: nil)
    }

    func send(path: String, method: String, secret: String? = nil, body: Data? = nil, maximumBytes: Int = 4096) async throws -> Data {
        var request = URLRequest(url: origin.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method; request.httpBody = body
        request.setValue("1", forHTTPHeaderField: "X-Blitz-Sync")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret { request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= maximumBytes else {
            throw SyncError.connection
        }
        return data
    }

    func register(id: String, secret: String, value: MatchupSyncRegistration) async throws -> Receipt {
        let data = try await send(path: "v1/activities/\(id)", method: "PUT", secret: secret, body: JSONEncoder().encode(value))
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        guard receipt.registered, receipt.expiresAt.isFinite, receipt.expiresAt > Date().timeIntervalSince1970 else { throw SyncError.connection }
        return receipt
    }

    func remove(id: String, secret: String) async throws {
        _ = try await send(path: "v1/activities/\(id)", method: "DELETE", secret: secret)
    }

    func status() async throws -> Status {
        try JSONDecoder().decode(Status.self, from: await send(path: "v1/status", method: "GET"))
    }
    func timeline(season: Int, leagueID: String, week: Int, away: String, home: String) async throws -> MatchupTimelineResponse {
        guard (2020...2100).contains(season),(1...21).contains(week),leagueID.count==5,leagueID.allSatisfy(\.isNumber),
              away.count==4,home.count==4,away.allSatisfy(\.isNumber),home.allSatisfy(\.isNumber),away != home else { throw SyncError.connection }
        let data = try await send(path: "v1/timeline/\(season)/\(leagueID)/\(week)/\(away)/\(home)",method:"GET",maximumBytes:1_500_000)
        let result = try JSONDecoder().decode(MatchupTimelineResponse.self,from:data)
        guard result.schema==1,result.season==season,result.leagueID==leagueID,result.week==week,
              result.teamIDs.sorted()==[away,home].sorted(),result.events.count<=2000,
              result.checkedAt.map { $0.isFinite && $0>0 && $0<=Date().timeIntervalSince1970+30 } ?? true,
              Set(result.events.map(\.id)).count==result.events.count,
              result.events.allSatisfy({ $0.at.isFinite && $0.at>0 && $0.at<=Date().timeIntervalSince1970+30 && $0.name.count<=160 && $0.id.count<=160 && ["tracking","gap","player","team","final"].contains($0.kind) && $0.source=="background" &&
                  ($0.fromAt.map { $0.isFinite && $0 > 0 } ?? true) && ($0.fromAt ?? 0) <= $0.at &&
                  ($0.teamID==nil || [away,home].contains($0.teamID!)) && [$0.previous,$0.current].allSatisfy { $0.map(\.isFinite) ?? true } }) else { throw SyncError.connection }
        return result
    }
}

enum SyncError: LocalizedError {
    case address, connection
    var errorDescription: String? {
        switch self {
        case .address: "Use your private Tailscale HTTPS server address."
        case .connection: "Couldn’t reach background sync. Check Tailscale and try again."
        }
    }
}

/// Only small activity subscriptions leave the device. MFL login cookies,
/// passwords and drafts never enter this transport or its durable cleanup queue.
@MainActor @Observable
final class MatchupBackgroundSync {
    static var supportsPush: Bool {
        #if MFL_BACKGROUND_PUSH
        true
        #else
        false
        #endif
    }
    private(set) var message = "Background sync needs a server."
    private(set) var isRegistered = false
    private(set) var expiresAt: Date?
    private let defaults: UserDefaults
    private let store: any PrivateStore
    private let makeClient: (String) throws -> MatchupSyncClient
    private let archiveKey = "matchup-background-sync.registrations.v1"
    private let secretKey = "matchup-background-sync.secret.v1"
    private var tokenTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var currentID: String?
    private var token: Data?
    private var registration: MatchupSyncRegistration?
    private var generation = 0

    struct Pending: Codable, Equatable {
        var id: String
        var address: String
        var expiresAt: Date = Date().addingTimeInterval(8 * 3600)
    }

    var address: String {
        if let value = defaults.string(forKey: "matchup-background-sync.serverURL") { return value }
        if let value = Bundle.main.object(forInfoDictionaryKey: "MFLBackgroundSyncURL") as? String,
           (try? MatchupSyncClient.serverURL(value)) != nil { return value }
        #if DEBUG
        if let existing = defaults.string(forKey: "nflStatsTest.serverURL"),
           var parts = URLComponents(string: existing), parts.host?.hasSuffix(".ts.net") == true {
            parts.port = 8444; parts.path = ""; parts.query = nil; parts.fragment = nil
            return parts.string ?? ""
        }
        #endif
        return ""
    }

    init(defaults: UserDefaults = .standard, store: any PrivateStore = KeychainPrivateStore(),
         makeClient: @escaping (String) throws -> MatchupSyncClient = { try MatchupSyncClient(address: $0) }) {
        self.defaults = defaults; self.store = store; self.makeClient = makeClient
        if !Self.supportsPush { message = "Apple push setup required for this build." }
    }

    var canRequestPush: Bool { Self.supportsPush && (try? MatchupSyncClient.serverURL(address)) != nil }

    func saveAddress(_ value: String) async throws {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { _ = try MatchupSyncClient.serverURL(cleaned) }
        await stop()
        defaults.set(cleaned, forKey: "matchup-background-sync.serverURL")
        message = Self.supportsPush ? "Open your live matchup to connect." : "Apple push setup required for this build."
    }

    func checkConnection() async {
        do {
            let status = try await makeClient(address).status()
            if !Self.supportsPush { message = "Server reachable. Apple push setup required for this build." }
            else if !status.readyForBuild { message = "Server reachable. Apple push key setup required." }
            else if let issue = status.issue { message = issue }
            else { message = isRegistered ? "Background scoring connected." : "Server ready. Open your live matchup to connect." }
        } catch { message = "Couldn’t reach background sync. Check Tailscale and the server address." }
    }

    func track(_ activity: Activity<MatchupActivityAttributes>, value: MatchupSyncRegistration) {
        guard canRequestPush else { return }
        if currentID != activity.id {
            generation += 1; sendTask?.cancel(); tokenTask?.cancel()
            registration = nil
            currentID = activity.id; token = activity.pushToken; isRegistered = false
            message = "Connecting background scoring…"
            tokenTask = Task { [weak self] in
                for await token in activity.pushTokenUpdates {
                    guard !Task.isCancelled, let self, self.currentID == activity.id else { return }
                    self.token = token
                    self.publish()
                }
            }
        }
        prepareRegistration(value, activityID: activity.id)
        publish()
    }

    /// Also used by the transport regression to provide a delayed ActivityKit
    /// sink without requiring a real Lock Screen activity in the test runner.
    func prepareRegistration(_ value: MatchupSyncRegistration, activityID: String) {
        var value = value
        if currentID == activityID { value.state = value.state.reconciling(with: registration?.state) }
        else { registration = nil }
        currentID = activityID
        registration = value
    }

    func publishArtwork(content: ActivityContent<MatchupActivityAttributes.ContentState>,
                        updateActivity: (ActivityContent<MatchupActivityAttributes.ContentState>) async -> Void,
                        isCurrent: () -> Bool,
                        sendRegistration: ((MatchupSyncRegistration) async throws -> Void)? = nil) async {
        guard isCurrent() else { return }
        // Persist in the pending registration before either asynchronous sink.
        // A token can arrive while ActivityKit is still processing this update.
        if var value = registration {
            value.state = content.state.reconciling(with: value.state)
            registration = value
        }
        await updateActivity(content)
        guard isCurrent(), let value = registration else { return }
        if let sendRegistration { try? await sendRegistration(value) }
        else { publish() }
    }

    private func secret() throws -> String {
        if let data = try store.read(secretKey), let value = String(data: data, encoding: .utf8) { return value }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw StoreError.unavailable }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        try store.write(Data(value.utf8), key: secretKey)
        return value
    }

    private func publish() {
        guard let id = currentID, let token, var value = registration, canRequestPush else { return }
        sendTask?.cancel()
        let generation = generation, address = address
        let prior = defaults.object(forKey: "matchup-background-sync.revision") as? Int64 ?? 0
        value.revision = max(prior + 1, Int64(Date().timeIntervalSince1970 * 1000))
        defaults.set(value.revision, forKey: "matchup-background-sync.revision")
        value.token = token.map { String(format: "%02x", $0) }.joined()
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let secret = try self.secret()
                // Record before transmission so cancellation, uncertain delivery and
                // a process exit still leave enough information to remove it later.
                var saved = try self.store.decode([Pending].self, key: self.archiveKey) ?? []
                let entry = saved.first(where: { $0.id == id && $0.address == address }) ?? Pending(id: id, address: address)
                if !saved.contains(entry) { saved.append(entry); try self.store.encode(saved, key: self.archiveKey) }
                await self.cleanup(except: entry, secret: secret)
                try Task.checkCancellation()
                guard self.generation == generation, self.currentID == id else { return }
                let receipt = try await self.makeClient(address).register(id: id, secret: secret, value: value)
                guard !Task.isCancelled, self.generation == generation, self.currentID == id else { return }
                self.isRegistered = receipt.pushReady
                self.expiresAt = Date(timeIntervalSince1970:receipt.expiresAt)
                self.message = receipt.pushReady ? "Background scoring connected." : "Server reachable. Apple push key setup required."
            } catch {
                guard !Task.isCancelled, self.generation == generation else { return }
                self.isRegistered = false
                self.message = "Background sync couldn’t connect. Scores still update while Blitz is open."
            }
        }
    }

    private func cleanup(except kept: Pending? = nil, secret: String?) async {
        guard let entries = try? store.decode([Pending].self, key: archiveKey) else { return }
        for entry in entries where entry != kept {
            guard !Task.isCancelled else { return }
            do {
                if entry.expiresAt > Date() {
                    guard let secret else { continue }
                    try await makeClient(entry.address).remove(id: entry.id, secret: secret)
                }
                // Re-read after await; a new activity may have been added meanwhile.
                var remaining = try store.decode([Pending].self, key: archiveKey) ?? []
                remaining.removeAll { $0 == entry }
                try store.encode(remaining, key: archiveKey)
            } catch { /* Durable queue retries on next foreground registration/end. */ }
        }
    }

    func stop(id: String? = nil) async {
        if let id, let currentID, id != currentID { return }
        expiresAt = nil
        generation += 1
        let pendingSend = sendTask
        sendTask?.cancel(); sendTask = nil; tokenTask?.cancel(); tokenTask = nil
        currentID = nil; token = nil; registration = nil; isRegistered = false
        // Wait for an in-flight PUT to settle before DELETE to avoid resurrection.
        await pendingSend?.value
        let savedSecret = (try? store.read(secretKey)).flatMap { String(data: $0, encoding: .utf8) }
        let entries = (try? store.decode([Pending].self, key: archiveKey)) ?? []
        let keep = entries.first { $0.id == currentID && $0.address == address }
        await cleanup(except: keep, secret: savedSecret)
        guard currentID == nil else { return }
        message = Self.supportsPush ? "Connects when your matchup is live." : "Apple push setup required for this build."
    }
}
