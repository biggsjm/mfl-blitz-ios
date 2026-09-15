import SwiftUI
import UserNotifications

@main
struct MFLBlitzApp: App {
    @UIApplicationDelegateAdaptor(BlitzNotificationDelegate.self) private var notificationDelegate
    @State private var model = Self.initialModel()

    init() {
        UNUserNotificationCenter.current().delegate = LeagueDeepLinkRouter.shared
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-matchup-mode") {
            UserDefaults.standard.removeObject(forKey: "matchup-view-mode")
        }
        #endif
    }

    private static func initialModel() -> AppModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--synthetic-cached-startup") {
            return CachedStartupPreviewRepository.makeModel()
        }
        #endif
        return AppModel()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--nfl-test-connection-check") {
                NFLStatsConnectionCheckView()
            } else {
                appRoot
            }
            #else
            appRoot
            #endif
        }
    }

    private var appRoot: some View {
        RootView()
            .environment(model)
            .tint(.blitzAction)
            .onOpenURL { LeagueDeepLinkRouter.shared.receive($0) }
    }
}
