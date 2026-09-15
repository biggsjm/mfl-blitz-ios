import SwiftUI

struct MatchupBackgroundSyncSettings: View {
    @Environment(AppModel.self) private var model
    @Bindable var sync: MatchupBackgroundSync
    @State private var address = ""
    @State private var error: String?
    @State private var isChecking = false

    var body: some View {
        Form {
            Section {
                Text(sync.message).font(.callout)
                TextField("https://your-server.your-tailnet.ts.net:8444", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityLabel("Private background scoring server")
                Button(isChecking ? "Checking…" : "Save and check connection") {
                    isChecking = true; error = nil
                    Task {
                        do {
                            if address.trimmingCharacters(in: .whitespacesAndNewlines) != sync.address {
                                try await sync.saveAddress(address)
                                await model.matchupActivity.end()
                                await model.updateMatchupActivity()
                            }
                            await sync.checkConnection()
                        } catch { self.error = error.localizedDescription }
                        isChecking = false
                    }
                }.disabled(isChecking || address.isEmpty)
                if let error { Text(error).foregroundStyle(.secondary).font(.footnote) }
            } header: { Text("Background scoring") } footer: {
                Text("Connect through Tailscale when your matchup is live. Your server checks MFL about every 90 seconds and Apple delivers updates while your phone is locked. Delivery can be delayed; the activity always shows its last checked time.")
            }
            Section {
                Text("Your private server receives this matchup’s team and starter names, scores, starter projections, small logos, and an Apple activity token. Your MFL password, login session and drafts stay on your device.")
                Text("Turning off Matchup Live Activity or disconnecting removes the subscription when reachable. Unreachable subscriptions expire within eight hours. Open Blitz to start a new activity after it ends.")
            }.font(.footnote).foregroundStyle(.secondary)
            Section("Live Activity history") {
                ForEach(model.matchupActivity.lifecycleHistory.reversed()) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.message)
                        Text(event.date, style: .time).foregroundStyle(.secondary)
                    }.font(.footnote)
                }
            }
        }
        .navigationTitle("Background scoring")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { address = sync.address }
    }
}
