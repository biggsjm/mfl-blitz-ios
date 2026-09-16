import Foundation
import Security

/// A scoped device credential obtained by verifying MFL membership once.
/// It is sent only to the exact HTTPS origin that issued it.
struct BetaServiceAccess: Codable, Sendable {
    var origin: String
    var code: String
    var season: Int
    var leagueID: String
    var franchiseID: String
    var expiresAt: Double
    static let key = "league-beta-access.v1"
    static let trustedOrigin = "https://hephaestus.tailb09d33.ts.net:10000"

    func matches(_ workspace: LeagueWorkspace, now: Date = Date()) -> Bool {
        season == workspace.season && leagueID == workspace.leagueID && franchiseID == workspace.franchiseID &&
            origin == Self.trustedOrigin && expiresAt > now.timeIntervalSince1970
    }

    static func deviceCredential(workspace: LeagueWorkspace, store: any PrivateStore) throws -> String {
        let key = "league-beta-device.\(workspace.storageScope)"
        if let saved = try store.decode(String.self, key: key) { return saved }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AccessError.connection }
        let value = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        try store.encode(value, key: key)
        return value
    }

    static func origin(of url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host, parts.user == nil, parts.password == nil else { return nil }
        return "https://\(host.lowercased()):\(parts.port ?? 443)"
    }

    static func authorize(_ request: inout URLRequest, store: any PrivateStore = KeychainPrivateStore(), now: Date = Date()) {
        guard let url = request.url, let access = try? store.decode(Self.self, key: key),
              access.expiresAt > now.timeIntervalSince1970, access.origin == origin(of: url) else { return }
        request.setValue(access.code, forHTTPHeaderField: "X-Blitz-Access")
    }

    static func connect(savedSession: SavedSession, deviceCredential code: String, address: String,
                        workspace: LeagueWorkspace, session: URLSession? = nil) async throws -> Self {
        let base = try MatchupSyncClient.serverURL(address)
        // Only the built-in first-party gateway may receive the session proof.
        // A user-editable background-scoring address is never trusted here.
        guard origin(of: base) == trustedOrigin else { throw AccessError.connection }
        guard savedSession.season == workspace.season, savedSession.leagueID == workspace.leagueID,
              savedSession.franchiseID == workspace.franchiseID else { throw AccessError.wrongTeam }
        var request = URLRequest(url: base.appending(path: "v1/access"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "season": workspace.season, "leagueID": workspace.leagueID, "franchiseID": workspace.franchiseID,
            "deviceCredential": code, "mflSession": savedSession.cookie
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 15
        let ownsSession = session == nil
        let session = session ?? URLSession(configuration: configuration, delegate: BetaAccessRedirectGuard(), delegateQueue: nil)
        defer { if ownsSession { session.finishTasksAndInvalidate() } }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count < 4096 else {
            throw AccessError.connection
        }
        struct Receipt: Decodable { var season: Int; var leagueID: String; var franchiseID: String; var expiresAt: Double }
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        guard receipt.season == workspace.season, receipt.leagueID == workspace.leagueID,
              receipt.franchiseID == workspace.franchiseID else { throw AccessError.wrongTeam }
        guard receipt.expiresAt.isFinite, receipt.expiresAt > Date().timeIntervalSince1970,
              let origin = origin(of: base) else { throw AccessError.connection }
        return Self(origin: origin, code: code, season: receipt.season, leagueID: receipt.leagueID,
                    franchiseID: receipt.franchiseID, expiresAt: receipt.expiresAt)
    }

    func revoke() async -> Bool {
        guard origin == Self.trustedOrigin, let url = URL(string: origin)?.appending(path: "v1/access") else { return false }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 5; config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config, delegate: BetaAccessRedirectGuard(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"; request.setValue(code, forHTTPHeaderField: "X-Blitz-Access")
        guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200 || http.statusCode == 403
    }

    enum AccessError: LocalizedError {
        case connection, wrongTeam
        var errorDescription: String? {
            switch self {
            case .connection: "Beta services will reconnect automatically. You can also try again here."
            case .wrongTeam: "Sign in to your invited MFL team to connect beta services."
            }
        }
    }
}

private final class BetaAccessRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
