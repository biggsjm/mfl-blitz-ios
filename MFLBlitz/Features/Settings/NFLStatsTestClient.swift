#if DEBUG
import Foundation

struct NFLTestGame: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let season: Int
    let stage: String
    let week: String
    let kickoff: Double
    let status: String
    let homeID: Int
    let home: String
    let awayID: Int
    let away: String
    let homeScore: Double?
    let awayScore: Double?

    var isFinal: Bool { ["FT", "AOT"].contains(status) }
}

struct NFLTestStat: Decodable, Identifiable, Sendable {
    let name: String
    let value: String?
    var id: String { name }
    var displayValue: String { value ?? "—" }
    var displayName: String {
        let common = ["comp att": "Completions / attempts", "passing touch downs": "Passing TDs",
                      "rushing touch downs": "Rushing TDs", "receiving touch downs": "Receiving TDs",
                      "total rushes": "Carries", "total receptions": "Receptions", "two pt": "Two-point conversions"]
        return common[name.lowercased()] ?? name.capitalized
    }
}

struct NFLTestStatGroup: Decodable, Identifiable, Sendable {
    let name: String
    let stats: [NFLTestStat]
    var id: String { name }
}

struct NFLTestPlayer: Decodable, Identifiable, Sendable {
    let id: String
    let providerID: Int
    let name: String
    let team: String
    let groups: [NFLTestStatGroup]
}

struct NFLTestGames: Decodable, Sendable {
    let provider: String
    let testOnly: Bool
    let season: Int
    let fetchedAt: Double
    let stale: Bool
    let games: [NFLTestGame]
}

struct NFLTestBoxScore: Decodable, Sendable {
    let provider: String
    let testOnly: Bool
    let season: Int
    let game: NFLTestGame
    let fetchedAt: Double
    let stale: Bool
    let players: [NFLTestPlayer]
}

enum NFLTestError: LocalizedError {
    case address, season, response, unavailable, budget, plan
    case transport(Int), httpStatus(Int), decoding
    var errorDescription: String? {
        switch self {
        case .address: "Enter the private HTTPS Tailscale address, without a path or API key."
        case .season: "This free test supports 2022–2024 only."
        case .response: "The test server returned data for an unexpected season or game."
        case .unavailable: "Couldn’t reach the NFL test service. Check Tailscale and try again."
        case .budget: "The provider or test budget is paused. Try again later; cached games remain available."
        case .plan: "This data isn’t available on the free plan."
        case .httpStatus(let code): "The test server returned HTTP \(code). The connection reached the server, but the request wasn’t accepted."
        case .decoding: "The server responded, but its NFL data couldn’t be read."
        case .transport(let code):
            switch code {
            case URLError.cannotFindHost.rawValue, URLError.dnsLookupFailed.rawValue:
                "The private server name couldn’t be resolved. Check Tailscale DNS. (\(code))"
            case URLError.timedOut.rawValue:
                "The private server didn’t respond in time. Try again. (\(code))"
            case URLError.secureConnectionFailed.rawValue, URLError.serverCertificateUntrusted.rawValue,
                 URLError.serverCertificateHasBadDate.rawValue, URLError.serverCertificateHasUnknownRoot.rawValue,
                 URLError.serverCertificateNotYetValid.rawValue:
                "iOS couldn’t verify the private server’s secure connection. (\(code))"
            case URLError.notConnectedToInternet.rawValue:
                "iOS reports no available connection for this request. Check Tailscale, then retry. (\(code))"
            default: "The private connection failed. Network code: \(code)."
            }
        }
    }
}

// Separate ephemeral session: never inherits MFL cookies, credentials or cache.
private final class NFLTestRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct NFLStatsTestClient: Sendable {
    private struct Failure: Decodable { let error: String }
    let baseURL: URL
    let session: URLSession

    static func serverURL(_ text: String) throws -> URL {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, host.hasSuffix(".ts.net"),
              host.split(separator: ".").count >= 4,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let url = parts.url else { throw NFLTestError.address }
        return url
    }

