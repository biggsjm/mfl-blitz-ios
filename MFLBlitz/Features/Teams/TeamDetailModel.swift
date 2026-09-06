import Foundation
import Observation

@MainActor
@Observable
final class TeamDetailModel {
    private(set) var summary: TeamSummary?
    private(set) var summaryScope: String?
    private(set) var headerErrorMessage: String?
    private(set) var roster: TeamRosterSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var rosterKey: String?
    private var headerKey: String?
    private var rosterRevision = 0
    private var headerRevision = 0
    private var lastLoadedAt: Date?

    func loadHeader(scope: String, franchiseID: String,
                    using loader: @MainActor () async throws -> [TeamSummary]) async {
        let key = "\(scope)|\(franchiseID)"
        if headerKey == key, summary != nil { return }
        headerRevision += 1
        let revision = headerRevision
        if headerKey != key { summary = nil; summaryScope = nil }
        headerKey = key
        headerErrorMessage = nil
        do {
            let teams = try await loader()
            try Task.checkCancellation()
            guard headerRevision == revision else { return }
            summary = teams.first { $0.id == franchiseID }
            summaryScope = scope
        } catch {
            guard headerRevision == revision, !Task.isCancelled, !(error is CancellationError) else { return }
            headerErrorMessage = error.localizedDescription
        }
    }

    func loadRoster(scope: String, franchiseID: String, lineupWeek: Int?, force: Bool = false,
                    using loader: @MainActor () async throws -> TeamRosterSnapshot) async {
        let key = "\(scope)|\(franchiseID)|\(lineupWeek.map(String.init) ?? "none")"
        if !force, rosterKey == key, roster != nil,
           let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 30 { return }
        rosterRevision += 1
        let revision = rosterRevision
        if rosterKey != key { roster = nil; lastLoadedAt = nil }
        rosterKey = key
        isLoading = true
        errorMessage = nil
        defer { if rosterRevision == revision { isLoading = false } }
        do {
            let value = try await loader()
            try Task.checkCancellation()
            guard rosterRevision == revision else { return }
            guard value.scope == scope, value.team.id == franchiseID, value.lineupWeek == lineupWeek else {
                throw RepositoryError.server("The returned roster belongs to a different team or week.")
            }
            roster = value
            summary = value.team
            summaryScope = scope
            lastLoadedAt = Date()
        } catch {
            guard rosterRevision == revision, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func invalidate() {
        rosterRevision += 1
        headerRevision += 1
        rosterKey = nil
        headerKey = nil
        summary = nil
        summaryScope = nil
        headerErrorMessage = nil
        roster = nil
        lastLoadedAt = nil
        isLoading = false
        errorMessage = nil
    }
}
