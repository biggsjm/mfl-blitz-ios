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
                #if DEBUG
                TextField("Scoring service address", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityLabel("Background scoring server")
                #endif
                Button(isChecking ? "Checking…" : "Check connection") {
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
                Text("Scoring connects automatically for your invited MFL team. The server shares MFL checks about once a minute, and Apple delivers updates while your phone is locked. The activity shows its last checked time.")
            }
            Section {
                Text("Blitz sends matchup scores, team and starter details, small logos and an Apple activity token to its server. Your password and drafts are never sent. Initial connection briefly verifies your MFL session without storing it on the server.")
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
