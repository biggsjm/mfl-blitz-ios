#if DEBUG
import Foundation

struct NFLTestProfile: Codable, Equatable, Sendable {
    let providerID: Int
    let name: String
    let position: String?
    let college: String?
    let height: String?
    let weight: String?
}

struct NFLTestProfileResponse: Decodable, Sendable {
    let provider: String
    let testOnly: Bool
    let season: Int
    let gameID: Int
    let fetchedAt: Double
    let stale: Bool
    let profile: NFLTestProfile
}

/// A human-reviewed identity assertion, NOT an authoritative cross-provider ID.
/// Only the DEBUG historical tool consumes these records. No production resolver.
struct NFLTestPlayerMatch: Codable, Equatable, Identifiable, Sendable {
    let origin: String
    let profile: NFLTestProfile
    let mflPlayer: PlayerIdentity
    let mflSeason: Int
    let historicalSeason: Int
    let gameID: Int
    let boxScoreName: String
    let gameTeam: String
    let profileFetchedAt: Double
    let reviewedAt: Date
    let note: String
    var id: String { "\(origin)|\(profile.providerID)" }
}

enum NFLTestMappingError: LocalizedError, Equatable {
    case invalid, conflict, storage
    var errorDescription: String? {
        switch self {
        case .invalid: "Check the player, position and verification note. Only fresh historical test data can be matched."
        case .conflict: "One of these IDs already has a saved match. Remove that match before changing it."
        case .storage: "Saved matches couldn’t be read or saved. No match was changed."
        }
    }
}

enum NFLTestMappingRules {
    static func origin(address: String) throws -> String {
        let url = try NFLStatsTestClient.serverURL(address)
        return "https://\(url.host!.lowercased()):\(url.port ?? 443)"
    }

    static func name(_ name: String) -> String {
        // Normalization ranks suggestions only. Never auto-accept a name match;
        // don't strip suffixes or expand initials/nicknames into another person.
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func position(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !value.isEmpty else { return nil }
        return value == "PK" ? "K" : value
    }

    static func compatible(_ profile: NFLTestProfile, _ candidate: PlayerIdentity) -> Bool {
        guard let position = position(profile.position), position == self.position(candidate.position) else { return false }
        return ["QB", "RB", "FB", "WR", "TE", "K", "P", "DL", "DE", "DT", "LB", "DB", "CB", "S"].contains(position)
    }

    static func candidates(profile: NFLTestProfile, players: [PlayerIdentity], query: String) -> [PlayerIdentity] {
        let search = name(query)
        let tokens = search.split(separator: " ")
        return players.filter { player in
            compatible(profile, player) && !tokens.isEmpty && tokens.allSatisfy { name(player.name).contains($0) }
        }.sorted {
            let firstExact = name($0.name) == name(profile.name), secondExact = name($1.name) == name(profile.name)
            if firstExact != secondExact { return firstExact }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
    }

    static func isCurrent(_ record: NFLTestPlayerMatch, origin: String, response: NFLTestProfileResponse,
                          game: NFLTestGame, player: NFLTestPlayer, candidate: PlayerIdentity?, mflSeason: Int) -> Bool {
        guard let candidate, [2022, 2023, 2024].contains(game.season), game.isFinal,
              response.testOnly, response.provider == "API-NFL", !response.stale,
              response.gameID == game.id, response.season == game.season,
              response.profile.providerID == player.providerID,
              record.origin == origin, record.historicalSeason == game.season,
              record.mflSeason == mflSeason, record.profile.providerID == player.providerID,
              record.mflPlayer.id == candidate.id,
              name(record.profile.name) == name(response.profile.name),
              name(record.boxScoreName) == name(player.name),
              name(record.mflPlayer.name) == name(candidate.name),
              position(record.profile.position) == position(response.profile.position),
              compatible(response.profile, candidate) else { return false }
        // Teams can change. An old game's team is evidence, not today's identity.
        return true
    }
}

@MainActor
final class NFLTestMappingStore {
    private struct Archive: Codable { let version: Int; var matches: [NFLTestPlayerMatch] }
    private let defaults: UserDefaults?
    private let key = "nflStatsTest.reviewedPlayerMatches.v1"
    private(set) var matches: [NFLTestPlayerMatch] = []

    init(defaults: UserDefaults? = .standard) throws {
        self.defaults = defaults
        try reload()
    }

    private func reload() throws {
        if let data = defaults?.data(forKey: key) {
            guard let archive = try? JSONDecoder().decode(Archive.self, from: data), archive.version == 1,
                  archive.matches.count <= 500,
                  Set(archive.matches.map(\.id)).count == archive.matches.count,
                  Set(archive.matches.map { "\($0.origin)|\($0.mflPlayer.id)" }).count == archive.matches.count
            else { throw NFLTestMappingError.storage }
            matches = archive.matches
        } else if defaults != nil {
            matches = []
        }
    }

    func confirm(origin: String, response: NFLTestProfileResponse, game: NFLTestGame, player: NFLTestPlayer,
                 candidate: PlayerIdentity, mflSeason: Int, note: String, now: Date = Date()) throws {
        try reload() // Another review window may have changed this ID pair.
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.profile.providerID > 0, candidate.id.allSatisfy({ "0123456789".contains($0) }),
              (1...12).contains(candidate.id.count), !Self.emptyName(response.profile.name), !Self.emptyName(candidate.name),
              note.count >= 10, note.count <= 500, (2000...2100).contains(mflSeason),
              response.fetchedAt.isFinite, response.fetchedAt <= now.timeIntervalSince1970 + 60,
              now.timeIntervalSince1970 - response.fetchedAt < 86_400,
              origin == "synthetic-preview" || (try? NFLTestMappingRules.origin(address: origin)) == origin
        else { throw NFLTestMappingError.invalid }
        let record = NFLTestPlayerMatch(origin: origin, profile: response.profile, mflPlayer: candidate,
            mflSeason: mflSeason, historicalSeason: game.season, gameID: game.id, boxScoreName: player.name,
            gameTeam: player.team, profileFetchedAt: response.fetchedAt, reviewedAt: now, note: note)
        guard NFLTestMappingRules.isCurrent(record, origin: origin, response: response, game: game,
                    player: player, candidate: candidate, mflSeason: mflSeason) else { throw NFLTestMappingError.invalid }
        guard !matches.contains(where: { $0.origin == origin &&
            ($0.profile.providerID == record.profile.providerID || $0.mflPlayer.id == candidate.id) })
        else { throw NFLTestMappingError.conflict }
        guard matches.count < 500 else { throw NFLTestMappingError.storage }
        try save(matches + [record])
    }

    func remove(id: String) throws {
        try reload()
        try save(matches.filter { $0.id != id })
    }

    private func save(_ records: [NFLTestPlayerMatch]) throws {
        guard let data = try? JSONEncoder().encode(Archive(version: 1, matches: records)) else { throw NFLTestMappingError.storage }
        defaults?.set(data, forKey: key)
        matches = records
    }

    private static func emptyName(_ name: String) -> Bool { NFLTestMappingRules.name(name).isEmpty }
}
#endif