    init(address: String, session: URLSession? = nil) throws {
        baseURL = try Self.serverURL(address)
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil
            config.urlCache = nil
            config.timeoutIntervalForRequest = 50
            config.timeoutIntervalForResource = 55
            self.session = URLSession(configuration: config, delegate: NFLTestRedirectGuard(), delegateQueue: nil)
        }
    }

    func games(season: Int) async throws -> NFLTestGames {
        try Self.validateSeason(season)
        let value: NFLTestGames = try await get("v1/seasons/\(season)/games")
        guard value.testOnly, value.provider == "API-NFL", value.season == season,
              value.games.allSatisfy({ $0.season == season }),
              Set(value.games.map(\.id)).count == value.games.count,
              value.fetchedAt.isFinite else { throw NFLTestError.response }
        return value
    }

    func players(game: NFLTestGame) async throws -> NFLTestBoxScore {
        try Self.validateSeason(game.season)
        guard game.id > 0, game.isFinal else { throw NFLTestError.response }
        let value: NFLTestBoxScore = try await get("v1/seasons/\(game.season)/games/\(game.id)/players")
        guard value.testOnly, value.provider == "API-NFL", value.season == game.season,
              value.game.id == game.id, value.game.season == game.season, value.game.isFinal,
              value.game.homeID == game.homeID, value.game.awayID == game.awayID,
              value.fetchedAt.isFinite,
              Set(value.players.map(\.id)).count == value.players.count else { throw NFLTestError.response }
        return value
    }

    func profile(player: NFLTestPlayer, game: NFLTestGame) async throws -> NFLTestProfileResponse {
        try Self.validateSeason(game.season)
        guard game.id > 0, game.isFinal, player.providerID > 0 else { throw NFLTestError.response }
        let value: NFLTestProfileResponse = try await get(
            "v1/seasons/\(game.season)/games/\(game.id)/players/\(player.providerID)/profile")
        guard value.testOnly, value.provider == "API-NFL", value.season == game.season,
              value.gameID == game.id, value.profile.providerID == player.providerID,
              value.fetchedAt.isFinite, !value.profile.name.trimmingCharacters(in: .whitespaces).isEmpty
        else { throw NFLTestError.response }
        return value
    }

    static func validateSeason(_ season: Int) throws {
        guard [2022, 2023, 2024].contains(season) else { throw NFLTestError.season }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("1", forHTTPHeaderField: "X-Blitz-NFL-Test")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, data.count <= 5_000_000 else { throw NFLTestError.response }
            guard http.statusCode == 200 else {
                let code = try? JSONDecoder().decode(Failure.self, from: data).error
                if code == "plan" || code == "coverage" { throw NFLTestError.plan }
                if code == "budget" || code == "cooldown" { throw NFLTestError.budget }
                throw NFLTestError.httpStatus(http.statusCode)
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as NFLTestError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as URLError { throw NFLTestError.transport(error.code.rawValue) }
        catch is DecodingError { throw NFLTestError.decoding }
        catch { throw NFLTestError.unavailable }
    }
}

enum NFLTestPreview {
    // Synthetic only. Preview never calls Hephaestus or consumes provider quota.
    static let game = NFLTestGame(id: 11, season: 2024, stage: "Regular Season", week: "Week 1",
        kickoff: 1725583200, status: "FT", homeID: 1, home: "Home Team", awayID: 2,
        away: "Away Team", homeScore: 21, awayScore: 7)
    static let games = NFLTestGames(provider: "API-NFL", testOnly: true, season: 2024,
        fetchedAt: 1725583200, stale: false, games: [game])
    static let box = NFLTestBoxScore(provider: "API-NFL", testOnly: true, season: 2024, game: game,
        fetchedAt: 1725583200, stale: false, players: [NFLTestPlayer(id: "1-10", providerID: 10,
        name: "Example Quarterback", team: "Home Team", groups: [NFLTestStatGroup(name: "Passing", stats: [
            NFLTestStat(name: "yards", value: "240"), NFLTestStat(name: "passing touch downs", value: "0"),
            NFLTestStat(name: "sacks", value: nil)])])])
}
#endif
