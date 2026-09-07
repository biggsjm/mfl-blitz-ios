import SwiftUI

struct ConnectionStatusBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let message = model.connectionMessage {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: model.isRestoringSession ? "arrow.triangle.2.circlepath" : "wifi.slash")
                        .accessibilityHidden(true)
                    Text(message).fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption).foregroundStyle(.secondary)
                if !model.isRestoringSession {
                    HStack(spacing: 16) {
                        Button("Retry") { Task { await model.retryConnection() } }
                        Button("Sign in") { model.reconnectWithSignIn() }
                    }
                    .font(.caption.weight(.semibold)).buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cached-session-status")
        }
    }
}

struct SavedDataLabel: View {
    let date: Date
    var detail: String? = nil
    @MainActor private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var updatedText: String {
        let now = Date()
        return now.timeIntervalSince(date) < 60 ? "Updated just now"
            : "Updated \(Self.formatter.localizedString(for: date, relativeTo: now))"
    }

    var body: some View {
        Label {
            Text([updatedText, detail]
                .compactMap { $0 }.joined(separator: " · "))
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
