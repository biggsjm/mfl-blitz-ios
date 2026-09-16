import SwiftUI

struct LeagueBetaAccessView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("League services", value: model.isDemo ? "Preview" : model.betaServicesMessage)
                if model.betaServicesMessage != "Connected" {
                    Button("Reconnect") { model.connectBetaServicesIfNeeded(force: true) }
                        .disabled(model.isDemo || model.isUsingCachedSession || model.betaServicesMessage == "Connecting…")
                }
            } footer: {
                Text("NFL stats and background scoring connect automatically for your invited MFL team. No access code or Tailscale app is needed.")
            }
            Section {
                NavigationLink("Lineup alerts") { LineupAlertSettings() }
            } footer: {
                Text("Alerts are optional. To verify team access, Blitz briefly checks your MFL session with MFL through its server. Your password is never sent to the server, and your session is not stored there.")
            }
        }
        .navigationTitle("League services")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.connectBetaServicesIfNeeded() }
    }
}
