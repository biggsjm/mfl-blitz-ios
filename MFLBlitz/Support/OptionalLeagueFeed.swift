import Foundation
import Observation
import MFLCore

actor ProtectedFeedStore {
    private let store: any PrivateStore
    init(_ store: any PrivateStore) { self.store = store }
    func load<T: Decodable & Sendable>(_ type: T.Type, key: String) throws -> T? { try store.decode(type, key: key) }
    func save<T: Encodable & Sendable>(_ value: T, key: String) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 1_000_000 else { throw StoreError.unavailable }
        try store.write(data, key: key)
    }
    func remove(_ key: String) throws { try store.remove(key) }
}

final class PreviewPrivateStore: PrivateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(_ key: String) -> Data? { lock.withLock { values[key] } }
    func write(_ data: Data, key: String) { lock.withLock { values[key] = data } }
    func remove(_ key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
}

/// Optional, account-scoped feeds never participate in the startup critical path.
/// Disk work and encoding run on their store actor; a cancelled view doesn't own
/// the shared request or throw away the previous successful snapshot.
@MainActor @Observable
final class OptionalLeagueFeed<Snapshot: LeagueFeedSnapshot> {
    private(set) var snapshot: Snapshot?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var retryAfter: Date?
    private let scope: String
    private let key: String
    private let ttl: TimeInterval
    private let store: ProtectedFeedStore
    private let loader: @MainActor (Bool) async throws -> Snapshot
    private var inFlight: (id: UUID, task: Task<Void, Never>)?
    private var loadedDisk = false
    private var invalidated = false
    private var lastAttempt: Date?

    init(scope: String, key: String, ttl: TimeInterval, store: ProtectedFeedStore,
         loader: @escaping @MainActor (Bool) async throws -> Snapshot) {
        self.scope = scope; self.key = "\(key).\(scope)"; self.ttl = ttl; self.store = store; self.loader = loader
    }

    func refresh(force: Bool = false) async {
        guard !invalidated else { return }
        if let existing = inFlight {
            await existing.task.value
            guard force, !invalidated else { return }
            if inFlight?.id == existing.id { inFlight = nil }
            // A user-requested verification must start after the older display
            // read, not join a request made before the user's action.
            await refresh(force: true)
            return
        }
        let id = UUID()
        let task = Task { @MainActor [weak self] in await self?.load(force: force) }
        let shared = Task { await task.value; return () }
        inFlight = (id, shared)
        await shared.value
        if inFlight?.id == id { inFlight = nil }
    }

    private func load(force: Bool) async {
        if !loadedDisk {
            loadedDisk = true
            if let cached = try? await store.load(Snapshot.self, key: key), cached.scope == scope,
               (0..<7 * 86_400).contains(Date().timeIntervalSince(cached.fetchedAt)), !invalidated {
                snapshot = cached
            }
        }
        guard !invalidated, retryAfter.map({ $0 <= Date() }) ?? true else { return }
        if !force, let snapshot, (0..<ttl).contains(Date().timeIntervalSince(snapshot.fetchedAt)) { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 15 { return }
        lastAttempt = Date(); isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await loader(force)
            guard !invalidated, fresh.scope == scope, !Task.isCancelled else { return }
            snapshot = fresh; errorMessage = nil; retryAfter = nil
            try? await store.save(fresh, key: key)
        } catch {
            guard !invalidated else { return }
            if MFLCoreError.isCancellation(error) || Task.isCancelled { lastAttempt = nil; return }
            errorMessage = error.localizedDescription
            if case MFLCoreError.rateLimited(let delay) = error { retryAfter = Date().addingTimeInterval(delay ?? 90) }
        }
    }

    func accept(_ snapshot: Snapshot) async {
        guard !invalidated, snapshot.scope == scope else { return }
        self.snapshot = snapshot; errorMessage = nil
        try? await store.save(snapshot, key: key)
    }

    func invalidate() { invalidated = true; inFlight?.task.cancel(); snapshot = nil }
    func finishInvalidation() async {
        invalidate()
        await inFlight?.task.value
        inFlight = nil
    }
}
