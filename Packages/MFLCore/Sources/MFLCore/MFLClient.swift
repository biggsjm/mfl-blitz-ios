import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct MFLHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]
    public let url: URL?

    public init(data: Data, statusCode: Int, headers: [String: String] = [:], url: URL? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        self.url = url
    }

    public init(data: Data, response: HTTPURLResponse) {
        self.init(
            data: data,
            statusCode: response.statusCode,
            headers: Dictionary(uniqueKeysWithValues: response.allHeaderFields.compactMap { key, value in
                guard let key = key as? String else { return nil }
                return (key, String(describing: value))
            }),
            url: response.url
        )
    }

    public func value(forHeader name: String) -> String? {
        headers[name.lowercased()]
    }
}

public protocol MFLHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse
}

public struct MFLURLSessionTransport: MFLHTTPTransport, Sendable {
    private let session: URLSession

    /// Creates an isolated transport that never persists cookies and never
    /// follows redirects. This is especially important for login and imports:
    /// Foundation must not replay credentials or `MFL_USER_ID` on another URL.
    public init(configuration: URLSessionConfiguration? = nil) {
        let hardenedConfiguration: URLSessionConfiguration
        if let configuration,
           let copiedConfiguration = configuration.copy() as? URLSessionConfiguration
        {
            hardenedConfiguration = copiedConfiguration
        } else {
            hardenedConfiguration = .ephemeral
        }
        hardenedConfiguration.httpCookieStorage = nil
        hardenedConfiguration.httpShouldSetCookies = false
        hardenedConfiguration.httpCookieAcceptPolicy = .never
        hardenedConfiguration.urlCache = nil
        hardenedConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(
            configuration: hardenedConfiguration,
            delegate: MFLRedirectBlockingDelegate(),
            delegateQueue: nil
        )
    }

    public func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MFLCoreError.invalidResponse
        }
        return MFLHTTPResponse(data: data, response: httpResponse)
    }
}

