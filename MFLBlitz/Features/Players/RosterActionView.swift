import SwiftUI

struct RosterActionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let player: PlayerIdentity
    @State var request: RosterActionRequest
    @State private var context: RosterActionContext?
    @State private var loading = false
    @State private var submitting = false
    @State private var error: String?
    @State private var receipt: RosterActionReceipt?
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                if model.isDemo { DemoBanner() }
                Section { PlayerIdentityView(player: player) }
                if let context, context.scope == model.workspace?.storageScope {
                    Section("Roster") {
                        LabeledContent("Active", value: "\(context.activeCount) of \(context.activeLimit)")
                        LabeledContent("IR", value: "\(context.irCount) of \(context.irLimit)")
                        if request.kind == .add || request.kind == .activate {
                            Picker("Drop", selection: $request.dropID) {
                                Text("No one").tag(String?.none)
                                ForEach(context.players.filter { context.membership[$0.id] == "ROSTER" && $0.id != player.id }) { value in
                                    Text(value.name).tag(Optional(value.id))
                                }
                            }
                            .disabled(submitting || receipt != nil)
                            .accessibilityIdentifier("roster-drop-player")
                        }
                    }
                    if let problem = context.problem(for: request) {
                        Section { Text(problem).foregroundStyle(.secondary) }
                    } else {
                        Section("This move") {
                            Label("\(player.name) → \(destination)", systemImage: request.kind == .drop ? "minus.circle" : "arrow.right.circle")
                            if let drop = request.dropID {
                                Label("Drop \(context.player(drop).name)", systemImage: "minus.circle").foregroundStyle(.red)
                            }
                            let expected = context.expectedMembership(after: request)
                            Text("Active \(expected.values.filter { $0 == "ROSTER" }.count)/\(context.activeLimit) · IR \(expected.values.filter { $0 == "INJURED_RESERVE" }.count)/\(context.irLimit)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if receipt == nil {
                            Section {
                                Button(request.kind.title, role: request.kind == .drop ? .destructive : nil) { confirming = true }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .disabled(submitting || model.isBusy || model.transactions.isBusy || model.pendingRosterChange != nil || irIneligibilityReason != nil)
                                    .accessibilityIdentifier("confirm-roster-move")
                            } footer: {
                                Text(irIneligibilityReason ?? (request.kind == .reserve ? "MFL checks injury eligibility and league rules." : "This changes your roster immediately."))
                            }
                        }
                    }
                }
                if loading || submitting { ProgressView(submitting ? "Confirming roster…" : "Checking roster…").frame(maxWidth: .infinity) }
                if let receipt { Section { Label(receipt.message, systemImage: receipt.confirmed ? "checkmark.circle.fill" : "clock.badge.questionmark") } }
                if let error { Section { Text(error).foregroundStyle(.secondary) } }
                if context == nil, !loading { Button("Retry availability") { Task { await load() } } }
                PendingRosterChangeSection()
                if let workspace = model.workspace, receipt?.confirmed != true {
                    Section { Link("Check roster on MFL", destination: workspace.leagueURL) }
                }
            }
            .navigationTitle(request.kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(submitting) } }
            .interactiveDismissDisabled(submitting)
            .alert("\(request.kind.title)?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button(request.kind.title, role: request.kind == .drop ? .destructive : nil) { Task { await submit() } }
            } message: { Text(confirmationSummary) }
            .task(id: model.workspace?.storageScope) { await load() }
            .task(id: model.currentWeek) {
                if request.kind == .reserve { await model.loadPlayerAvailability(week: model.currentWeek) }
            }
        }
    }

    private var destination: String {
        switch request.kind { case .add, .activate: "Active roster"; case .reserve: "IR"; case .drop: "Free agents" }
    }
    private var irIneligibilityReason: String? {
        request.kind == .reserve ? model.playerTools.irIneligibilityReason(playerID: player.id, week: model.currentWeek) : nil
    }
    private var confirmationSummary: String {
        var text = "\(player.name) → \(destination)."
        if let drop = request.dropID { text += " Drop \(context?.player(drop).name ?? drop)." }
        return text
    }
    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        await model.loadPendingRosterChange()
        do { context = try await model.loadRosterActionContext() }
        catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
    }
    private func submit() async {
        guard let context, !submitting, receipt == nil else { return }
        submitting = true; error = nil
        defer { submitting = false }
        do { receipt = try await model.performRosterAction(request, reviewed: context) }
        catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
    }
}

struct PendingRosterChangeSection: View {
    @Environment(AppModel.self) private var model
    @State private var acknowledging = false
    var body: some View {
        if model.pendingRosterChange != nil {
            Section("Roster change needs checking") {
                Text(model.rosterChangeError ?? "We haven’t confirmed your last move. It won’t be sent again.")
                    .font(.subheadline)
                Button("Check status") { Task { await model.checkRosterChange() } }.disabled(model.isBusy)
                if let workspace = model.workspace { Link("Check roster on MFL", destination: workspace.leagueURL) }
                Button("I checked MFL") { acknowledging = true }.disabled(model.isBusy)
            }
            .alert("Finished checking your roster?", isPresented: $acknowledging) {
                Button("Keep checking", role: .cancel) {}
                Button("Yes, continue") { Task { await model.acknowledgeRosterChange() } }
            } message: { Text("This clears the notice. It does not send, undo or retry the move.") }
        } else if let error = model.rosterChangeError {
            Section { Text(error).font(.footnote); Button("Retry status") { Task { await model.loadPendingRosterChange() } } }
        }
    }
}

