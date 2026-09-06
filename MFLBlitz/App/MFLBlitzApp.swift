import SwiftUI

@main
struct MFLBlitzApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.blitzGreen)
        }
    }
}
