import Foundation
import CryptoKit
import MFLCore

enum ReminderLead: Int, CaseIterable, Codable, Identifiable, Sendable {
    case minutes15 = 900, hour = 3600, day = 86400
    var id: Self { self }
    var title: String {
        switch self { case .minutes15: "15 minutes before"; case .hour: "1 hour before"; case .day: "1 day before" }
    }
}
enum EventReminderChoice: Codable, Equatable, Sendable { case off, before(ReminderLead) }
struct DeadlinePreferences: Codable, Equatable, Sendable {
    var categories: [LeagueEventKind: ReminderLead] = [:]
    var events: [String: EventReminderChoice] = [:]
    var hasEnabledReminders: Bool { !categories.isEmpty || events.values.contains { if case .before = $0 { true } else { false } } }
    func lead(for event: MFLCalendarOccurrence) -> ReminderLead? {
        if let choice = events[event.id] { if case .before(let lead) = choice { return lead }; return nil }
        return categories[event.kind]
    }
}
struct PlannedDeadlineReminder: Equatable, Sendable {
    var id: String
    var eventID: String
    var fireDate: Date
    var eventDate: Date
    var title: String
    var category: LeagueEventKind
    var destination: URL
}

enum DeadlineReminderPolicy {
    static let prefix = "mflblitz.deadline."
    static let window: TimeInterval = 14 * 86_400
    static let budget = 32

    static func identifier(scope: String, eventID: String) -> String {
        prefix + SHA256.hash(data: Data("\(scope)|\(eventID)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func plan(snapshot: LeagueCalendarSnapshot, preferences: DeadlinePreferences, now: Date) -> [PlannedDeadlineReminder] {
        // Only a successfully refreshed feed may schedule new notifications.
        guard (0..<900).contains(now.timeIntervalSince(snapshot.fetchedAt)) else { return [] }
        var seen: Set<String> = []
        return snapshot.events.compactMap { event -> PlannedDeadlineReminder? in
            guard let lead = preferences.lead(for: event) else { return nil }
            let fire = event.start.addingTimeInterval(-Double(lead.rawValue))
            guard fire > now, fire <= now.addingTimeInterval(window), seen.insert(event.id).inserted else { return nil }
            var url = URLComponents()
            url.scheme = "mflblitz"; url.host = "calendar"
            url.queryItems = [URLQueryItem(name: "scope", value: snapshot.scope), URLQueryItem(name: "id", value: event.id)]
            guard let destination = url.url else { return nil }
            return PlannedDeadlineReminder(id: identifier(scope: snapshot.scope, eventID: event.id), eventID: event.id,
                fireDate: fire, eventDate: event.start, title: event.kind.title, category: event.kind, destination: destination)
        }.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(budget).map { $0 }
    }
}