struct RosterManagementView: View {
    @Environment(AppModel.self) private var model
    @State private var context: RosterActionContext?
    @State private var error: String?
    @State private var loading = false
    @State private var selected: RosterActionRequest?
    @State private var showFreeAgents = false
    @State private var search = ""

    var body: some View {
        List {
            if model.isDemo { DemoBanner() }
            PendingRosterChangeSection()
            Section {
                Picker("Players", selection: $showFreeAgents) {
                    Text("My roster").tag(false)
                    Text("Free agents").tag(true)
                }.pickerStyle(.segmented)
            }.listRowBackground(Color.clear).listRowInsets(.init())
            if let context, context.scope == model.workspace?.storageScope {
                Section {
                    Text("Active \(context.activeCount)/\(context.activeLimit) · IR \(context.irCount)/\(context.irLimit)")
                        .font(.subheadline.monospacedDigit())
                    if context.allowed.isEmpty { Text(context.unavailableReason ?? "Check availability on MFL.").font(.footnote).foregroundStyle(.secondary) }
                }
                if showFreeAgents {
                    Section("Available players") {
                        ForEach(model.waivers.candidates.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { candidate in
                            HStack {
                                let identity = PlayerIdentity(id: candidate.id, name: candidate.name, position: candidate.position, nflTeam: candidate.nflTeam)
                                playerLink(identity)
                                Button { selected = .init(kind: .add, playerID: candidate.id) } label: { Image(systemName: "plus.circle.fill").frame(width: 44, height: 44) }
                                    .buttonStyle(.borderless).accessibilityLabel("Add \(candidate.name)")
                                    .disabled(!context.allowed.contains(.add) || model.isBusy)
                            }
                        }
                        if model.waivers.candidates.isEmpty { Text(model.isLoadingWaivers ? "Loading players…" : "Refresh waivers to load available players.").foregroundStyle(.secondary) }
                    }
                } else {
                    ForEach(["ROSTER", "INJURED_RESERVE"], id: \.self) { status in
                        Section(status == "ROSTER" ? "Active roster" : "Injured reserve") {
                            ForEach(context.players.filter { context.membership[$0.id] == status && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }) { player in
                                HStack {
                                    playerLink(player)
                                    Menu {
                                        Button(status == "ROSTER" ? "Move to IR" : "Activate") {
                                            selected = .init(kind: status == "ROSTER" ? .reserve : .activate, playerID: player.id)
                                        }.disabled(!context.allowed.contains(status == "ROSTER" ? .reserve : .activate)
                                            || (status == "ROSTER" && model.playerTools.irIneligibilityReason(playerID: player.id, week: model.currentWeek) != nil))
                                            .accessibilityHint(status == "ROSTER" ? (model.playerTools.irIneligibilityReason(playerID: player.id, week: model.currentWeek) ?? "Review a move to injured reserve") : "Review activation")
                                        Button("Drop player", role: .destructive) { selected = .init(kind: .drop, playerID: player.id) }
                                            .disabled(!context.allowed.contains(.drop))
                                    } label: { Image(systemName: "arrow.up.arrow.down.circle").frame(width: 44, height: 44) }
                                    .disabled(model.isBusy).accessibilityLabel("Manage \(player.name)")
                                }
                            }
                        }
                    }
                }
            }
            if loading { ProgressView("Checking roster…").frame(maxWidth: .infinity) }
            if let error { Section { Text(error); Button("Retry") { Task { await load() } } } }
            if let workspace = model.workspace { Section { Link("Roster tools on MFL", destination: workspace.leagueURL) } }
        }
        .navigationTitle("Roster moves").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a player")
        .task(id: "\(model.workspace?.storageScope ?? "")|\(model.rosterRevision)") { await load() }
        .task(id: showFreeAgents) {
            if showFreeAgents, model.waivers.candidates.isEmpty { await model.refreshWaivers() }
        }
        .task(id: "availability|\(model.workspace?.storageScope ?? "")|\(model.currentWeek)") {
            await model.loadPlayerAvailability(week: model.currentWeek)
        }
        .refreshable {
            await load()
            await model.loadPlayerAvailability(week: model.currentWeek, refresh: true)
            if showFreeAgents { await model.refreshWaivers() }
        }
        .sheet(item: $selected) { request in
            RosterActionSheet(player: identity(request.playerID), request: request)
        }
    }
    @ViewBuilder private func playerLink(_ player: PlayerIdentity) -> some View {
        if let scope = model.browseScope {
            NavigationLink(value: PlayerRoute(scope: scope, playerID: player.id, inspectedWeek: model.currentWeek)) {
                VStack(alignment: .leading, spacing: 4) {
                    PlayerIdentityView(player: player)
                    PlayerAvailabilityCaption(playerID: player.id, nflTeam: player.nflTeam ?? "", week: model.currentWeek)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("roster-move-player-\(player.id)")
        }
    }
    private func identity(_ id: String) -> PlayerIdentity {
        if let player = context?.players.first(where: { $0.id == id }) { return player }
        if let player = model.waivers.candidates.first(where: { $0.id == id }) {
            return PlayerIdentity(id: id, name: player.name, position: player.position, nflTeam: player.nflTeam)
        }
        return PlayerIdentity(id: id, name: "Player \(id)")
    }
    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        await model.loadPendingRosterChange()
        do { context = try await model.loadRosterActionContext() }
        catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
    }
}
