import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MFLCoreError: Error, Equatable, Sendable {
    case invalidHost(String)
    case invalidLeagueURL
    case invalidSeason(Int)
    case invalidLeagueID(String)
    case invalidUserAgent
    case invalidCookie
    case invalidRequest(String)
    case invalidResponse
    case unexpectedRedirect
    case transport(String)
    case httpStatus(code: Int, message: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case unauthorized(String)
    case api(String)
    case authenticationFailed(String)
    case decoding(String)
}

extension MFLCoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidHost(host): "Invalid or untrusted MFL host: \(host)"
        case .invalidLeagueURL: "The URL is not a valid MyFantasyLeague league URL."
        case let .invalidSeason(season): "Invalid MFL season: \(season)"
        case let .invalidLeagueID(id): "Invalid MFL league id: \(id)"
        case .invalidUserAgent: "The MFL API User-Agent cannot be empty or contain line breaks."
        case .invalidCookie: "The MFL authentication cookie is invalid."
        case let .invalidRequest(message): message
        case .invalidResponse: "The server did not return a valid HTTP response."
        case .unexpectedRedirect: "MFL redirected a sensitive request, so it was stopped."
        case let .transport(message): "The MFL request failed: \(message)"
        case let .httpStatus(code, message): message ?? "MFL returned HTTP \(code)."
        case let .rateLimited(retryAfter):
            if let retryAfter { "MFL rate-limited the request. Try again in \(Int(retryAfter.rounded(.up))) seconds." }
            else { "MFL rate-limited the request. Try again later." }
        case let .unauthorized(message): message
        case let .api(message): message
        case let .authenticationFailed(message): message
        case let .decoding(message): "MFL returned data in an unexpected format: \(message)"
        }
    }
}

/// A validated MyFantasyLeague host. Only HTTPS hosts beneath
/// `myfantasyleague.com` are accepted, preventing a server-provided `baseURL`
/// from redirecting credentials to another domain.
public struct MFLAPIHost: Hashable, Codable, Sendable, CustomStringConvertible {
    public let name: String

    public static let api = Self(validatedName: "api.myfantasyleague.com")

    public init(_ value: String) throws {
        let candidate = value.contains("://") ? value : "https://\(value)"
        guard
            let components = URLComponents(string: candidate),
            components.scheme?.lowercased() == "https",
            components.user == nil,
            components.password == nil,
            components.port == nil,
            let host = components.host?.lowercased(),
            host == "myfantasyleague.com" || host.hasSuffix(".myfantasyleague.com")
        else {
            throw MFLCoreError.invalidHost(value)
        }
        name = host
    }

    private init(validatedName: String) {
        name = validatedName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }

    public var description: String { name }
}

public struct MFLLeagueReference: Hashable, Codable, Sendable {
    public let season: Int
    public let leagueID: String
    public let host: MFLAPIHost?

    public init(season: Int, leagueID: String, host: MFLAPIHost? = nil) throws {
        guard (2000 ... 2100).contains(season) else {
            throw MFLCoreError.invalidSeason(season)
        }
        guard !leagueID.isEmpty, leagueID.allSatisfy(\.isNumber) else {
            throw MFLCoreError.invalidLeagueID(leagueID)
        }
        self.season = season
        self.leagueID = leagueID
        self.host = host
    }

    /// Parses URLs such as `https://www45.myfantasyleague.com/2026/home/41366#0`.
    public init(leagueURL: URL) throws {
        guard leagueURL.scheme?.lowercased() == "https", let rawHost = leagueURL.host else {
            throw MFLCoreError.invalidLeagueURL
        }
        let host = try MFLAPIHost(rawHost)
        let parts = leagueURL.pathComponents.filter { $0 != "/" }
        guard
            parts.count >= 3,
            let season = Int(parts[0]),
            parts[1].lowercased() == "home"
        else {
            throw MFLCoreError.invalidLeagueURL
        }
        try self.init(season: season, leagueID: parts[2], host: host)
    }

    private enum CodingKeys: String, CodingKey {
        case season
        case leagueID
        case host
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            season: container.decode(Int.self, forKey: .season),
            leagueID: container.decode(String.self, forKey: .leagueID),
            host: container.decodeIfPresent(MFLAPIHost.self, forKey: .host)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(season, forKey: .season)
        try container.encode(leagueID, forKey: .leagueID)
        try container.encodeIfPresent(host, forKey: .host)
    }
}

/// The value returned by MFL's HTTPS login endpoint.
public struct MFLAuthenticationCookie: Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) throws {
        guard
            !value.isEmpty,
            !value.contains("\r"),
            !value.contains("\n"),
            !value.contains(";")
        else {
            throw MFLCoreError.invalidCookie
        }
        self.value = value
    }

    public var description: String { "MFL_USER_ID=<redacted>" }

    var requestHeaderValue: String { "MFL_USER_ID=\(value)" }
}

public enum MFLRefreshPolicy: Equatable, Sendable {
    /// Return an unexpired in-memory response, otherwise load it.
    case useCache
    /// Always load from MFL and replace the in-memory response.
    case reloadIgnoringCache
}

public struct MFLCacheDurations: Equatable, Sendable {
    public var league: TimeInterval
    public var players: TimeInterval
    public var freeAgents: TimeInterval
    public var rosters: TimeInterval
    public var liveScoring: TimeInterval
    public var standings: TimeInterval
    public var messageBoard: TimeInterval
    public var messageThread: TimeInterval
    public var pendingWaivers: TimeInterval

    /// Conservative in-memory defaults. The 24-hour player TTL follows MFL's
    /// explicit guidance; shorter league-data TTLs preserve a responsive app.
    public static let standard = Self(
        league: 15 * 60,
        players: 24 * 60 * 60,
        freeAgents: 60,
        rosters: 30,
        liveScoring: 90,
        standings: 60,
        messageBoard: 30,
        messageThread: 15,
        pendingWaivers: 15
    )

