import SwiftUI
import Observation

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
        switch request.kind { case .add, .activate: "Active roster"; case .reserve: "IR"; case .drop: "Off your roster" }
    }
    private var irIneligibilityReason: String? {
        request.kind == .reserve ? model.playerTools.irIneligibilityReason(playerID: player.id, week: model.currentWeek) : nil
    }
    private var confirmationSummary: String {
        if request.kind == .drop {
            return "Remove \(player.name) from your roster? This releases the player; it does not move them to your bench."
        }
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

@MainActor @Observable
final class RosterToolsModel {
    private(set) var context: RosterActionContext?
    private(set) var error: String?
    private(set) var isLoading = false
    private var scope: String?
    private var revision = 0
    var selected: RosterActionRequest?

    func canPerform(_ kind: RosterActionKind, scope: String?) -> Bool {
        guard let scope, let context, context.scope == scope,
              !isLoading, error == nil, context.pending == nil else { return false }
        return context.allowed.contains(kind)
    }

    func load(scope: String, using loader: () async throws -> RosterActionContext) async {
        // A new roster revision must supersede a cancelled view task even for
        // the same owner. Repository reads already share cached requests.
        if self.scope != scope { context = nil; selected = nil }
        self.scope = scope
        revision += 1
        let request = revision
        isLoading = true; error = nil
        defer { if revision == request { isLoading = false } }
        do {
            let result = try await loader()
            try Task.checkCancellation()
            guard revision == request else { return }
            guard result.scope == scope else {
                context = nil
                self.error = "Roster availability could not be confirmed."
                return
            }
            context = result
        } catch {
            guard revision == request, !(error is CancellationError), !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func identity(_ id: String, candidates: [WaiverCandidate] = []) -> PlayerIdentity {
        if let player = context?.players.first(where: { $0.id == id }) { return player }
        if let player = candidates.first(where: { $0.id == id }) {
            return PlayerIdentity(id: id, name: player.name, position: player.position, nflTeam: player.nflTeam)
        }
        return PlayerIdentity(id: id, name: "Player \(id)")
    }
}

struct InjuredReserveView: View {
    @Environment(AppModel.self) private var model
    @State private var tools = RosterToolsModel()

    var body: some View {
        RosterActionListView(mode: .injuredReserve, tools: tools)
            .task(id: "\(model.workspace?.storageScope ?? "")|\(model.rosterRevision)") { await load() }
            .task(id: "availability|\(model.workspace?.storageScope ?? "")|\(model.currentWeek)") {
                await model.loadPlayerAvailability(week: model.currentWeek)
            }
            .refreshable {
                await load()
                await model.loadPlayerAvailability(week: model.currentWeek, refresh: true)
            }
            .sheet(item: $tools.selected) { request in
                RosterActionSheet(player: tools.identity(request.playerID), request: request)
            }
    }

    private func load() async {
        guard let scope = model.workspace?.storageScope else { return }
        await model.loadPendingRosterChange()
        await tools.load(scope: scope) { try await model.loadRosterActionContext() }
    }
}

/// Two purpose-specific lists share presentation and the existing reviewed
/// mutation machinery, without exposing a catch-all "Manage roster" screen.
struct RosterActionListView: View {
    enum Mode { case drops, injuredReserve }
    @Environment(AppModel.self) private var model
    let mode: Mode
    @Bindable var tools: RosterToolsModel
    var searchText = ""

    var body: some View {
        List {
            if model.isDemo { DemoBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            PendingRosterChangeSection()
            if let context = tools.context, context.scope == model.workspace?.storageScope {
                if mode == .drops {
                    Section {
                        Text("Active \(context.activeCount)/\(context.activeLimit) · IR \(context.irCount)/\(context.irLimit)")
                            .font(.subheadline.monospacedDigit())
                    }
                    if !context.allowed.contains(.drop) {
                        Section { Text(context.unavailableReason ?? "Drops are unavailable. Check MFL.").font(.footnote) }
                    }
                    Section("My roster") {
                        ForEach(players(context)) { player in
                            playerRow(player, kind: .drop, membership: context.membership[player.id])
                        }
                        if players(context).isEmpty { Text("No players match.").foregroundStyle(.secondary) }
                    }
                } else {
                    Section {
                        LabeledContent("IR spots", value: "\(context.irCount) of \(context.irLimit)")
                        LabeledContent("Active roster", value: "\(context.activeCount) of \(context.activeLimit)")
                    }.monospacedDigit()
                    if context.irLimit <= 0 {
                        Section { Text("This league does not have IR spots.").foregroundStyle(.secondary) }
                    } else {
                        Section("On injured reserve") {
                            let reserved = players(context).filter { context.membership[$0.id] == "INJURED_RESERVE" }
                            ForEach(reserved) { playerRow($0, kind: .activate, membership: "INJURED_RESERVE") }
                            if reserved.isEmpty { Text("No players on IR").foregroundStyle(.secondary) }
                        }
                        if !context.allowed.contains(.reserve) && !context.allowed.contains(.activate) {
                            Section { Text(context.unavailableReason ?? "IR moves are unavailable. Check MFL.").font(.footnote) }
                        }
                        Section {
                            let eligible = players(context).filter {
                                context.membership[$0.id] == "ROSTER" &&
                                    model.playerTools.irIneligibilityReason(playerID: $0.id, week: model.currentWeek) == nil
                            }
                            ForEach(eligible) { playerRow($0, kind: .reserve, membership: "ROSTER") }
                            if eligible.isEmpty {
                                Text(model.playerTools.irAvailabilityIssue(week: model.currentWeek)
                                     ?? "No eligible players available").foregroundStyle(.secondary)
                            }
                        } header: { Text("Eligible to move") } footer: {
                            Text(context.irCount >= context.irLimit
                                 ? "IR is full. Activate a player to make room."
                                 : "Players need a current Out or IR designation. Refresh to check eligibility.")
                        }
                    }
                }
            }
            if tools.isLoading { ProgressView("Checking roster…").frame(maxWidth: .infinity) }
            if let error = tools.error {
                Section {
                    Text(error)
                    Button("Retry roster") { Task { await reload() } }.disabled(tools.isLoading)
                }
            }
            if let workspace = model.workspace {
                Section { Link(mode == .drops ? "Adds / drops on MFL" : "Injured reserve on MFL", destination: workspace.leagueURL) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func players(_ context: RosterActionContext) -> [PlayerIdentity] {
        context.players.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.position?.localizedCaseInsensitiveContains(searchText) ?? false)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func playerRow(_ player: PlayerIdentity, kind: RosterActionKind, membership: String?) -> some View {
        HStack(spacing: 12) {
            if let scope = model.browseScope {
                NavigationLink(value: PlayerRoute(scope: scope, playerID: player.id, inspectedWeek: model.currentWeek)) {
                    PlayerIdentityView(player: player, subtitle: membership == "INJURED_RESERVE" ? "IR" : nil)
                }
                .buttonStyle(.plain).accessibilityIdentifier("roster-move-player-\(player.id)")
            }
            Spacer(minLength: 0)
            Button(role: kind == .drop ? .destructive : nil) {
                tools.selected = RosterActionRequest(kind: kind, playerID: player.id)
            } label: {
                Image(systemName: kind == .drop ? "person.badge.minus" : kind == .reserve ? "cross.case" : "arrow.up.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless).tint(kind == .drop ? .red : .primary)
            .accessibilityLabel("\(kind.title), \(player.name)")
            .accessibilityIdentifier("roster-\(kind.rawValue)-\(player.id)")
            .disabled(!canPerform(kind, playerID: player.id))
        }
        .accessibilityElement(children: .contain)
    }

    private func canPerform(_ kind: RosterActionKind, playerID: String) -> Bool {
        guard tools.canPerform(kind, scope: model.workspace?.storageScope),
              !model.isBusy, !model.transactions.isBusy, model.pendingRosterChange == nil else { return false }
        if kind == .reserve {
            guard let context = tools.context, context.irCount < context.irLimit else { return false }
            return model.playerTools.irIneligibilityReason(playerID: playerID, week: model.currentWeek) == nil
        }
        return true
    }

    private func reload() async {
        guard let scope = model.workspace?.storageScope else { return }
        await tools.load(scope: scope) { try await model.loadRosterActionContext() }
    }
}
