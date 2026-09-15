#if DEBUG
import Foundation
import Testing
@testable import MFLBlitz

@MainActor @Suite struct NFLTestPlayerMappingTests {
    private let now = Date(timeIntervalSince1970: 1_789_000_000)
    private let origin = "https://test.example.ts.net:8443"
    private var player: NFLTestPlayer { NFLTestPreview.box.players[0] }
    private var candidate: PlayerIdentity { .init(id: "101", name: "Example Quarterback", position: "QB", nflTeam: "DAL") }
    private func response(id: Int = 10, stale: Bool = false, season: Int = 2024, gameID: Int = 11,
                          name: String = "Example Quarterback", position: String? = "QB") -> NFLTestProfileResponse {
        .init(provider: "API-NFL", testOnly: true, season: season, gameID: gameID,
              fetchedAt: now.timeIntervalSince1970, stale: stale,
              profile: .init(providerID: id, name: name, position: position, college: "Example College", height: nil, weight: nil))
    }
    private func confirm(_ store: NFLTestMappingStore, response: NFLTestProfileResponse? = nil,
                         candidate: PlayerIdentity? = nil, note: String = "Checked both player biographies.") throws {
        try store.confirm(origin: origin, response: response ?? self.response(), game: NFLTestPreview.game,
            player: player, candidate: candidate ?? self.candidate, mflSeason: 2026, note: note, now: now)
    }

    @Test func suggestionsNeverAutoResolveDuplicates() throws {
        let other = PlayerIdentity(id: "102", name: candidate.name, position: "QB", nflTeam: "NYG")
        let store = try NFLTestMappingStore(defaults: nil)
        let found = NFLTestMappingRules.candidates(profile: response().profile, players: [other, candidate], query: candidate.name)
        #expect(found.map(\.id) == ["101", "102"])
        #expect(store.matches.isEmpty)
        #expect(NFLTestMappingRules.name("Example Quarterback Jr.") != NFLTestMappingRules.name(candidate.name))
        #expect(NFLTestMappingRules.name("E. Quarterback") != NFLTestMappingRules.name(candidate.name))
    }

    @Test func rejectsMissingOrConflictingPositionAndTeamUnits() throws {
        for position in [nil, "", "WR", "TMWR", "DEF"] as [String?] {
            let other = PlayerIdentity(id: "102", name: candidate.name, position: position, nflTeam: "DAL")
            #expect(!NFLTestMappingRules.compatible(response().profile, other))
            #expect(throws: (any Error).self) { try confirm(NFLTestMappingStore(defaults: nil), candidate: other) }
        }
        #expect(!NFLTestMappingRules.compatible(response(position: nil).profile, candidate))
    }

    @Test func confirmationNeedsNoteAndFreshHistoricalEvidence() throws {
        for invalid in [response(stale: true), response(season: 2026), response(gameID: 99), response(id: 99)] {
            #expect(throws: (any Error).self) { try confirm(NFLTestMappingStore(defaults: nil), response: invalid) }
        }
        for note in ["", "same", String(repeating: "x", count: 501)] {
            #expect(throws: (any Error).self) { try confirm(NFLTestMappingStore(defaults: nil), note: note) }
        }
        let store = try NFLTestMappingStore(defaults: nil)
        #expect(throws: (any Error).self) {
            try store.confirm(origin: origin, response: response(), game: NFLTestPreview.game, player: player,
                candidate: candidate, mflSeason: 2026, note: "Verified profile identities", now: now.addingTimeInterval(86_401))
        }
        #expect(store.matches.isEmpty)
    }

    @Test func provenancePersistsAndRemovalAllowsCorrection() throws {
        let suite = "NFLMappingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try NFLTestMappingStore(defaults: defaults)
        try confirm(store)
        let restored = try NFLTestMappingStore(defaults: defaults)
        let record = try #require(restored.matches.first)
        #expect(record.historicalSeason == 2024 && record.mflSeason == 2026)
        #expect(record.gameID == 11 && record.profile.providerID == 10 && record.mflPlayer.id == "101")
        #expect(record.reviewedAt == now && record.note == "Checked both player biographies.")
        #expect(record.gameTeam == "Home Team")
        try restored.remove(id: record.id)
        #expect(try NFLTestMappingStore(defaults: defaults).matches.isEmpty)
        try confirm(restored, candidate: .init(id: "102", name: candidate.name, position: "QB"))
        #expect(restored.matches.first?.mflPlayer.id == "102")
    }

    @Test func rejectsBothDirectionsOfIDCollisionAcrossReviewWindows() throws {
        let suite = "NFLMappingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try NFLTestMappingStore(defaults: defaults), second = try NFLTestMappingStore(defaults: defaults)
        try confirm(first)
        #expect(throws: NFLTestMappingError.conflict) {
            try confirm(second, candidate: .init(id: "102", name: candidate.name, position: "QB"))
        }
        let other = NFLTestPlayer(id: "1-12", providerID: 12, name: candidate.name, team: "Other Team", groups: [])
        #expect(throws: NFLTestMappingError.conflict) {
            try second.confirm(origin: origin, response: response(id: 12), game: NFLTestPreview.game, player: other,
                candidate: candidate, mflSeason: 2026, note: "Checked both biographies", now: now)
        }
    }

    @Test func resolverRejectsChangedIdentityMissingCatalogAndDifferentSeason() throws {
        let store = try NFLTestMappingStore(defaults: nil)
        try confirm(store)
        let record = try #require(store.matches.first)
        func valid(_ response: NFLTestProfileResponse, candidate: PlayerIdentity? = nil, year: Int = 2026,
                   server: String? = nil) -> Bool {
            NFLTestMappingRules.isCurrent(record, origin: server ?? origin, response: response, game: NFLTestPreview.game,
                player: player, candidate: candidate, mflSeason: year)
        }
        #expect(valid(response(), candidate: candidate))
        var traded = candidate; traded.nflTeam = "NYG"
        #expect(valid(response(), candidate: traded))
        #expect(!valid(response(), candidate: nil))
        #expect(!valid(response(name: "Different Person"), candidate: candidate))
        #expect(!valid(response(position: "WR"), candidate: candidate))
        #expect(!valid(response(), candidate: candidate, year: 2027))
        #expect(!valid(response(), candidate: candidate, server: "https://other.example.ts.net:8443"))
        #expect(!valid(response(stale: true), candidate: candidate))
        #expect(!valid(response(season: 2026), candidate: candidate))
    }

    @Test func corruptArchiveFailsClosedAndPreviewDoesNotPersist() throws {
        let suite = "NFLMappingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "nflStatsTest.reviewedPlayerMatches.v1")
        #expect(throws: NFLTestMappingError.storage) { try NFLTestMappingStore(defaults: defaults) }
        let preview = try NFLTestMappingStore(defaults: nil)
        try confirm(preview)
        #expect(try NFLTestMappingStore(defaults: nil).matches.isEmpty)
        #expect(defaults.data(forKey: "nflStatsTest.reviewedPlayerMatches.v1") == Data("invalid".utf8))
    }
}
#endif
