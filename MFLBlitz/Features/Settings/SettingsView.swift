import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("League", value: model.workspace?.leagueName ?? "—")
                    LabeledContent("Team", value: model.workspace?.franchiseName ?? "—")
                    LabeledContent("Season", value: model.workspace.map { String($0.season) } ?? "—")
                    LabeledContent("League ID", value: model.workspace?.leagueID ?? "—")
                } header: {
                    Text("Connected league")
                }

                Section("Privacy") {
                    Label("No ads or cross-app tracking", systemImage: "hand.raised.fill")
                    Label("Password is never stored", systemImage: "key.fill")
                    Label("Session ends when the app closes", systemImage: "lock.shield.fill")
                    Link(
                        "Read the privacy policy",
                        destination: URL(string: "https://github.com/biggsjm/mfl-blitz-ios/blob/main/PRIVACY.md")!
                    )
                }

                if !model.isDemo && !model.canSubmitChanges {
                    Section {
                        Label("Live scores and league data are enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("Lineup, waiver, and board writes are gated", systemImage: "lock.shield.fill")
                            .foregroundStyle(.orange)
                    } header: {
                        Text("Safety preview")
                    } footer: {
                        Text("Writes unlock only after the MFL client is registered and every mutation is verified in a disposable league.")
                    }
                }

                Section("MyFantasyLeague") {
                    Button("Open league website", systemImage: "safari") {
                        if let workspace = model.workspace,
                           let url = URL(string: "\(workspace.baseURL.absoluteString)/\(workspace.season)/home/\(workspace.leagueID)") {
                            openURL(url)
                        }
                    }
                    Link(
                        "Developer API documentation",
                        destination: URL(
                            string: "https://api.myfantasyleague.com/\(model.workspace?.season ?? Calendar.current.component(.year, from: Date()))/api_info"
                        )!
                    )
                    Link("MFL acceptable use policy", destination: URL(string: "https://home.myfantasyleague.com/acceptable-use-policy/")!)
                }

                Section {
                    Button("Disconnect this device", role: .destructive) {
                        showingSignOutConfirmation = true
                    }
                } footer: {
                    Text("MFL Blitz is an independent open-source client and is not affiliated with or endorsed by MyFantasyLeague, the NFL, or any NFL team.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Disconnect MFL Blitz?", isPresented: $showingSignOutConfirmation, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    Task {
                        await model.signOut()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The in-memory MFL session will end. Your league data stays on MyFantasyLeague.")
            }
        }
    }
}
