import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

@MainActor
struct StartupCacheTests {
    private func makeCache(_ store: MemoryPrivateStore) throws -> (LeagueDisplayCache, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mfl-display-tests-\(UUID().uuidString)")
        try store.encode(SavedSession(cookie: "synthetic-startup-cookie", season: 2026,
            leagueID: "41333", franchiseID: "0001"), key: "session")
        return (LeagueDisplayCache(fileURL: directory.appending(path: "display.json"), privateStore: store), directory)
    }

    @Test("Relaunch displays cached league content before any account response and keeps changes disabled")
    func cachedFirstFrame() async throws {
        let store = MemoryPrivateStore()
        let (cache, directory) = try makeCache(store)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ReliabilityRepository()
        let first = AppModel(repository: repository, privateStore: store, displayCache: cache)
        await first.signIn(credentials: LoginCredentials())
        let cached = try #require(await cache.load())
        #expect(cached.scores?.value.matchups.count == 6)
        #expect(cached.lineup?.value.editState.allowsEditing == false)
        #expect(cached.board?.value.allSatisfy { $0.posts.isEmpty } == true)
        let gate = TestGate()
        await repository.pauseRestore(gate)
        let lineups = await repository.lineupLoads
        let reopenedCache = LeagueDisplayCache(fileURL: directory.appending(path: "display.json"), privateStore: store)
        let reopened = AppModel(repository: repository, privateStore: store, displayCache: reopenedCache)
        let clock = ContinuousClock(), start = ContinuousClock.now
        let task = Task { await reopened.restoreSession() }
        for _ in 0..<100 {
            if reopened.isUsingCachedSession { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        print("[Synthetic startup] cached content visible while authentication is held: \(start.duration(to: clock.now))")
        #expect(reopened.phase == .signedIn)
        #expect(reopened.isRestoringSession)
        #expect(reopened.isUsingCachedSession)
        #expect(reopened.scores.matchups.count == 6 && !reopened.lineup.players.isEmpty)
        #expect(!reopened.standings.isEmpty && !reopened.boardThreads.isEmpty)
        #expect(!reopened.canSubmitLineup && !reopened.canChangeLineupDraft)
        #expect(!reopened.canSubmitWaivers && !reopened.canPostToBoard)
        #expect(reopened.lineupProjectionComparison == nil)
        #expect(reopened.scores.matchups.allSatisfy { matchup in
            matchup.status == .saved && (matchup.away.players + matchup.home.players).allSatisfy { $0.gameSecondsRemaining == nil }
        })
        #expect(await repository.lineupLoads == lineups)
        let lineupGate = TestGate()
        await repository.pauseLineup(lineupGate)
        await gate.open()
        for _ in 0..<100 {
            if !reopened.isUsingCachedSession { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!reopened.isUsingCachedSession && reopened.isLoadingLineup)
        #expect(reopened.cachedLineupDate != nil && !reopened.canChangeLineupDraft && !reopened.canSubmitLineup)
        await lineupGate.open()
        await task.value
        #expect(!reopened.isUsingCachedSession && reopened.connectionMessage == nil)
        #expect(reopened.canSubmitLineup && reopened.cachedLineupDate == nil)
    }

    @Test("An offline launch keeps content, can retry, and never sends changes")
    func offlineRetry() async throws {
        let store = MemoryPrivateStore()
        let (cache, directory) = try makeCache(store)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ReliabilityRepository()
        let first = AppModel(repository: repository, privateStore: store, displayCache: cache)
        await first.signIn(credentials: LoginCredentials())
        await repository.failRestore(.transport("Synthetic offline"))
        let reopened = AppModel(repository: repository, privateStore: store, displayCache: cache)
        await reopened.restoreSession()
        #expect(reopened.phase == .signedIn && reopened.isUsingCachedSession)
        #expect(reopened.connectionMessage == "Offline · Last update shown")
        #expect(reopened.notice == nil && !reopened.isBusy)
        let original = reopened.lineup
        reopened.toggleStarter(original.players[0].id)
        #expect(reopened.lineup == original)
        #expect(!reopened.canSubmitLineup && !reopened.canSubmitWaivers)
        await repository.failRestore(nil)
        await reopened.retryConnection()
        #expect(!reopened.isUsingCachedSession && reopened.canSubmitLineup)
    }

    @Test("Invalid sessions remove cached display instead of treating expired access as offline")
    func expiredSession() async throws {
        let store = MemoryPrivateStore()
        let (cache, directory) = try makeCache(store)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ReliabilityRepository()
        let first = AppModel(repository: repository, privateStore: store, displayCache: cache)
        await first.signIn(credentials: LoginCredentials())
        await repository.failRestore(.unauthorized("Synthetic expiration"))
        let reopened = AppModel(repository: repository, privateStore: store, displayCache: cache)
        await reopened.restoreSession()
        #expect(reopened.phase == .onboarding && reopened.workspace == nil)
        #expect(reopened.scores.matchups.isEmpty && reopened.lineup.players.isEmpty)
        #expect(await cache.load() == nil)
        #expect(try store.decode(SavedSession.self, key: "session") == nil)
    }

    @Test("A saved display is isolated by exact cookie, season, league and franchise", arguments: ["cookie", "season", "league", "franchise", "removed"])
    func isolation(change: String) async throws {
        let store = MemoryPrivateStore()
        let (cache, directory) = try makeCache(store)
        defer { try? FileManager.default.removeItem(at: directory) }
        let identity = try #require(await cache.identity(for: SampleData.workspace))
        await cache.save(workspace: SampleData.workspace, identity: identity, update: .scores(SampleData.scores))
        var session = try #require(try store.decode(SavedSession.self, key: "session"))
        switch change {
        case "cookie": session.cookie = "different-synthetic-cookie"
        case "season": session.season = 2025
        case "league": session.leagueID = "99999"
        case "franchise": session.franchiseID = "0002"
        default: break
        }
        if change == "removed" { store.remove("session") }
        else { try store.encode(session, key: "session") }
        #expect(await cache.load() == nil)
        await cache.save(workspace: SampleData.workspace, identity: identity, update: .scores(SampleData.scores))
        #expect(await cache.load() == nil) // Late old-session responses cannot publish.
    }

    @Test("Cache age stays per section; fresh identity metadata cannot rejuvenate old scores")
    func perSectionAge() async throws {
        let store = MemoryPrivateStore()
        let (cache, directory) = try makeCache(store)
        defer { try? FileManager.default.removeItem(at: directory) }
        let identity = try #require(await cache.identity(for: SampleData.workspace))
        let now = Date()
        await cache.save(workspace: SampleData.workspace, identity: identity,
            update: .scores(SampleData.scores), now: now.addingTimeInterval(-8 * 86_400))
        await cache.save(workspace: SampleData.workspace, identity: identity,
            update: .standings(SampleData.standings), now: now)
        let cached = try #require(await cache.load(now: now))
        #expect(cached.scores == nil && cached.standings != nil)
        #expect(await cache.load(now: now.addingTimeInterval(-100)) == nil)
        let raw = try String(contentsOf: directory.appending(path: "display.json"), encoding: .utf8)
        #expect(!raw.contains("synthetic-startup-cookie"))
        let excluded = try directory.appending(path: "display.json").resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(excluded.isExcludedFromBackup == true)
    }

    @Test("Corrupt caches are ignored and sign out clears a healthy cache")
    func corruptionAndSignOut() async throws {
        let store = MemoryPrivateStore()
        let (cache, directory) = try makeCache(store)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(repository: ReliabilityRepository(), privateStore: store, displayCache: cache)
        await model.signIn(credentials: LoginCredentials())
        let url = directory.appending(path: "display.json")
        try Data("not JSON".utf8).write(to: url)
        #expect(await cache.load() == nil)
        await model.refreshScores()
        #expect(await cache.load() != nil)
        await model.signOut()
        #expect(await cache.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Cold entry gives scores and lineup priority over optional feeds")
    func priorityBudget() async throws {
        let repository = ReliabilityRepository()
        let gate = TestGate()
        await repository.pauseLineup(gate)
        let model = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        let task = Task { await model.signIn(credentials: LoginCredentials()) }
        for _ in 0..<100 {
            if !model.scores.matchups.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.scores.matchups.isEmpty && model.phase == .signedIn)
        #expect(await repository.waiverLoads == 0)
        #expect(await repository.standingsLoads == 0)
        #expect(await repository.boardLoads == 0)
        #expect(await repository.tradeLoads == 0)
        await gate.open()
        await task.value
        #expect(await repository.waiverLoads == 1)
        #expect(await repository.boardLoads == 1)
    }
}
