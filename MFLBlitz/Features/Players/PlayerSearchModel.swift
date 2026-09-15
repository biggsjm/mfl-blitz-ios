import Foundation
import Observation
import MFLCore

@MainActor
@Observable
final class PlayerSearchModel {
    var query = ""
    private(set) var results = PlayerSearchResults(players: [], total: 0)
    private(set) var recentPlayers: [PlayerIdentity] = []
    private(set) var ownership: PlayerSearchOwnership?
    private(set) var isLoadingCatalog = false
    private(set) var isLoadingOwnership = false
    private(set) var catalogError: String?
    private(set) var ownershipError: String?
    private(set) var catalogVersion = 0
    private(set) var scope: String?
    @ObservationIgnored private var index: PlayerSearchIndex?
    private var catalogLoadedAt: Date?
    private var ownershipRevision: Int?
    private var generation = 0
    private var queryGeneration = 0

    var hasCatalog: Bool { index != nil }

    func reset(scope: String?) {
        generation += 1; queryGeneration += 1
        self.scope = scope
        query = ""; results = .init(players: [], total: 0); recentPlayers = []
        index = nil; ownership = nil; catalogLoadedAt = nil; ownershipRevision = nil
        isLoadingCatalog = false; isLoadingOwnership = false
        catalogError = nil; ownershipError = nil; catalogVersion += 1
    }

    func prepare(scope: String) {
        if self.scope != scope { reset(scope: scope) }
    }

    func loadCatalog(scope: String, now: Date = Date(),
                     using loader: @MainActor () async throws -> PlayerSearchCatalog) async {
        prepare(scope: scope)
        guard !isLoadingCatalog else { return }
        if index != nil, let catalogLoadedAt, (0..<86_400).contains(now.timeIntervalSince(catalogLoadedAt)) { return }
        let request = generation
        isLoadingCatalog = true; catalogError = nil
        defer { if request == generation { isLoadingCatalog = false } }
        do {
            let loaded = try await loader()
            try Task.checkCancellation()
            guard request == generation, loaded.scope == scope else { return }
            index = loaded.index; catalogLoadedAt = now; catalogVersion += 1
            recentPlayers = recentPlayers.compactMap { loaded.index.playersByID[$0.id] }
        } catch {
            guard request == generation, !MFLCoreError.isCancellation(error), !Task.isCancelled else { return }
            catalogError = "Couldn’t update the player list."
        }
    }

    func loadOwnership(scope: String, revision: Int, force: Bool = false, now: Date = Date(),
                       using loader: @MainActor (Bool) async throws -> PlayerSearchOwnership) async {
        prepare(scope: scope)
        guard !isLoadingOwnership else { return }
        let changed = ownershipRevision != nil && ownershipRevision != revision
        if !force, !changed, ownershipError == nil, let ownership,
           (0..<30).contains(now.timeIntervalSince(ownership.checkedAt)) { return }
        let request = generation
        isLoadingOwnership = true; ownershipError = nil
        defer { if request == generation { isLoadingOwnership = false } }
        do {
            let loaded = try await loader(force || changed)
            try Task.checkCancellation()
            guard request == generation, loaded.scope == scope else { return }
            ownership = loaded; ownershipRevision = revision
        } catch {
            guard request == generation, !MFLCoreError.isCancellation(error), !Task.isCancelled else { return }
            ownershipError = ownership == nil ? "Ownership unavailable." : "Ownership may be out of date."
        }
    }

    func search() async {
        queryGeneration += 1
        let request = queryGeneration, scope = scope, query = query
        guard let index else { results = .init(players: [], total: 0); return }
        // Filtering a full NFL catalog never competes with typing/navigation on
        // the main actor. Obsolete keystrokes cannot replace newer results.
        let task = Task.detached(priority: .userInitiated) { index.search(query) }
        let found = await task.value
        guard !Task.isCancelled, request == queryGeneration, scope == self.scope else { return }
        results = found
    }

    func remember(_ player: PlayerIdentity) {
        recentPlayers.removeAll { $0.id == player.id }
        recentPlayers.insert(player, at: 0)
        recentPlayers = Array(recentPlayers.prefix(8))
    }

    func clearRecents() { recentPlayers = [] }
}