private final class MFLRedirectBlockingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Actor-isolated API client for one MFL league and season.
///
/// The actor owns its short-lived host lookup, response cache, cookie, and
/// one-second request gate. It never automatically retries a failed or 429
/// request, matching MFL's published guidance.
public actor MFLClient {
    public let configuration: MFLClientConfiguration

    private let transport: any MFLHTTPTransport
    private let requestBuilder: MFLAPIRequestBuilder
    private let responseDecoder = MFLResponseDecoder()
    private let clock = ContinuousClock()

    private var cookie: MFLAuthenticationCookie?
    private var leagueHost: MFLAPIHost?
    private var nextRequestInstant: ContinuousClock.Instant?
    private var cache: [CacheKey: CacheEntry] = [:]

    public init(
        configuration: MFLClientConfiguration,
        transport: any MFLHTTPTransport = MFLURLSessionTransport(),
        authenticationCookie: MFLAuthenticationCookie? = nil
    ) {
        self.configuration = configuration
        self.transport = transport
        requestBuilder = MFLAPIRequestBuilder(
            season: configuration.league.season,
            userAgent: configuration.userAgent,
            timeout: configuration.requestTimeout
        )
        cookie = authenticationCookie
        leagueHost = configuration.league.host
    }

    // MARK: Authentication

    /// Authenticates with MFL via an HTTPS POST. The password is used only to
    /// construct this request and is never retained by the client.
    @discardableResult
    public func authenticate(username: String, password: String) async throws -> MFLAuthenticationCookie {
        guard !username.isEmpty, !password.isEmpty else {
            throw MFLCoreError.authenticationFailed("Username and password are required.")
        }

        let request = try requestBuilder.makeLoginRequest(username: username, password: password)
        let response = try await send(request)
        try validateSensitiveResponseOrigin(response, for: request)
        try validateHTTP(response)
        let parsedCookie = try Self.parseLoginCookie(response.data)
        cookie = parsedCookie
        cache.removeAll(keepingCapacity: true)
        return parsedCookie
    }

    /// Installs a previously saved MFL cookie, normally read from the app's Keychain.
    /// Pass `nil` to log out locally. MFL has no server-side logout endpoint.
    public func setAuthenticationCookie(_ cookie: MFLAuthenticationCookie?) {
        self.cookie = cookie
        cache.removeAll(keepingCapacity: true)
    }

    public func authenticationCookie() -> MFLAuthenticationCookie? {
        cookie
    }

    /// Selects an already validated league host, such as the host returned by
    /// the authenticated `myleagues` export.
    public func setLeagueHost(_ host: MFLAPIHost) {
        leagueHost = host
        cache.removeAll(keepingCapacity: true)
    }

    // MARK: Host discovery

    /// Resolves and retains the league's current `wwwXX` host for this client session.
    @discardableResult
    public func discoverLeagueHost(forceRefresh: Bool = false) async throws -> MFLAPIHost {
        if let leagueHost, !forceRefresh { return leagueHost }

        let response: MFLLeagueResponse = try await export(
            MFLLeagueResponse.self,
            endpoint: .league,
            host: .api,
            leagueID: configuration.league.leagueID,
            parameters: [:],
            ttl: configuration.cacheDurations.league,
            refreshPolicy: forceRefresh ? .reloadIgnoringCache : .useCache
        )
        guard let baseURL = response.league.baseURL else {
            if let leagueHost { return leagueHost }
            throw MFLCoreError.invalidResponse
        }
        let discovered = try MFLAPIHost(baseURL)
        leagueHost = discovered
        return discovered
    }

    // MARK: Reads

    /// Returns the signed-in user's leagues for this client's season. Besides
    /// enabling a future league picker, this is the authoritative mapping from
    /// an account to its franchise id and current league host.
    public func myLeagues(
        includeFranchiseNames: Bool = true,
        refreshPolicy: MFLRefreshPolicy = .useCache
    ) async throws -> MFLUserLeagueCollection {
        guard cookie != nil else {
            throw MFLCoreError.unauthorized("Sign in to load your MFL leagues.")
        }
        var parameters = ["YEAR": String(configuration.league.season)]
        if includeFranchiseNames { parameters["FRANCHISE_NAMES"] = "1" }
        let response: MFLMyLeaguesResponse = try await export(
            MFLMyLeaguesResponse.self,
            endpoint: .myleagues,
            host: .api,
            leagueID: nil,
            parameters: parameters,
            ttl: configuration.cacheDurations.league,
            refreshPolicy: refreshPolicy
        )
        return response.leagues
    }

    public func league(refreshPolicy: MFLRefreshPolicy = .useCache) async throws -> MFLLeague {
        let host = leagueHost ?? .api
        let response: MFLLeagueResponse = try await export(
            MFLLeagueResponse.self,
            endpoint: .league,
            host: host,
            leagueID: configuration.league.leagueID,
            parameters: [:],
            ttl: configuration.cacheDurations.league,
            refreshPolicy: refreshPolicy
        )
        if let baseURL = response.league.baseURL {
            leagueHost = try MFLAPIHost(baseURL)
        }
        return response.league
    }

    /// Loads MFL's player-id translation table from the shared API host.
    /// The default 24-hour cache reflects MFL's documented once-daily update cadence.
    public func players(
        ids: [String] = [],
        details: Bool = false,
        changedSince: Date? = nil,
        refreshPolicy: MFLRefreshPolicy = .useCache
    ) async throws -> MFLPlayerCatalog {
        try ids.forEach(validateIdentifier)
        var parameters: [String: String] = [:]
        if !ids.isEmpty { parameters["PLAYERS"] = ids.joined(separator: ",") }
        if details { parameters["DETAILS"] = "1" }
        if let changedSince {
            parameters["SINCE"] = String(Int(changedSince.timeIntervalSince1970))
        }
        let response: MFLPlayersResponse = try await export(
            MFLPlayersResponse.self,
            endpoint: .players,
            host: .api,
            leagueID: nil,
            parameters: parameters,
            ttl: configuration.cacheDurations.players,
            refreshPolicy: refreshPolicy
        )
        return response.players
    }

    public func rosters(
        franchiseID: String? = nil,
        week: Int? = nil,
        refreshPolicy: MFLRefreshPolicy = .useCache
    ) async throws -> MFLRosterCollection {
        var parameters: [String: String] = [:]
        if let franchiseID {
            try validateIdentifier(franchiseID)
            parameters["FRANCHISE"] = franchiseID
        }
        if let week {
            try validateWeek(week)
            parameters["W"] = String(week)
        }
        let response: MFLRostersResponse = try await export(
            MFLRostersResponse.self,
            endpoint: .rosters,
            host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID,
            parameters: parameters,
            ttl: configuration.cacheDurations.rosters,
            refreshPolicy: refreshPolicy
        )
        return response.rosters
    }

    /// Returns MFL's roster assignments and optional eligibility flags for the
    /// requested player ids. MFL requires at least one id in `P`; `week` selects
    /// the lineup week. `franchiseID` is sent as MFL's optional `F` context for
    /// deluxe leagues; callers still select the desired roster assignment.
    public func playerRosterStatus(
        playerIDs: [String],
        week: Int? = nil,
        franchiseID: String? = nil,
        refreshPolicy: MFLRefreshPolicy = .useCache
    ) async throws -> MFLPlayerRosterStatusCollection {
        guard !playerIDs.isEmpty else {
            throw MFLCoreError.invalidRequest("At least one player id is required for roster status.")
        }
        try playerIDs.forEach(validateIdentifier)
        guard Set(playerIDs).count == playerIDs.count else {
            throw MFLCoreError.invalidRequest("Player ids for roster status must be unique.")
        }

        var parameters = ["P": playerIDs.joined(separator: ",")]
        if let week {
            try validateWeek(week)
            parameters["W"] = String(week)
        }
        if let franchiseID {
            try validateIdentifier(franchiseID)
            parameters["F"] = franchiseID
        }

        let response: MFLPlayerRosterStatusesResponse = try await export(
            MFLPlayerRosterStatusesResponse.self,
            endpoint: .playerRosterStatus,
            host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID,
            parameters: parameters,
            ttl: configuration.cacheDurations.playerRosterStatus,
            refreshPolicy: refreshPolicy
        )
        return response.playerRosterStatuses
    }

    /// Returns players currently available to add. Join each result's `id`
    /// against `players(ids:)` for names, NFL teams, and positions.
    public func freeAgents(
        position: String? = nil,
        refreshPolicy: MFLRefreshPolicy = .useCache
    ) async throws -> MFLFreeAgentPool {
        var parameters: [String: String] = [:]
        if let position {
            let normalized = position.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !normalized.contains(","), !normalized.contains("\n") else {
                throw MFLCoreError.invalidRequest("The free-agent position filter is invalid.")
            }
            parameters["POSITION"] = normalized
        }
        let response: MFLFreeAgentsResponse = try await export(
            MFLFreeAgentsResponse.self,
            endpoint: .freeAgents,
            host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID,
            parameters: parameters,
            ttl: configuration.cacheDurations.freeAgents,
            refreshPolicy: refreshPolicy
        )
        return response.freeAgents
    }

    public func liveScoring(
        week: Int? = nil,
        includeBench: Bool = false,
        refreshPolicy: MFLRefreshPolicy = .useCache
    ) async throws -> MFLLiveScoring {
        var parameters: [String: String] = [:]
        if let week {
            try validateWeek(week)
            parameters["W"] = String(week)
        }
        if includeBench { parameters["DETAILS"] = "1" }
        let response: MFLLiveScoringResponse = try await export(
            MFLLiveScoringResponse.self,
            endpoint: .liveScoring,
            host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID,
            parameters: parameters,
            ttl: configuration.cacheDurations.liveScoring,
            refreshPolicy: refreshPolicy
        )
        return response.liveScoring
    }

    public func standings(
        includeColumnNames: Bool = true,
        includeAllFields: Bool = true,
        refreshPolicy: MFLRefreshPolicy = .useCache
    ) async throws -> MFLLeagueStandings {
        var parameters: [String: String] = [:]
        if includeColumnNames { parameters["COLUMN_NAMES"] = "1" }
        if includeAllFields { parameters["ALL"] = "1" }
        let response: MFLLeagueStandingsResponse = try await export(
            MFLLeagueStandingsResponse.self,
            endpoint: .leagueStandings,
            host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID,
            parameters: parameters,
            ttl: configuration.cacheDurations.standings,
            refreshPolicy: refreshPolicy
        )
        return response.leagueStandings
    }

    public func messageBoard(
        count: Int = 10,
        refreshPolicy: MFLRefreshPolicy = .useCache
    ) async throws -> MFLMessageBoard {
        guard count > 0 else { throw MFLCoreError.invalidRequest("Message count must be greater than zero.") }
        let response: MFLMessageBoardResponse = try await export(
            MFLMessageBoardResponse.self,
            endpoint: .messageBoard,
            host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID,
            parameters: ["COUNT": String(count)],
            ttl: configuration.cacheDurations.messageBoard,
            refreshPolicy: refreshPolicy
        )
        return response.messageBoard
    }

    public func messageBoardThread(
        id: String,
        refreshPolicy: MFLRefreshPolicy = .useCache
    ) async throws -> MFLMessageThread {
        try validateIdentifier(id)
        let response: MFLMessageBoardThreadResponse = try await export(
            MFLMessageBoardThreadResponse.self,
            endpoint: .messageBoardThread,
            host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID,
            parameters: ["THREAD": id],
            ttl: configuration.cacheDurations.messageThread,
            refreshPolicy: refreshPolicy
        )
        return response.messageBoardThread
    }

    public func pendingWaivers(
        franchiseID: String? = nil,
        refreshPolicy: MFLRefreshPolicy = .useCache
    ) async throws -> MFLPendingWaivers {
        var parameters: [String: String] = [:]
        if let franchiseID {
            try validateIdentifier(franchiseID)
            parameters["FRANCHISE_ID"] = franchiseID
        }
        let response: MFLPendingWaiversResponse = try await export(
            MFLPendingWaiversResponse.self,
            endpoint: .pendingWaivers,
            host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID,
            parameters: parameters,
            ttl: configuration.cacheDurations.pendingWaivers,
            refreshPolicy: refreshPolicy
        )
        return response.pendingWaivers
    }

    // MARK: Writes

    @discardableResult
    public func submitLineup(_ submission: MFLLineupSubmission) async throws -> MFLMutationResult {
        try validateWeek(submission.week)
        guard !submission.starterPlayerIDs.isEmpty else {
            throw MFLCoreError.invalidRequest("A lineup must contain at least one starter.")
        }
        try submission.starterPlayerIDs.forEach(validateIdentifier)
        try submission.tiebreakerPlayerIDs.forEach(validateIdentifier)
        guard Set(submission.starterPlayerIDs).count == submission.starterPlayerIDs.count else {
            throw MFLCoreError.invalidRequest("A lineup cannot contain the same starter more than once.")
        }

        var parameters = [
            "W": String(submission.week),
            "STARTERS": submission.starterPlayerIDs.joined(separator: ","),
        ]
        if let comments = submission.comments, !comments.isEmpty { parameters["COMMENTS"] = comments }
        if !submission.tiebreakerPlayerIDs.isEmpty {
            parameters["TIEBREAKERS"] = submission.tiebreakerPlayerIDs.joined(separator: ",")
        }
        if let franchiseID = submission.franchiseID {
            try validateIdentifier(franchiseID)
            parameters["FRANCHISE_ID"] = franchiseID
        }

        let result = try await performImport(endpoint: .lineup, parameters: parameters)
        invalidate([.rosters, .playerRosterStatus, .liveScoring])
        return result
    }

    @discardableResult
    public func submitBlindBidWaiverRequest(
        _ waiverRequest: MFLBlindBidWaiverRequest
    ) async throws -> MFLMutationResult {
        if let round = waiverRequest.round, round <= 0 {
            throw MFLCoreError.invalidRequest("Waiver round must be greater than zero.")
        }

        var encodedBids: [String] = []
        encodedBids.reserveCapacity(waiverRequest.bids.count)
        for bid in waiverRequest.bids {
            try validateIdentifier(bid.playerID)
            if let dropPlayerID = bid.dropPlayerID { try validateIdentifier(dropPlayerID) }
            guard bid.amount >= 0, !bid.amount.isNaN else {
                throw MFLCoreError.invalidRequest("Blind-bid amounts cannot be negative or NaN.")
            }
            let amount = NSDecimalNumber(decimal: bid.amount).stringValue
            encodedBids.append("\(bid.playerID)_\(amount)_\(bid.dropPlayerID ?? "0000")")
        }

        var parameters = ["PICKS": encodedBids.joined(separator: ",")]
        if let round = waiverRequest.round { parameters["ROUND"] = String(round) }
        if waiverRequest.replaceExisting { parameters["REPLACE"] = "1" }
        if let franchiseID = waiverRequest.franchiseID {
            try validateIdentifier(franchiseID)
            parameters["FRANCHISE_ID"] = franchiseID
        }

        let result = try await performImport(endpoint: .blindBidWaiverRequest, parameters: parameters)
        invalidate([.pendingWaivers, .rosters, .freeAgents])
        return result
    }

    @discardableResult
    public func postMessageBoard(_ post: MFLMessageBoardPost) async throws -> MFLMutationResult {
        let body = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw MFLCoreError.invalidRequest("A message body is required.") }

        var parameters = ["BODY": body]
        if let threadID = post.threadID {
            try validateIdentifier(threadID)
            parameters["THREAD"] = threadID
        } else {
            let subject = post.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !subject.isEmpty else {
                throw MFLCoreError.invalidRequest("A subject is required when starting a thread.")
            }
            parameters["SUBJECT"] = subject
        }
        if let franchiseID = post.franchiseID {
            try validateIdentifier(franchiseID)
            parameters["FRANCHISE_ID"] = franchiseID
        }

        let result = try await performImport(endpoint: .messageBoard, parameters: parameters)
        invalidate([.messageBoard, .messageBoardThread])
        return result
    }

    // MARK: Cache

    public func clearCache() {
        cache.removeAll(keepingCapacity: true)
    }

    public func clearCache(for endpoint: MFLExportEndpoint) {
        invalidate([endpoint])
    }

    // MARK: Internals

    private func resolvedLeagueHost() async throws -> MFLAPIHost {
        if let leagueHost { return leagueHost }
        return try await discoverLeagueHost()
    }

    private func export<Value: Decodable>(
        _ type: Value.Type,
        endpoint: MFLExportEndpoint,
        host: MFLAPIHost,
        leagueID: String?,
        parameters: [String: String],
        ttl: TimeInterval,
        refreshPolicy: MFLRefreshPolicy
    ) async throws -> Value {
        let key = CacheKey(
            endpoint: endpoint,
            leagueID: leagueID,
            parameters: parameters
        )
        if refreshPolicy == .useCache,
           let cached = cache[key],
           cached.expiresAt > Date()
        {
            return try responseDecoder.decode(type, from: cached.data)
        }

        let request = try requestBuilder.makeExportRequest(
            endpoint: endpoint,
            host: host,
            leagueID: leagueID,
            parameters: parameters,
            cookie: cookie
        )
        let response = try await sendFollowingSafeExportRedirect(request)
        try validateHTTP(response)
        try detectAPIError(in: response.data)

        let decoded = try responseDecoder.decode(type, from: response.data)
        if ttl > 0 {
            cache[key] = CacheEntry(data: response.data, expiresAt: Date().addingTimeInterval(ttl))
        }
        return decoded
    }

    /// MFL routes league exports from `api.myfantasyleague.com` to the
    /// league's current `wwwXX` host with an HTTP redirect. URLSession is
    /// deliberately configured not to follow redirects automatically so a
    /// cookie can never hitch a ride to an unvalidated destination. For GET
    /// exports only, validate the destination, preserve the exact path/query,
    /// remove authentication, and make one explicit follow-up request.
    private func sendFollowingSafeExportRedirect(_ request: URLRequest) async throws -> MFLHTTPResponse {
        let response = try await send(request)
        guard (300 ... 399).contains(response.statusCode) else { return response }

        guard request.httpMethod == "GET",
              let originalURL = request.url,
              let location = response.value(forHeader: "Location"),
              let redirectedURL = URL(string: location, relativeTo: originalURL)?.absoluteURL,
              redirectedURL.path == originalURL.path,
              redirectedURL.query == originalURL.query
        else {
            throw MFLCoreError.unexpectedRedirect
        }
        _ = try MFLAPIHost(redirectedURL.absoluteString)

        var redirectedRequest = request
        redirectedRequest.url = redirectedURL
        redirectedRequest.setValue(nil, forHTTPHeaderField: "Cookie")
        let redirectedResponse = try await send(redirectedRequest)
        guard !(300 ... 399).contains(redirectedResponse.statusCode) else {
            throw MFLCoreError.unexpectedRedirect
        }
        return redirectedResponse
    }

    private func performImport(
        endpoint: MFLImportEndpoint,
        parameters: [String: String]
    ) async throws -> MFLMutationResult {
        guard let cookie else {
            throw MFLCoreError.unauthorized("Sign in to make changes to this league.")
        }
        let request = try requestBuilder.makeImportRequest(
            endpoint: endpoint,
            host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID,
            parameters: parameters,
            cookie: cookie
        )
        let response = try await send(request)
        try validateSensitiveResponseOrigin(response, for: request)
        try validateHTTP(response)
        return try mutationResult(from: response.data)
    }

    private func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        try await waitForRequestSlot()
        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MFLCoreError {
            throw error
        } catch {
            throw MFLCoreError.transport(String(describing: error))
        }
    }

    private func waitForRequestSlot() async throws {
        let now = clock.now
        let scheduled: ContinuousClock.Instant
        if let nextRequestInstant, nextRequestInstant > now {
            scheduled = nextRequestInstant
        } else {
            scheduled = now
        }
        nextRequestInstant = scheduled.advanced(by: configuration.minimumRequestInterval)
        if scheduled > now {
            try await clock.sleep(until: scheduled)
        }
    }

    private func validateHTTP(_ response: MFLHTTPResponse) throws {
        if response.statusCode == 429 {
            let retryAfter = response.value(forHeader: "Retry-After").flatMap(TimeInterval.init)
            throw MFLCoreError.rateLimited(retryAfter: retryAfter)
        }
        guard (200 ... 299).contains(response.statusCode) else {
            let message = MFLAPIErrorEnvelope.message(in: response.data)
            if response.statusCode == 401 || response.statusCode == 403 {
                throw MFLCoreError.unauthorized(message ?? "MFL denied access to this request.")
            }
            throw MFLCoreError.httpStatus(code: response.statusCode, message: message)
        }
    }

    private func validateSensitiveResponseOrigin(
        _ response: MFLHTTPResponse,
        for request: URLRequest
    ) throws {
        guard let responseURL = response.url else { return }
        guard let requestURL = request.url,
              responseURL.scheme?.lowercased() == requestURL.scheme?.lowercased(),
              responseURL.host?.lowercased() == requestURL.host?.lowercased(),
              responseURL.port == requestURL.port,
              responseURL.path == requestURL.path
        else {
            throw MFLCoreError.unexpectedRedirect
        }
    }

    private func mutationResult(from data: Data) throws -> MFLMutationResult {
        guard !data.isEmpty else { throw MFLCoreError.invalidResponse }
        try detectAPIError(in: data)

        if let payload = try? JSONDecoder().decode(MFLJSONValue.self, from: data) {
            guard let object = payload.objectValue else {
                throw MFLCoreError.invalidResponse
            }
            let status = object["status"]?.stringValue
                ?? object["success"]?.stringValue
                ?? object["result"]?.stringValue
            guard let status else { throw MFLCoreError.invalidResponse }
            guard Self.isRecognizedMutationSuccess(status) else {
                throw classifiedAPIError(object["message"]?.stringValue ?? status)
            }
            return MFLMutationResult(
                message: object["message"]?.stringValue ?? status,
                payload: payload
            )
        }

        let delegate = MFLMutationXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.rootElement != "html" else {
            throw MFLCoreError.invalidResponse
        }
        if let message = delegate.errorMessage {
            throw classifiedAPIError(message)
        }
        guard let status = delegate.statusMessage else { throw MFLCoreError.invalidResponse }
        guard Self.isRecognizedMutationSuccess(status) else {
            throw classifiedAPIError(status)
        }
        return MFLMutationResult(message: status, payload: nil)
    }

    private static func isRecognizedMutationSuccess(_ message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        guard ![
            "error",
            "fail",
            "unsuccessful",
            "denied",
            "invalid",
            "unable",
            "not submitted",
            "not saved",
            "not posted",
            "not accepted",
            "not updated",
            "not completed",
            "unaccepted",
            "rejected",
        ].contains(where: { normalized.contains($0) }) else {
            return false
        }
        if ["ok", "success", "1", "true"].contains(normalized) { return true }
        if normalized.hasPrefix("ok ") || normalized.hasPrefix("ok:") { return true }
        return [
            "submitted",
            "saved",
            "posted",
            "updated",
            "accepted",
            "successful",
            "successfully",
            "completed",
        ].contains { normalized.contains($0) }
    }

    private func detectAPIError(in data: Data) throws {
        guard let message = MFLAPIErrorEnvelope.message(in: data) else { return }
        throw classifiedAPIError(message)
    }

    private func classifiedAPIError(_ message: String) -> MFLCoreError {
        let normalized = message.lowercased()
        if normalized.contains("logged in")
            || normalized.contains("mfl_user_id")
            || normalized.contains("not authorized")
            || normalized.contains("access restricted")
        {
            return MFLCoreError.unauthorized(message)
        }
        return MFLCoreError.api(message)
    }

    private func invalidate(_ endpoints: Set<MFLExportEndpoint>) {
        cache = cache.filter { !endpoints.contains($0.key.endpoint) }
    }

    private func validateWeek(_ week: Int) throws {
        guard (1 ... 21).contains(week) else {
            throw MFLCoreError.invalidRequest("MFL week must be between 1 and 21.")
        }
    }

    private func validateIdentifier(_ identifier: String) throws {
        guard
            !identifier.isEmpty,
            !identifier.contains(","),
            !identifier.contains("_"),
            !identifier.contains("\r"),
            !identifier.contains("\n")
        else {
            throw MFLCoreError.invalidRequest("An MFL identifier is empty or contains a reserved character.")
        }
    }

    private static func parseLoginCookie(_ data: Data) throws -> MFLAuthenticationCookie {
        let delegate = MFLLoginXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw MFLCoreError.authenticationFailed(
                delegate.errorMessage ?? parser.parserError?.localizedDescription ?? "MFL returned an invalid login response."
            )
        }
        if let value = delegate.cookieValue {
            return try MFLAuthenticationCookie(value: value)
        }
        throw MFLCoreError.authenticationFailed(delegate.errorMessage ?? "MFL did not accept those credentials.")
    }
}

