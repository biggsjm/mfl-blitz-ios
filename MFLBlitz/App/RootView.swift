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
        .task { await model.restoreSession() }
        .overlay {
            if model.isRestoringSession && model.phase == .onboarding {
                ZStack {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    VStack(spacing: 24) {
                        ProgressView("Reconnecting to MFL…")
                        Text("Checking your saved account. Your drafts stay on this device.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Sign in instead") { model.cancelReconnect() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("cancel-reconnect")
                    }
                    .padding(32)
                }
            }
        }
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
