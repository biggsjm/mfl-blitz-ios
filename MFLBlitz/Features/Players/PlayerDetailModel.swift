import Foundation
import Observation

@MainActor
@Observable
final class PlayerDetailModel {
    private(set) var detail: PlayerDetailSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var biography: PlayerBio?
    private(set) var hasLoadedBiography = false
    private(set) var isLoadingBiography = false
    private(set) var biographyErrorMessage: String?
    private var requestKey: String?
    private var revision = 0
    private var biographyRevision = 0
    private var lastLoadedAt: Date?

    func load(scope: String, playerID: String, force: Bool = false,
              using loader: @MainActor () async throws -> PlayerDetailSnapshot) async {
        let key = "\(scope)|\(playerID)"
        if !force, requestKey == key, detail != nil,
           let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 15 { return }
        revision += 1
        let requestRevision = revision
        if requestKey != key { detail = nil; lastLoadedAt = nil; resetBiography() }
        requestKey = key
        isLoading = true
        errorMessage = nil
        defer { if revision == requestRevision { isLoading = false } }
        do {
            let loaded = try await loader()
            try Task.checkCancellation()
            guard revision == requestRevision else { return }
            guard loaded.scope == scope, loaded.identity.id == playerID else {
                throw RepositoryError.server("The returned player belongs to a different league or player.")
            }
            detail = loaded
            if let bio = loaded.bio {
                biography = bio
                hasLoadedBiography = true
            }
            lastLoadedAt = Date()
        } catch {
            guard revision == requestRevision, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadBiography(scope: String, playerID: String, force: Bool = false,
                       using loader: @MainActor () async throws -> PlayerBio?) async {
        let key = "\(scope)|\(playerID)"
        guard requestKey == key, detail?.scope == scope, detail?.identity.id == playerID else { return }
        if hasLoadedBiography, !force { return }
        biographyRevision += 1
        let request = biographyRevision
        isLoadingBiography = true; biographyErrorMessage = nil
        defer { if request == biographyRevision { isLoadingBiography = false } }
        do {
            let loaded = try await loader()
            try Task.checkCancellation()
            guard request == biographyRevision, requestKey == key else { return }
            biography = loaded
            hasLoadedBiography = true
        } catch {
            guard request == biographyRevision, requestKey == key,
                  !Task.isCancelled, !(error is CancellationError) else { return }
            biographyErrorMessage = error.localizedDescription
        }
    }

    private func resetBiography() {
        biographyRevision += 1
        biography = nil; hasLoadedBiography = false
        isLoadingBiography = false; biographyErrorMessage = nil
    }

    func invalidate() {
        revision += 1
        requestKey = nil
        detail = nil
        lastLoadedAt = nil
        isLoading = false
        errorMessage = nil
        resetBiography()
    }
}
