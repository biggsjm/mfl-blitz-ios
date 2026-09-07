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
    private let playerCache: (any MFLPersistentResponseCache)?
    private var leagueCache: (any MFLPersistentResponseCache)?
    private var leagueCacheScope = ""
    private var cachedSeasonStatus: (value: MFLSeasonStatus, date: Date)?
    private var seasonStatusRead: (id: UUID, task: Task<MFLSeasonStatus, Error>)?
    private let clock = ContinuousClock()

    private var cookie: MFLAuthenticationCookie?
    private var leagueHost: MFLAPIHost?
    private var nextRequestInstant: ContinuousClock.Instant?
    private var rateLimitedUntil: [String: Date] = [:]
    private var cache: [CacheKey: CacheEntry] = [:]
    private var sharedReads: [CacheKey: (id: UUID, task: Task<MFLStoredResponse, Error>)] = [:]
    private var readVersions: [CacheKey: UUID] = [:]

    public init(
        configuration: MFLClientConfiguration,
        transport: any MFLHTTPTransport = MFLURLSessionTransport(),
        authenticationCookie: MFLAuthenticationCookie? = nil,
        playerCache: (any MFLPersistentResponseCache)? = nil
    ) {
        self.configuration = configuration
        self.transport = transport
        self.playerCache = playerCache
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
        clearCache()
        return parsedCookie
    }

    /// Installs a previously saved MFL cookie, normally read from the app's Keychain.
    /// Pass `nil` to log out locally. MFL has no server-side logout endpoint.
    public func setAuthenticationCookie(_ cookie: MFLAuthenticationCookie?) {
        self.cookie = cookie
        clearCache()
    }

    public func authenticationCookie() -> MFLAuthenticationCookie? {
        cookie
    }

    /// Selects an already validated league host, such as the host returned by
    /// the authenticated `myleagues` export.
    public func setLeagueHost(_ host: MFLAPIHost) {
        leagueHost = host
        clearCache()
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

    /// Attach only after fresh membership verification. The caller must bind
    /// this protected store to the exact session, season and franchise.
    public func setLeagueCache(_ store: (any MFLPersistentResponseCache)?, scope: String = "") {
        invalidate([.league])
        leagueCache = store
        leagueCacheScope = scope
    }

    /// No authentication cookie is sent to this public static resource.
    public func seasonStatus(refreshPolicy: MFLRefreshPolicy = .useCache) async throws -> MFLSeasonStatus {
        if refreshPolicy == .useCache, let cachedSeasonStatus,
           (0..<60).contains(Date().timeIntervalSince(cachedSeasonStatus.date)) { return cachedSeasonStatus.value }
        if refreshPolicy == .useCache, let read = seasonStatusRead {
            let value = try await read.task.value
            try Task.checkCancellation()
            return value
        }
        let id = UUID()
        let task = Task { try await self.fetchSeasonStatus() }
        seasonStatusRead = (id, task)
        defer { if seasonStatusRead?.id == id { seasonStatusRead = nil } }
        let value = try await task.value
        if seasonStatusRead?.id == id { cachedSeasonStatus = (value, Date()) }
        try Task.checkCancellation()
        return value
    }

    private func fetchSeasonStatus() async throws -> MFLSeasonStatus {
        guard let url = URL(string: "https://api.myfantasyleague.com/fflnetdynamic\(configuration.league.season)/mfl_status.json") else {
            throw MFLCoreError.invalidResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: configuration.requestTimeout)
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await send(request)
        try validateHTTP(response)
        let status = try responseDecoder.decode(MFLSeasonStatus.self, from: response.data)
        guard status.year == configuration.league.season else { throw MFLCoreError.invalidResponse }
        return status
    }

    /// Omitting W and F returns the whole fantasy season. This is schedule
    /// metadata, not an invitation to fetch every week's player scoring.
    public func schedule(refreshPolicy: MFLRefreshPolicy = .useCache) async throws -> MFLSchedule {
        let result: MFLScheduleResponse = try await export(
            MFLScheduleResponse.self, endpoint: .schedule,
            host: try await resolvedLeagueHost(), leagueID: configuration.league.leagueID,
            parameters: [:], ttl: 900, refreshPolicy: refreshPolicy
        )
        return result.schedule
    }

    public func weeklyResults(week: Int) async throws -> MFLLiveScoring {
        try validateWeek(week)
        let result: MFLWeeklyResultsResponse = try await export(
            MFLWeeklyResultsResponse.self, endpoint: .weeklyResults,
            host: try await resolvedLeagueHost(), leagueID: configuration.league.leagueID,
            parameters: ["W": String(week)], ttl: 0, refreshPolicy: .reloadIgnoringCache
        )
        guard result.weeklyResults.week == week else { throw MFLCoreError.invalidResponse }
        return result.weeklyResults
    }

    /// One league/week request covers rostered players and free agents. Unlike
    /// live scores, pregame projections can be cached for 15 minutes.
    public func projectedScores(week: Int, refreshPolicy: MFLRefreshPolicy = .useCache) async throws -> MFLProjectedScores {
        try validateWeek(week)
        let result: MFLProjectedScoresResponse = try await export(
            MFLProjectedScoresResponse.self, endpoint: .projectedScores,
            host: try await resolvedLeagueHost(), leagueID: configuration.league.leagueID,
            parameters: ["W": String(week)], ttl: 900, refreshPolicy: refreshPolicy)
        guard result.projectedScores.week == nil || result.projectedScores.week == week else {
            throw MFLCoreError.invalidResponse
        }
        #if DEBUG
        // Aggregate diagnostics only: never log cookies or raw response bodies.
        print("[MFL projections] Week \(week): \(result.projectedScores.scoresByPlayerID.count) usable projections")
        #endif
        return result.projectedScores
    }

    public func calendar() async throws -> MFLJSONValue {
        try await export(MFLJSONValue.self, endpoint: .calendar,
                         host: try await resolvedLeagueHost(), leagueID: configuration.league.leagueID,
                         parameters: [:], ttl: 60, refreshPolicy: .reloadIgnoringCache)
    }

    public func waiverResults() async throws -> MFLJSONValue {
        try await export(MFLJSONValue.self, endpoint: .transactions,
                         host: try await resolvedLeagueHost(), leagueID: configuration.league.leagueID,
                         parameters: ["TRANS_TYPE": "BBID_WAIVER,WAIVER,FREE_AGENT", "COUNT": "30"],
                         ttl: 30, refreshPolicy: .reloadIgnoringCache)
    }

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

    public func league(refreshPolicy: MFLRefreshPolicy = .useCache, maximumAge: TimeInterval? = nil) async throws -> MFLLeague {
        let host = leagueHost ?? .api
        let response: MFLLeagueResponse = try await export(
            MFLLeagueResponse.self,
            endpoint: .league,
            host: host,
            leagueID: configuration.league.leagueID,
            parameters: [:],
            ttl: configuration.cacheDurations.league,
            refreshPolicy: refreshPolicy,
            maximumAge: maximumAge
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

    // MARK: Player availability and research

    public func injuries(week: Int, refreshPolicy: MFLRefreshPolicy = .useCache) async throws -> MFLInjuries {
        try validateWeek(week)
        let response = try await export(MFLInjuriesResponse.self, endpoint: .injuries, host: .api,
            leagueID: nil, parameters: ["W": String(week)], ttl: 3_600, refreshPolicy: refreshPolicy)
        guard response.injuries.week == nil || response.injuries.week == week else { throw MFLCoreError.invalidResponse }
        return response.injuries
    }

    public func nflSchedule(week: Int, refreshPolicy: MFLRefreshPolicy = .useCache) async throws -> MFLNFLSchedule {
        try validateWeek(week)
        let response = try await export(MFLNFLScheduleResponse.self, endpoint: .nflSchedule, host: .api,
            leagueID: nil, parameters: ["W": String(week)], ttl: 21_600, refreshPolicy: refreshPolicy)
        guard response.nflSchedule.week == nil || response.nflSchedule.week == week else { throw MFLCoreError.invalidResponse }
        return response.nflSchedule
    }

    public func nflByeWeeks(refreshPolicy: MFLRefreshPolicy = .useCache) async throws -> MFLByeWeeks {
        let response = try await export(MFLByeWeeksResponse.self, endpoint: .nflByeWeeks, host: .api,
            leagueID: nil, parameters: [:], ttl: 86_400, refreshPolicy: refreshPolicy)
        guard response.nflByeWeeks.year == nil || response.nflByeWeeks.year == configuration.league.season else {
            throw MFLCoreError.invalidResponse
        }
        return response.nflByeWeeks
    }

    public func playerScores(playerIDs: [String], period: MFLPlayerScorePeriod,
                             refreshPolicy: MFLRefreshPolicy = .useCache) async throws -> MFLPlayerScores {
        guard !playerIDs.isEmpty, playerIDs.count <= 100, Set(playerIDs).count == playerIDs.count else {
            throw MFLCoreError.invalidRequest("Choose between one and 100 unique players.")
        }
        try playerIDs.forEach(validateIdentifier)
        if case .week(let week) = period { try validateWeek(week) }
        let response = try await export(MFLPlayerScoresResponse.self, endpoint: .playerScores,
            host: try await resolvedLeagueHost(), leagueID: configuration.league.leagueID,
            parameters: ["W": period.parameter, "PLAYERS": playerIDs.sorted().joined(separator: ",")],
            ttl: 3_600, refreshPolicy: refreshPolicy)
        guard response.playerScores.period == nil || response.playerScores.period?.uppercased() == period.parameter else {
            throw MFLCoreError.invalidResponse
        }
        return response.playerScores
    }

    public func pointsAllowed(refreshPolicy: MFLRefreshPolicy = .useCache) async throws -> MFLJSONValue {
        try await export(MFLJSONValue.self, endpoint: .pointsAllowed, host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID, parameters: [:], ttl: 21_600, refreshPolicy: refreshPolicy)
    }

    public func watchList(refreshPolicy: MFLRefreshPolicy = .useCache) async throws -> MFLWatchList {
        try await export(MFLWatchList.self, endpoint: .myWatchList, host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID, parameters: [:], ttl: 60, refreshPolicy: refreshPolicy)
    }

    public func abilities(refreshPolicy: MFLRefreshPolicy = .useCache) async throws -> MFLJSONValue {
        try await export(MFLJSONValue.self, endpoint: .abilities, host: try await resolvedLeagueHost(),
            leagueID: configuration.league.leagueID, parameters: ["DETAILS": "1"], ttl: 30, refreshPolicy: refreshPolicy)
    }

    // MARK: Writes

    @discardableResult
    public func updateWatchList(playerID: String, isWatched: Bool) async throws -> MFLMutationResult {
        try validateIdentifier(playerID)
        defer { invalidate([.myWatchList]) }
        return try await performImport(endpoint: .myWatchList, parameters: [isWatched ? "ADD" : "REMOVE": playerID])
    }

    @discardableResult
    public func addDrop(addPlayerID: String?, dropPlayerID: String?) async throws -> MFLMutationResult {
        guard addPlayerID != nil || dropPlayerID != nil else { throw MFLCoreError.invalidRequest("Choose a player to add or drop.") }
        if let addPlayerID { try validateIdentifier(addPlayerID) }
        if let dropPlayerID { try validateIdentifier(dropPlayerID) }
        guard addPlayerID == nil || addPlayerID != dropPlayerID else {
            throw MFLCoreError.invalidRequest("The same player cannot be added and dropped.")
        }
        var parameters: [String: String] = [:]
        parameters["ADD"] = addPlayerID
        parameters["DROP"] = dropPlayerID
        defer { invalidate([.rosters, .playerRosterStatus, .freeAgents, .league, .transactions]) }
        return try await performImport(endpoint: .fcfsWaiver, parameters: parameters)
    }

    @discardableResult
    public func moveInjuredReserve(playerID: String, activate: Bool, dropPlayerID: String? = nil) async throws -> MFLMutationResult {
        try validateIdentifier(playerID)
        if let dropPlayerID { try validateIdentifier(dropPlayerID) }
        guard dropPlayerID != playerID, activate || dropPlayerID == nil else {
            throw MFLCoreError.invalidRequest("This injured-reserve move is invalid.")
        }
        var parameters = [activate ? "ACTIVATE" : "DEACTIVATE": playerID]
        parameters["DROP"] = dropPlayerID
        defer { invalidate([.rosters, .playerRosterStatus, .freeAgents, .league, .transactions]) }
        return try await performImport(endpoint: .ir, parameters: parameters)
    }

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

    // MARK: Trades and transaction activity

    public func pendingTrades(franchiseID: String) async throws -> MFLPendingTrades {
        try validateIdentifier(franchiseID)
        let response = try await export(MFLPendingTradesResponse.self, endpoint: .pendingTrades,
            host: try await resolvedLeagueHost(), leagueID: configuration.league.leagueID,
            parameters: ["FRANCHISE_ID": franchiseID], ttl: 0, refreshPolicy: .reloadIgnoringCache)
        return response.pendingTrades
    }

    public func tradeAssets() async throws -> MFLTradeAssets {
        let response = try await export(MFLTradeAssetsResponse.self, endpoint: .assets,
            host: try await resolvedLeagueHost(), leagueID: configuration.league.leagueID,
            parameters: [:], ttl: 0, refreshPolicy: .reloadIgnoringCache)
        return response.assets
    }

    public func transactionActivity() async throws -> MFLJSONValue {
        try await export(MFLJSONValue.self, endpoint: .transactions,
            host: try await resolvedLeagueHost(), leagueID: configuration.league.leagueID,
            parameters: ["TRANS_TYPE": "DEFAULT", "COUNT": "50"],
            ttl: 0, refreshPolicy: .reloadIgnoringCache)
    }

    @discardableResult
    public func proposeTrade(to franchiseID: String, giving: [String], receiving: [String],
                             comments: String, expires: Date, actingFranchiseID: String) async throws -> MFLMutationResult {
        try validateIdentifier(franchiseID)
        try validateIdentifier(actingFranchiseID)
        guard franchiseID != actingFranchiseID, !giving.isEmpty, !receiving.isEmpty,
              Set(giving).count == giving.count, Set(receiving).count == receiving.count,
              (giving + receiving).allSatisfy(MFLTradeAssetCode.isSupported),
              giving.filter({ $0.hasPrefix("BB_") }).count <= 1,
              receiving.filter({ $0.hasPrefix("BB_") }).count <= 1,
              expires.timeIntervalSince1970.isFinite, expires.timeIntervalSince1970 < Double(Int.max), expires > Date(), comments.count <= 1_000 else {
            throw MFLCoreError.invalidRequest("Review the teams, assets, message, and expiration before sending this offer.")
        }
        let result = try await performImport(endpoint: .tradeProposal, parameters: [
            "OFFEREDTO": franchiseID, "WILL_GIVE_UP": giving.joined(separator: ","),
            "WILL_RECEIVE": receiving.joined(separator: ","), "COMMENTS": comments,
            "EXPIRES": String(Int(expires.timeIntervalSince1970)), "FRANCHISE_ID": actingFranchiseID
        ])
        invalidate([.pendingTrades, .assets, .transactions])
        return result
    }

    @discardableResult
    public func respondToTrade(id: String, response: MFLTradeResponse, comments: String = "",
                               actingFranchiseID: String) async throws -> MFLMutationResult {
        try validateIdentifier(id)
        try validateIdentifier(actingFranchiseID)
        guard comments.count <= 1_000 else { throw MFLCoreError.invalidRequest("Keep trade messages under 1,000 characters.") }
        var parameters = ["TRADE_ID": id, "RESPONSE": response.rawValue, "FRANCHISE_ID": actingFranchiseID]
        if response == .reject { parameters["COMMENTS"] = comments }
        let result = try await performImport(endpoint: .tradeResponse, parameters: parameters)
        invalidate([.pendingTrades, .assets, .rosters, .transactions, .liveScoring, .pendingWaivers])
        return result
    }

    // MARK: Cache

    public func clearCache() {
        cache.removeAll(keepingCapacity: true)
        sharedReads.removeAll(keepingCapacity: true)
        readVersions.removeAll(keepingCapacity: true)
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
        refreshPolicy: MFLRefreshPolicy,
        maximumAge: TimeInterval? = nil
    ) async throws -> Value {
        let key = CacheKey(
            endpoint: endpoint,
            leagueID: leagueID,
            parameters: parameters
        )
        if refreshPolicy == .useCache,
           let cached = cache[key],
           cached.expiresAt > Date(),
           cached.fetchedAt <= Date(),
           maximumAge.map({ Date().timeIntervalSince(cached.fetchedAt) < $0 }) ?? true
        {
            if let players = cached.players as? Value { return players }
            return try responseDecoder.decode(type, from: cached.data)
        }

        // Coalesce cacheable reads across tabs (notably the full player catalog
        // and projections). Forced preflight/readback requests NEVER join one.
        if refreshPolicy == .useCache, let read = sharedReads[key] {
            let value = try await read.task.value
            try Task.checkCancellation()
            if let maximumAge, Date().timeIntervalSince(value.fetchedAt) >= maximumAge {
                return try await export(type, endpoint: endpoint, host: host, leagueID: leagueID,
                    parameters: parameters, ttl: ttl, refreshPolicy: .reloadIgnoringCache, maximumAge: maximumAge)
            }
            if readVersions[key] == read.id, let players = cache[key]?.players as? Value { return players }
            return try responseDecoder.decode(type, from: value.data)
        }
        let request = try requestBuilder.makeExportRequest(
            endpoint: endpoint,
            host: host,
            leagueID: leagueID,
            parameters: parameters,
            cookie: [.injuries, .nflSchedule, .nflByeWeeks].contains(endpoint) ? nil : cookie
        )
        let version = UUID()
        readVersions[key] = version
        let persistentKey = endpoint == .league
            ? "league-v1:\(configuration.league.season):\(host.name):\(leagueID ?? "")\(leagueCacheScope.isEmpty ? "" : ":" + leagueCacheScope)"
            : "players-v1:\(configuration.league.season)"
        let persistentStore = parameters.isEmpty ? (endpoint == .players ? playerCache : endpoint == .league ? leagueCache : nil) : nil
        let value: MFLStoredResponse
        if refreshPolicy == .useCache, ttl > 0 {
            let task = Task {
                let value: MFLStoredResponse
                let decoded: Value
                let loadedFromDisk: Bool
                if let stored = await persistentStore?.read(),
                   stored.isFresh(key: persistentKey, ttl: min(ttl, 86_400, maximumAge ?? ttl)),
                   let storedValue = try? self.responseDecoder.decode(type, from: stored.data) {
                    #if DEBUG
                    print("[MFL cache] \(endpoint.rawValue): disk hit")
                    #endif
                    value = stored
                    decoded = storedValue
                    loadedFromDisk = true
                } else {
                    let data = try await self.exportData(request)
                    // Do not publish malformed responses to either cache.
                    decoded = try self.responseDecoder.decode(type, from: data)
                    #if DEBUG
                    if persistentStore != nil { print("[MFL cache] \(endpoint.rawValue): downloaded") }
                    #endif
                    value = MFLStoredResponse(key: persistentKey, data: data)
                    loadedFromDisk = false
                }
                // The read belongs to all waiters, not the caller that started
                // it. Publish before checking any individual caller's cancellation.
                if self.readVersions[key] == version {
                    self.cache[key] = CacheEntry(data: value.data, fetchedAt: value.fetchedAt,
                        expiresAt: value.fetchedAt.addingTimeInterval(ttl), players: decoded as? MFLPlayersResponse)
                    if !loadedFromDisk { await persistentStore?.write(value) }
                }
                return value
            }
            sharedReads[key] = (version, task)
            defer { if sharedReads[key]?.id == version { sharedReads[key] = nil } }
            value = try await task.value
        } else {
            // A forced read replaces any older shared read for future callers.
            sharedReads[key] = nil
            value = MFLStoredResponse(key: persistentKey, data: try await exportData(request))
        }
        try Task.checkCancellation()
        if refreshPolicy == .useCache, readVersions[key] == version,
           let players = cache[key]?.players as? Value { return players }
        let decoded = try responseDecoder.decode(type, from: value.data)
        if refreshPolicy == .reloadIgnoringCache, ttl > 0, readVersions[key] == version {
            cache[key] = CacheEntry(data: value.data, fetchedAt: value.fetchedAt,
                expiresAt: value.fetchedAt.addingTimeInterval(ttl), players: decoded as? MFLPlayersResponse)
            await persistentStore?.write(value)
        }
        return decoded
    }

    private func exportData(_ request: URLRequest) async throws -> Data {
        let response = try await sendFollowingSafeExportRedirect(request)
        try validateHTTP(response)
        try detectAPIError(in: response.data)
        return response.data
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
        // Never restore pre-mutation balances/rules after relaunch. Detach and
        // invalidate before awaiting disk removal so old shared reads cannot
        // repopulate it. Even an ambiguous import leaves this cache unavailable.
        let oldLeagueCache = leagueCache
        leagueCache = nil
        invalidate([.league])
        await oldLeagueCache?.remove()
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
        try checkRateLimit(for: request)
        try await waitForRequestSlot()
        try checkRateLimit(for: request)
        do {
            let response = try await transport.send(request)
            if response.statusCode == 429 {
                let deadline = Date().addingTimeInterval(max(1, retryAfter(response) ?? 90))
                // MFL documents throttling per server. Never redirect a league
                // request to evade it; pause only the host that rejected it.
                for host in [request.url?.host, response.url?.host].compactMap({ $0?.lowercased() }) {
                    rateLimitedUntil[host] = max(rateLimitedUntil[host] ?? .distantPast, deadline)
                }
            }
            return response
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MFLCoreError {
            throw error
        } catch {
            throw MFLCoreError.transport(String(describing: error))
        }
    }

    private func checkRateLimit(for request: URLRequest) throws {
        if let host = request.url?.host?.lowercased(), let deadline = rateLimitedUntil[host], deadline > Date() {
            throw MFLCoreError.rateLimited(retryAfter: deadline.timeIntervalSinceNow)
        }
    }

    private func waitForRequestSlot() async throws {
        // Recheck after every suspension. Reserved slots can all be in the past
        // after backgrounding, otherwise waking callers send a burst together.
        while let next = nextRequestInstant, next > clock.now {
            try await clock.sleep(until: next)
        }
        try Task.checkCancellation()
        nextRequestInstant = clock.now.advanced(by: configuration.minimumRequestInterval)
    }

    private func retryAfter(_ response: MFLHTTPResponse) -> TimeInterval? {
        response.value(forHeader: "Retry-After").flatMap(TimeInterval.init).flatMap {
                $0.isFinite && $0 >= 0 && $0 < Double(Int.max) / 2 ? $0 : nil
        }
    }

    private func validateHTTP(_ response: MFLHTTPResponse) throws {
        if response.statusCode == 429 { throw MFLCoreError.rateLimited(retryAfter: retryAfter(response)) }
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
        sharedReads = sharedReads.filter { !endpoints.contains($0.key.endpoint) }
        readVersions = readVersions.filter { !endpoints.contains($0.key.endpoint) }
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
    let fetchedAt: Date
    let expiresAt: Date
    // Immutable, typed catalog shares the raw entry's exact expiry/invalidation.
    // Keeping this decoded avoids parsing thousands of players on every tab.
    let players: MFLPlayersResponse?
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
