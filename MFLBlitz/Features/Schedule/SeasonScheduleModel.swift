import Foundation
import Observation
import MFLCore

enum ScheduleFreshness {
    /// Whole units keep the status useful without a second-by-second counter.
    static func label(updatedAt: Date, now: Date) -> String {
        let age = max(0, now.timeIntervalSince(updatedAt))
        if age < 60 { return "Updated just now" }
        if age < 3_600 { return "Updated \(Int(age / 60)) min ago" }
        if age < 86_400 { return "Updated \(Int(age / 3_600)) hr ago" }
        let days = Int(age / 86_400)
        return "Updated \(days) \(days == 1 ? "day" : "days") ago"
    }
}
@MainActor
@Observable
final class SeasonScheduleModel {
    private(set) var snapshot: SeasonScheduleSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var retryAfter: Date?

    @ObservationIgnored private let loader: @MainActor () async throws -> SeasonScheduleSnapshot
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let timeToLive: TimeInterval
    @ObservationIgnored private var inFlight: (id: UUID, task: Task<SeasonScheduleSnapshot, any Error>)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var lastAttempt: Date?

    init(loader: @escaping @MainActor () async throws -> SeasonScheduleSnapshot) {
        self.loader = loader
        self.now = Date.init
        self.timeToLive = 900
    }

    init() {
        self.loader = { throw RepositoryError.missingSession }
        self.now = Date.init
        self.timeToLive = 900
    }

    /// Internal clock injection makes expiry and session-race tests independent
    /// of wall-clock delays; production uses the fixed fifteen-minute policy.
    init(timeToLive: TimeInterval, now: @escaping @MainActor () -> Date,
         loader: @escaping @MainActor () async throws -> SeasonScheduleSnapshot) {
        self.loader = loader
        self.now = now
        self.timeToLive = max(0, timeToLive)
    }

    func loadIfNeeded() async { await refresh(force: false) }

    func refresh(force: Bool = true) async {
        guard !invalidated else { return }
        if let current = inFlight {
            await finish(current, generation: generation)
            return
        }
        let date = now()
        guard retryAfter.map({ $0 <= date }) ?? true else { return }
        if !force {
            if let snapshot {
                let age = date.timeIntervalSince(snapshot.fetchedAt)
                if age >= 0 && age < timeToLive { return }
            }
            // A failed entry must not trigger another request for every newly
            // rendered week or team. Pull to refresh can explicitly retry.
            if let lastAttempt, date.timeIntervalSince(lastAttempt) >= 0,
               date.timeIntervalSince(lastAttempt) < 15 { return }
        }
        let id = UUID()
        let load = loader
        let task = Task { @MainActor in try await load() }
        let request = (id: id, task: task)
        inFlight = request
        lastAttempt = date
        isLoading = true
        await finish(request, generation: generation)
    }

    func invalidateSession() {
        generation += 1
        invalidated = true
        inFlight?.task.cancel()
        inFlight = nil
        snapshot = nil
        errorMessage = nil
        retryAfter = nil
        lastAttempt = nil
        isLoading = false
    }

    private func finish(_ request: (id: UUID, task: Task<SeasonScheduleSnapshot, any Error>),
                        generation requestGeneration: Int) async {
        do {
            let fresh = try await request.task.value
            guard !invalidated, generation == requestGeneration, inFlight?.id == request.id else { return }
            snapshot = fresh
            errorMessage = nil
            retryAfter = nil
        } catch {
            guard !invalidated, generation == requestGeneration, inFlight?.id == request.id else { return }
            if !(error is CancellationError) {
                errorMessage = snapshot == nil
                    ? "The schedule couldn’t be loaded. \(error.localizedDescription)"
                    : "The schedule couldn’t be refreshed. The saved schedule is shown. \(error.localizedDescription)"
                if case MFLCoreError.rateLimited(let seconds) = error {
                    let delay = seconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 90
                    retryAfter = now().addingTimeInterval(delay)
                }
            }
        }
        guard generation == requestGeneration, inFlight?.id == request.id else { return }
        inFlight = nil
        isLoading = false
    }
}