private struct CacheKey: Hashable {
    let endpoint: MFLExportEndpoint
    let leagueID: String?
    let parameters: String

    init(endpoint: MFLExportEndpoint, leagueID: String?, parameters: [String: String]) {
        self.endpoint = endpoint
        self.leagueID = leagueID
        self.parameters = parameters.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    }
}

private struct CacheEntry: Sendable {
    let data: Data
    let expiresAt: Date
}

private final class MFLLoginXMLDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    var cookieValue: String?
    var errorMessage: String?

    private var collectingErrorText = false
    private var errorText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = elementName.lowercased()
        if element == "status" {
            cookieValue = attributeDict.first { $0.key.caseInsensitiveCompare("MFL_USER_ID") == .orderedSame }?.value
        } else if element == "error" {
            collectingErrorText = true
            errorMessage = attributeDict["message"] ?? attributeDict["$t"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingErrorText { errorText += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.lowercased() == "error" {
            collectingErrorText = false
            let text = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            if errorMessage == nil, !text.isEmpty { errorMessage = text }
        }
    }
}

private final class MFLMutationXMLDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    var rootElement: String?
    var errorMessage: String?
    var statusMessage: String?

    private var collectingError = false
    private var collectingStatus = false
    private var errorText = ""
    private var statusText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = elementName.lowercased()
        if rootElement == nil { rootElement = element }

        if element == "error" {
            collectingError = true
            errorMessage = attribute(
                named: ["message", "$t", "text"],
                in: attributeDict
            )
        } else if ["status", "success", "result"].contains(element) {
            collectingStatus = true
            statusMessage = attribute(
                named: ["message", "status", "value", "$t"],
                in: attributeDict
            )
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingError { errorText += string }
        if collectingStatus { statusText += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.lowercased()
        if element == "error" {
            collectingError = false
            let text = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            if errorMessage == nil, !text.isEmpty { errorMessage = text }
        } else if ["status", "success", "result"].contains(element) {
            collectingStatus = false
            let text = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
            if statusMessage == nil, !text.isEmpty { statusMessage = text }
        }
    }

    private func attribute(named names: Set<String>, in attributes: [String: String]) -> String? {
        attributes.first { names.contains($0.key.lowercased()) }?.value
    }
}
