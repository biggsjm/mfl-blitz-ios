import Foundation
import Observation
import UserNotifications

struct LeagueDeepLink: Equatable, Identifiable {
    enum Destination: Equatable { case calendar(String), matchup(week: Int, id: String) }
    let scope: String
    let destination: Destination
    var id: String { "\(scope)|\(destination)" }

    init?(_ url: URL) {
        guard url.scheme == "mflblitz", url.user == nil, url.password == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let query = parts.queryItems,
              Set(query.map(\.name)).count == query.count,
              let scope = query.first(where: { $0.name == "scope" })?.value, scope.count < 80,
              let id = query.first(where: { $0.name == "id" })?.value, !id.isEmpty, id.count < 160 else { return nil }
        self.scope = scope
        switch url.host {
        case "calendar": destination = .calendar(id)
        case "matchup":
            guard let text = query.first(where: { $0.name == "week" })?.value, let week = Int(text), (1...22).contains(week) else { return nil }
            destination = .matchup(week: week, id: id)
        default: return nil
        }
    }
}

@MainActor @Observable
final class LeagueDeepLinkRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LeagueDeepLinkRouter()
    var pending: LeagueDeepLink?
    func receive(_ url: URL) { pending = LeagueDeepLink(url) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier != UNNotificationDismissActionIdentifier,
           let raw = response.notification.request.content.userInfo["destination"] as? String, let url = URL(string: raw) {
            Task { @MainActor in self.receive(url) }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
