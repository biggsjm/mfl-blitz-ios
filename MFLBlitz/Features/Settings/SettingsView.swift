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
                    LabeledContent("Build", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
                } header: {
                    Text("Connected league")
                }

                Section {
                    Toggle("Matchup Live Activity", isOn: Binding(get: { model.matchupActivity.enabled }, set: { enabled in
                        model.matchupActivity.enabled = enabled
                        Task {
                            if enabled { model.matchupActivity.resume(); await model.updateMatchupActivity() }
                            else { await model.matchupActivity.end() }
                        }
                    }))
                    if let error = model.matchupActivity.errorMessage { Text(error).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Game day") } footer: {
                    Text("Shows your current matchup while starters are playing. Scores update while Blitz is open; older scores are marked Update needed. No background push service is connected.")
                }

                Section("Privacy") {
                    Label("No ads or cross-app tracking", systemImage: "hand.raised.fill")
                    Label("Password is never stored", systemImage: "key.fill")
                    Label("Session and drafts protected in this device’s Keychain", systemImage: "lock.shield.fill")
                    Link(
                        "Read the privacy policy",
                        destination: URL(string: "https://github.com/biggsjm/mfl-blitz-ios/blob/main/PRIVACY.md")!
                    )
                }

                if !model.isDemo && model.hasRestrictedLiveActions {
                    Section {
                        Label("Live scores and league data are enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if model.canEditLineup {
                            Label("Lineup changes are enabled", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Lineup changes are unavailable this week", systemImage: "lock.shield.fill")
                                .foregroundStyle(.orange)
                        }
                        Label(model.waivers.unavailableReason == nil ? "Blind-bid submissions are enabled" : "Use MFL for this waiver format or window", systemImage: model.waivers.unavailableReason == nil ? "checkmark.circle.fill" : "info.circle")
                        Label("Message-board posting is enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } header: {
                        Text("Connected league access")
                    } footer: {
                        Text("Saved starters, bid rounds, and posts are read back from MFL. MFL does not expose saved tiebreakers for confirmation. Interrupted writes are never automatically retried.")
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
                    .disabled(model.isBusy || model.transactions.isBusy || model.playerTools.isChangingWatchList || model.tradingBlock?.isBusy == true || model.leagueCalendar?.isSaving == true)
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
                Text("This removes this team’s saved session and local drafts from this device. Submitted league data stays on MyFantasyLeague.")
            }
        }
    }
}
