import Foundation
import Observation
import MFLCore

@MainActor @Observable
final class LeagueCalendarModel {
    let feed: OptionalLeagueFeed<LeagueCalendarSnapshot>
    let workspace: LeagueWorkspace
    private(set) var preferences = DeadlinePreferences()
    private(set) var permission = DeadlineAuthorization.undecided
    private(set) var isSaving = false
    var notice: String?
    private let store: ProtectedFeedStore
    private let notifications: any DeadlineNotificationService
    private var loadedPreferences = false
    private var preferencesRead: Task<DeadlinePreferences, Error>?
    private var invalidated = false

    init(repository: any LeagueRepository, workspace: LeagueWorkspace, store: ProtectedFeedStore,
         notifications: any DeadlineNotificationService = SystemDeadlineNotifications()) {
        self.workspace = workspace; self.store = store; self.notifications = notifications
        feed = OptionalLeagueFeed(scope: workspace.storageScope, key: "calendar.snapshot", ttl: 900, store: store) {
            try await repository.loadLeagueCalendar(refresh: $0)
        }
    }

    func loadPreferences() async {
        guard !invalidated else { return }
        if !loadedPreferences {
            let task: Task<DeadlinePreferences, Error>
            if let preferencesRead { task = preferencesRead }
            else {
                let store = store, key = "calendar.reminders.\(workspace.storageScope)"
                task = Task { try await store.load(DeadlinePreferences.self, key: key) ?? DeadlinePreferences() }
                preferencesRead = task
            }
            do {
                let restored = try await task.value
                guard !invalidated else { return }
                // Several views may await the same restore. A later waiter must
                // not overwrite a preference the first waiter has since saved.
                if !loadedPreferences { preferences = restored; loadedPreferences = true }
                preferencesRead = nil
            }
            catch {
                preferencesRead = nil
                notice = "Your reminder settings couldn’t be read. Existing reminders haven’t been changed."
                return
            }
        }
        permission = await notifications.authorization()
    }

    func refresh(force: Bool = false) async {
        await loadPreferences()
        await feed.refresh(force: force)
        await reconcile()
    }

    func refreshForForeground() async {
        await loadPreferences()
        guard preferences.hasEnabledReminders else { return }
        await feed.refresh()
        await reconcile()
    }

    func setEvent(_ eventID: String, choice: EventReminderChoice) async -> Bool {
        guard !isSaving, !invalidated else { return false }
        isSaving = true
        defer { isSaving = false }
        await loadPreferences()
        var changed = preferences
        changed.events[eventID] = choice
        if case .off = choice {
            guard await persist(changed) else { return false }
            await notifications.remove(eventID: eventID, scope: workspace.storageScope)
            return true
        }
        return await enable(changed, verifying: eventID)
    }

    func setCategory(_ kind: LeagueEventKind, lead: ReminderLead?) async {
        guard !isSaving, !invalidated else { return }
        isSaving = true
        defer { isSaving = false }
        await loadPreferences()
        var changed = preferences
        changed.categories[kind] = lead
        if lead != nil { _ = await enable(changed, verifying: nil) }
        else {
            guard await persist(changed) else { return }
            await notifications.applyOptOuts(preferences, scope: workspace.storageScope)
            // Remove category alerts immediately even if refreshing is unavailable.
            if let snapshot = feed.snapshot {
                for event in snapshot.events where event.kind == kind && preferences.lead(for: event) == nil {
                    await notifications.remove(eventID: event.id, scope: workspace.storageScope)
                }
            }
            if !preferences.hasEnabledReminders { await notifications.clear() }
        }
    }

    private func enable(_ changed: DeadlinePreferences, verifying eventID: String?) async -> Bool {
        guard !invalidated else { return false }
        await feed.refresh(force: true)
        guard !invalidated, feed.errorMessage == nil, let snapshot = feed.snapshot,
              (0..<900).contains(Date().timeIntervalSince(snapshot.fetchedAt)) else {
            notice = "Refresh the league calendar before adding a reminder."; return false
        }
        if let eventID {
            guard let event = snapshot.events.first(where: { $0.id == eventID }), let lead = changed.lead(for: event),
                  event.start.addingTimeInterval(-Double(lead.rawValue)) > Date() else {
                notice = "This event or reminder time has changed. Review its latest time."; return false
            }
        }
        permission = await notifications.authorization()
        do {
            if permission == .undecided { permission = try await notifications.requestPermission() ? .allowed : .denied }
            guard permission == .allowed else { notice = "Notifications are off. You can enable them in iOS Settings."; return false }
            guard await persist(changed) else { return false }
            await reconcile()
            return notice == nil
        } catch { notice = "The reminder couldn’t be enabled. Please try again."; return false }
    }

    private func persist(_ value: DeadlinePreferences) async -> Bool {
        guard !invalidated, loadedPreferences else { return false }
        do {
            try await store.save(value, key: "calendar.reminders.\(workspace.storageScope)")
            guard !invalidated else { return false }
            preferences = value; notice = nil; return true
        } catch { notice = "Your reminder settings couldn’t be saved."; return false }
    }

    private func reconcile() async {
        guard !invalidated, loadedPreferences, permission == .allowed, feed.errorMessage == nil, let snapshot = feed.snapshot,
              (0..<900).contains(Date().timeIntervalSince(snapshot.fetchedAt)) else { return }
        let plan = DeadlineReminderPolicy.plan(snapshot: snapshot, preferences: preferences, now: Date())
        do { try await notifications.reconcile(plan, scope: workspace.storageScope, complete: snapshot.source.recurrenceVerified) }
        catch { notice = "Some reminders couldn’t be scheduled. Open Calendar to retry." }
    }

    func invalidate() { invalidated = true; feed.invalidate() }
    func disconnect() async {
        invalidate()
        await feed.finishInvalidation()
        await notifications.clear()
    }
}
