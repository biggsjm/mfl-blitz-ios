#if DEBUG
import Foundation
import MFLCore

/// Native startup tests must never read the owner's Keychain or contact MFL.
/// This is deliberately not selected by ordinary Preview or connected mode.
actor CachedStartupPreviewRepository: LeagueRepository {
    private let offline: Bool
    init(offline: Bool) { self.offline = offline }

    @MainActor static func makeModel() -> AppModel {
        let store = StartupPreviewStore()
        try? store.encode(SavedSession(cookie: "synthetic-startup-only", season: 2026,
            leagueID: "41333", franchiseID: "0001"), key: "session")
        let url = FileManager.default.temporaryDirectory.appending(path: "mfl-synthetic-startup-display.json")
        let repository = CachedStartupPreviewRepository(offline: ProcessInfo.processInfo.arguments.contains("--synthetic-startup-offline"))
        return AppModel(repository: repository, privateStore: store,
            displayCache: LeagueDisplayCache(fileURL: url, privateStore: store))
    }

    func seed(_ cache: LeagueDisplayCache) async {
        guard let workspace = try? await loadWorkspace() else { return }
        guard let identity = await cache.identity(for: workspace) else { return }
        let yesterday = Date().addingTimeInterval(-3_600)
        await cache.save(workspace: workspace, identity: identity, update: .scores(SampleData.scores), now: yesterday)
        await cache.save(workspace: workspace, identity: identity, update: .lineup(SampleData.lineup), now: yesterday)
        await cache.save(workspace: workspace, identity: identity, update: .standings(SampleData.previewStandings), now: yesterday)
        await cache.save(workspace: workspace, identity: identity, update: .board(SampleData.board), now: yesterday)
        if let roster = try? await DemoLeagueRepository().loadTeamRoster(franchiseID: "0001", lineupWeek: nil, refresh: false) {
            await cache.save(workspace: workspace, identity: identity, update: .roster(roster), now: yesterday)
            await cache.save(workspace: workspace, identity: identity, update: .teams([roster.team]), now: yesterday)
        }
    }

    func loadWorkspace() async throws -> LeagueWorkspace {
        var value = SampleData.workspace
        value = LeagueWorkspace(leagueID: value.leagueID, season: value.season, leagueName: "Startup preview",
            franchiseID: value.franchiseID, franchiseName: value.franchiseName, baseURL: value.baseURL, week: value.week)
        return value
    }
    func restoreSession() async throws -> LeagueWorkspace? {
        if !offline { try await Task.sleep(for: .seconds(45)) }
        throw MFLCoreError.transport("Synthetic offline connection")
    }
    func signIn(with credentials: LoginCredentials) async throws -> LeagueWorkspace { throw RepositoryError.invalidCredentials }
    func loadScores(week: Int) async throws -> ScoresSnapshot { SampleData.scores }
    func loadLineup(week: Int) async throws -> LineupSnapshot { SampleData.lineup }
    func loadWaivers() async throws -> WaiverSnapshot { SampleData.waivers }
    func loadStandings() async throws -> [StandingRow] { SampleData.previewStandings }
    func loadBoard() async throws -> [BoardThread] { SampleData.board }
    func loadThread(id: String) async throws -> BoardThread { throw RepositoryError.missingSession }
    func submitLineup(_ lineup: LineupSnapshot) async throws { throw RepositoryError.missingSession }
    func submitWaivers(_ claims: [WaiverClaim], replacing baseline: [WaiverClaim]) async throws { throw RepositoryError.missingSession }
    func postMessage(subject: String?, body: String, threadID: String?) async throws { throw RepositoryError.missingSession }
    func signOut() async {}
}

private final class StartupPreviewStore: PrivateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(_ key: String) -> Data? { lock.withLock { values[key] } }
    func write(_ data: Data, key: String) { lock.withLock { values[key] = data } }
    func remove(_ key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
}
#endif
