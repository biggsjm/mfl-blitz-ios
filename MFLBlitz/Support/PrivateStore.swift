import Foundation
import Security

protocol PrivateStore: Sendable {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func remove(_ key: String) throws
}

/// Passwords are never stored. Session cookies, private bids, and message drafts
/// stay on this device and are available only while it is unlocked.
struct KeychainPrivateStore: PrivateStore {
    private let service = "com.biggsjm.MFLBlitz.private.v1"

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key,
         kSecAttrSynchronizable as String: false]
    }

    func read(_ key: String) throws -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw StoreError.unavailable }
        return data
    }

    func write(_ data: Data, key: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            try check(SecItemAdd(query(key).merging(attributes) { _, new in new } as CFDictionary, nil))
        } else { try check(status) }
    }

    func remove(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw StoreError.unavailable }
    }
}

enum StoreError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Couldn’t access secure storage. Keep the app open and unlock your device before trying again. Your changes have not been sent." }
}

extension PrivateStore {
    func decode<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        guard let data = try read(key) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }
    func encode<T: Encodable>(_ value: T, key: String) throws {
        try write(JSONEncoder().encode(value), key: key)
    }
}

struct SavedSession: Codable, Sendable {
    var cookie: String
    var season: Int
    var leagueID: String
    var franchiseID: String
}

extension LeagueWorkspace {
    var storageScope: String { "\(season).\(leagueID).\(franchiseID)" }
    var leagueURL: URL { baseURL.appending(path: "\(season)/home/\(leagueID)") }
    func reportURL(_ report: String) -> URL {
        baseURL.appending(path: "\(season)/options").appending(queryItems: [
            URLQueryItem(name: "L", value: leagueID), URLQueryItem(name: "O", value: report)
        ])
    }
}

struct LineupDraft: Codable, Equatable, Sendable {
    var baseline: Set<String>
    var starters: Set<String>
    var tiebreakers: [String]
    var submittedTiebreakers: [String] = []
    var startingAssignments: [LineupSlotAssignment]? = nil
}

struct BoardDraft: Codable, Equatable, Sendable {
    var subject = ""
    var body = ""

    var hasContent: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SavedBoardDraft: Identifiable, Equatable, Sendable {
    let id: String
    let draft: BoardDraft
    var threadID: String? { id == "new" ? nil : id }
}

struct LeagueDrafts: Codable, Sendable {
    var lineups: [Int: LineupDraft] = [:]
    var waiverClaims: [WaiverClaim]?
    var waiverBaseline: [WaiverClaim] = []
    var board: [String: BoardDraft] = [:]
}

/// A durable send marker prevents a timeout/relaunch from silently posting twice.
struct PendingBoardPost: Codable, Sendable {
    var subject: String?
    var body: String
    var threadID: String?
    var existingIDs: Set<String>
    var startedAt: Date
}
