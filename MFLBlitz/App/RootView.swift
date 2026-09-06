import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.phase {
            case .onboarding:
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .signedIn:
                AppTabView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: model.phase)
        .alert(
            model.notice.map { notice in
                switch notice {
                case .success: "All set"
                case .error: "Something went wrong"
                }
            } ?? "",
            isPresented: Binding(
                get: { model.notice != nil },
                set: { if !$0 { model.notice = nil } }
            )
        ) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice?.message ?? "")
        }
    }
}
