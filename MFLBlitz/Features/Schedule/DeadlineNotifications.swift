import Foundation
import UserNotifications

enum DeadlineAuthorization: Sendable { case undecided, denied, allowed }

protocol DeadlineNotificationService: Sendable {
    func authorization() async -> DeadlineAuthorization
    func requestPermission() async throws -> Bool
    func reconcile(_ reminders: [PlannedDeadlineReminder], scope: String, complete: Bool) async throws
    func remove(eventID: String, scope: String) async
    func applyOptOuts(_ preferences: DeadlinePreferences, scope: String) async
    func clear() async
}

actor SystemDeadlineNotifications: DeadlineNotificationService {
    private let center = UNUserNotificationCenter.current()
    private var generation = 0
    private var scheduling: (id: UUID, task: Task<Void, Error>)?

    func authorization() async -> DeadlineAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .undecided
        case .authorized, .provisional, .ephemeral: .allowed
        default: .denied
        }
    }
    func requestPermission() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }

    func reconcile(_ reminders: [PlannedDeadlineReminder], scope: String, complete: Bool) async throws {
        let predecessor = scheduling?.task
        let current = generation
        let id = UUID()
        let task = Task {
            _ = try? await predecessor?.value
            guard self.generation == current else { return }
            try await self.apply(reminders, scope: scope, complete: complete)
        }
        scheduling = (id, task)
        do { try await task.value }
        catch { if scheduling?.id == id { scheduling = nil }; throw error }
        if scheduling?.id == id { scheduling = nil }
    }

    private func apply(_ reminders: [PlannedDeadlineReminder], scope: String, complete: Bool) async throws {
        let current = generation
        let pending = await center.pendingNotificationRequests()
        guard generation == current else { return }
        let intended = Set(reminders.map(\.id))
        let obsolete = pending.filter {
            $0.identifier.hasPrefix(DeadlineReminderPolicy.prefix)
                && (($0.content.userInfo["scope"] as? String) != scope || (complete && !intended.contains($0.identifier)))
        }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        var keptIDs = Set(pending.filter { $0.identifier.hasPrefix(DeadlineReminderPolicy.prefix) }.map(\.identifier)).subtracting(obsolete)
        for reminder in reminders {
            guard generation == current else { return }
            guard keptIDs.contains(reminder.id) || keptIDs.count < DeadlineReminderPolicy.budget else { continue }
            guard reminder.fireDate > Date() else { continue }
            if let existing = pending.first(where: { $0.identifier == reminder.id }),
               existing.content.userInfo["eventTimestamp"] as? Double == reminder.eventDate.timeIntervalSince1970,
               existing.content.userInfo["fireTimestamp"] as? Double == reminder.fireDate.timeIntervalSince1970 { continue }
            let content = UNMutableNotificationContent()
            content.title = "MFL Blitz"
            content.body = "\(reminder.title) · \(reminder.eventDate.formatted(date: .abbreviated, time: .shortened))"
            content.sound = .default
            content.userInfo = ["scope": scope, "destination": reminder.destination.absoluteString, "eventID": reminder.eventID, "kind": reminder.category.rawValue,
                "eventTimestamp": reminder.eventDate.timeIntervalSince1970, "fireTimestamp": reminder.fireDate.timeIntervalSince1970]
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            components.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            keptIDs.insert(reminder.id)
            if generation != current { center.removePendingNotificationRequests(withIdentifiers: [reminder.id]); return }
        }
    }
    func remove(eventID: String, scope: String) async {
        generation += 1
        _ = try? await scheduling?.task.value
        let id = DeadlineReminderPolicy.identifier(scope: scope, eventID: eventID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
    func applyOptOuts(_ preferences: DeadlinePreferences, scope: String) async {
        generation += 1
        _ = try? await scheduling?.task.value
        let pending = await center.pendingNotificationRequests()
        let disabled = pending.filter { request in
            let info = request.content.userInfo
            guard request.identifier.hasPrefix(DeadlineReminderPolicy.prefix), info["scope"] as? String == scope else { return false }
            guard let id = info["eventID"] as? String, let raw = info["kind"] as? String, let kind = LeagueEventKind(rawValue: raw) else { return true }
            if let override = preferences.events[id] { if case .off = override { return true }; return false }
            return preferences.categories[kind] == nil
        }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: disabled)
        center.removeDeliveredNotifications(withIdentifiers: disabled)
    }
    func clear() async {
        generation += 1
        _ = try? await scheduling?.task.value
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(DeadlineReminderPolicy.prefix) }.map(\.identifier)
        let delivered = await center.deliveredNotifications().filter { $0.request.identifier.hasPrefix(DeadlineReminderPolicy.prefix) }.map { $0.request.identifier }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }
}

/// Offline previews never request permission or place anything on the device's
/// Lock Screen. The same planning/reconciliation paths remain testable.
actor PreviewDeadlineNotifications: DeadlineNotificationService {
    func authorization() -> DeadlineAuthorization { .allowed }
    func requestPermission() -> Bool { true }
    func reconcile(_ reminders: [PlannedDeadlineReminder], scope: String, complete: Bool) {}
    func remove(eventID: String, scope: String) {}
    func applyOptOuts(_ preferences: DeadlinePreferences, scope: String) {}
    func clear() {}
}
