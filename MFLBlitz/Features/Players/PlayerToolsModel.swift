import Foundation
import Observation

@MainActor @Observable
final class PlayerToolsModel {
    private(set) var scope: String?
    private(set) var availability: [Int: PlayerAvailabilitySnapshot] = [:]
    private(set) var availabilityErrors: [Int: String] = [:]
    private(set) var watchList: WatchListSnapshot?
    private(set) var watchError: String?
    private(set) var isLoadingWatchList = false
    private(set) var isChangingWatchList = false
    private(set) var unconfirmedWatch: PendingWatchAction?
    private var loadingWeeks: Set<Int> = []
    private var lastAttempts: [Int: Date] = [:]
    private var generation = 0

    func reset(scope: String?) {
        generation += 1
        self.scope = scope
        availability = [:]; availabilityErrors = [:]; loadingWeeks = []; lastAttempts = [:]
        watchList = nil; watchError = nil; isLoadingWatchList = false; isChangingWatchList = false; unconfirmedWatch = nil
    }

    func loadAvailability(week: Int, refresh: Bool, loader: () async throws -> PlayerAvailabilitySnapshot) async {
        guard !loadingWeeks.contains(week), let scope else { return }
        if !refresh, let last = lastAttempts[week], Date().timeIntervalSince(last) < 60 { return }
        if !refresh, let snapshot = availability[week], Date().timeIntervalSince(snapshot.fetchedAt) < 900 { return }
        let revision = generation
        loadingWeeks.insert(week); lastAttempts[week] = Date()
        defer { if revision == generation { loadingWeeks.remove(week) } }
        do {
            let result = try await loader()
            try Task.checkCancellation()
            guard revision == generation, result.scope == scope, result.week == week else { return }
            if availability.count >= 4, let oldest = availability.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key {
                availability.removeValue(forKey: oldest)
            }
            availability[week] = result
            availabilityErrors[week] = nil
        } catch {
            guard revision == generation, !(error is CancellationError), !Task.isCancelled else { return }
            availabilityErrors[week] = error.localizedDescription
        }
    }

    func loadWatchList(refresh: Bool, loader: () async throws -> WatchListSnapshot) async {
        guard !isLoadingWatchList, !isChangingWatchList, let scope else { return }
        if !refresh, let watchList, Date().timeIntervalSince(watchList.checkedAt) < 60 { return }
        let revision = generation
        isLoadingWatchList = true
        defer { if revision == generation { isLoadingWatchList = false } }
        do {
            let result = try await loader()
            try Task.checkCancellation()
            guard revision == generation, result.scope == scope else { return }
            watchList = result; unconfirmedWatch = result.pending; watchError = nil
        } catch {
            guard revision == generation, !(error is CancellationError), !Task.isCancelled else { return }
            watchError = error.localizedDescription
        }
    }

    func changeWatchList(playerID: String, isWatched: Bool,
                         operation: () async throws -> WatchListSnapshot) async {
        guard !isChangingWatchList, !isLoadingWatchList, unconfirmedWatch == nil, watchList != nil, let scope else { return }
        let revision = generation
        isChangingWatchList = true; watchError = nil
        unconfirmedWatch = PendingWatchAction(playerID: playerID, isWatched: isWatched, startedAt: Date())
        defer { if revision == generation { isChangingWatchList = false } }
        do {
            let result = try await operation()
            guard revision == generation, result.scope == scope else { return }
            watchList = result; unconfirmedWatch = result.pending
        } catch {
            guard revision == generation else { return }
            watchError = "Couldn’t confirm the watchlist change. Check its status before trying again."
        }
    }
}

@MainActor @Observable
final class PlayerResearchModel {
    private(set) var page: PlayerResearchPage?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var key: String?
    private var revision = 0

    func load(scope: String, playerID: String, contextWeek: Int, more: Bool = false,
              loader: (Int?) async throws -> PlayerResearchPage) async {
        let nextKey = "\(scope)|\(playerID)|\(contextWeek)"
        if key == nextKey, isLoading { return }
        if more && (key != nextKey || page?.nextBeforeWeek == nil) { return }
        if key != nextKey { page = nil }
        key = nextKey; revision += 1
        let request = revision
        let before = more ? page?.nextBeforeWeek : nil
        isLoading = true; errorMessage = nil
        defer { if request == revision { isLoading = false } }
        do {
            let result = try await loader(before)
            try Task.checkCancellation()
            guard request == revision, result.scope == scope, result.playerID == playerID else { return }
            if more, var existing = page {
                let known = Set(existing.weeks.map(\.week))
                existing.weeks += result.weeks.filter { !known.contains($0.week) }
                existing.nextBeforeWeek = result.nextBeforeWeek
                page = existing
            } else { page = result }
        } catch {
            guard request == revision, !(error is CancellationError), !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