    public init(
        league: TimeInterval,
        players: TimeInterval,
        freeAgents: TimeInterval,
        rosters: TimeInterval,
        liveScoring: TimeInterval,
        standings: TimeInterval,
        messageBoard: TimeInterval,
        messageThread: TimeInterval,
        pendingWaivers: TimeInterval
    ) {
        self.league = max(0, league)
        self.players = max(0, players)
        self.freeAgents = max(0, freeAgents)
        self.rosters = max(0, rosters)
        self.liveScoring = max(0, liveScoring)
        self.standings = max(0, standings)
        self.messageBoard = max(0, messageBoard)
        self.messageThread = max(0, messageThread)
        self.pendingWaivers = max(0, pendingWaivers)
    }
}

public struct MFLClientConfiguration: Sendable {
    public var league: MFLLeagueReference
    /// This should exactly match the value registered with MFL for elevated limits.
    public var userAgent: String
    /// MFL recommends spacing calls by at least one second.
    public var minimumRequestInterval: Duration
    public var requestTimeout: TimeInterval
    public var cacheDurations: MFLCacheDurations

    public init(
        league: MFLLeagueReference,
        userAgent: String = "MFL Blitz/1.0",
        minimumRequestInterval: Duration = .seconds(1),
        requestTimeout: TimeInterval = 30,
        cacheDurations: MFLCacheDurations = .standard
    ) {
        self.league = league
        self.userAgent = userAgent
        self.minimumRequestInterval = minimumRequestInterval < .zero ? .zero : minimumRequestInterval
        self.requestTimeout = requestTimeout
        self.cacheDurations = cacheDurations
    }
}

public enum MFLExportEndpoint: String, CaseIterable, Sendable {
    case myleagues
    case league
    case players
    case freeAgents
    case rosters
    case liveScoring
    case leagueStandings
    case messageBoard
    case messageBoardThread
    case pendingWaivers
}

public enum MFLImportEndpoint: String, CaseIterable, Sendable {
    case lineup
    case blindBidWaiverRequest
    case messageBoard
}

public struct MFLAPIRequestBuilder: Sendable {
    public let season: Int
    public let userAgent: String
    public let timeout: TimeInterval

    public init(season: Int, userAgent: String, timeout: TimeInterval = 30) {
        self.season = season
        self.userAgent = userAgent
        self.timeout = timeout
    }

    public func makeExportRequest(
        endpoint: MFLExportEndpoint,
        host: MFLAPIHost,
        leagueID: String? = nil,
        parameters: [String: String] = [:],
        cookie: MFLAuthenticationCookie? = nil
    ) throws -> URLRequest {
        var query = parameters
        query["TYPE"] = endpoint.rawValue
        query["JSON"] = "1"
        if let leagueID { query["L"] = leagueID }
        return try makeRequest(
            path: "export",
            host: host,
            method: "GET",
            query: query,
            body: [:],
            cookie: cookie
        )
    }

    /// Builds a form-encoded POST to MFL's import endpoint. Keeping mutation
    /// arguments out of the URL avoids accidental resubmission and log exposure.
    public func makeImportRequest(
        endpoint: MFLImportEndpoint,
        host: MFLAPIHost,
        leagueID: String,
        parameters: [String: String],
        cookie: MFLAuthenticationCookie
    ) throws -> URLRequest {
        try makeRequest(
            path: "import",
            host: host,
            method: "POST",
            query: ["JSON": "1", "L": leagueID, "TYPE": endpoint.rawValue],
            body: parameters,
            cookie: cookie
        )
    }

    /// MFL's login API is intentionally HTTPS POST and returns XML containing
    /// the `MFL_USER_ID` cookie value.
    public func makeLoginRequest(username: String, password: String) throws -> URLRequest {
        try makeRequest(
            path: "login",
            host: .api,
            method: "POST",
            query: [:],
            body: ["USERNAME": username, "PASSWORD": password, "XML": "1"],
            cookie: nil
        )
    }

    private func makeRequest(
        path: String,
        host: MFLAPIHost,
        method: String,
        query: [String: String],
        body: [String: String],
        cookie: MFLAuthenticationCookie?
    ) throws -> URLRequest {
        guard (2000 ... 2100).contains(season) else { throw MFLCoreError.invalidSeason(season) }
        guard
            !userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !userAgent.contains("\r"),
            !userAgent.contains("\n")
        else {
            throw MFLCoreError.invalidUserAgent
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host.name
        components.path = "/\(season)/\(path)"
        if !query.isEmpty {
            components.queryItems = query.sorted(by: { $0.key < $1.key }).map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
        }
        guard let url = components.url else {
            throw MFLCoreError.invalidRequest("Unable to construct the MFL request URL.")
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = method
        request.setValue("application/json, application/xml;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let cookie {
            request.setValue(cookie.requestHeaderValue, forHTTPHeaderField: "Cookie")
        }
        if !body.isEmpty {
            request.httpBody = Self.formEncode(body).data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func formEncode(_ values: [String: String]) -> String {
        values.sorted(by: { $0.key < $1.key }).map {
            "\(formEncodeComponent($0.key))=\(formEncodeComponent($0.value))"
        }.joined(separator: "&")
    }

    private static func formEncodeComponent(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        return value.utf8.map { byte -> String in
            guard byte < 128, let scalar = UnicodeScalar(Int(byte)), allowed.contains(Character(String(scalar))) else {
                return String(format: "%%%02X", byte)
            }
            let character = Character(String(scalar))
            return character == " " ? "+" : String(character)
        }.joined()
        .replacingOccurrences(of: "%20", with: "+")
    }
}
