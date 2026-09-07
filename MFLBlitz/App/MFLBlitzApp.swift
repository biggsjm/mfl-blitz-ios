import SwiftUI
import UserNotifications

@main
struct MFLBlitzApp: App {
    @State private var model = Self.initialModel()

    init() { UNUserNotificationCenter.current().delegate = LeagueDeepLinkRouter.shared }

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
            RootView()
                .environment(model)
                .tint(.blitzGreen)
                .onOpenURL { LeagueDeepLinkRouter.shared.receive($0) }
        }
    }
}
