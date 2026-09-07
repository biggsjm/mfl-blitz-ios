import SwiftUI

@main
struct MFLBlitzApp: App {
    @State private var model = Self.initialModel()

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
        }
    }
}
