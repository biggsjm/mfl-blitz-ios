import SwiftUI
import MFLCore

struct AddsDropsView: View {
    @Environment(AppModel.self) private var model
    @State private var roster = RosterToolsModel()
    @State private var section = SectionKind.available
    @State private var availableSearch = ""
    @State private var rosterSearch = ""
    @FocusState private var searchFocused: Bool
    enum SectionKind: String, CaseIterable { case available = "Available", roster = "My roster" }

    private var search: Binding<String> {
        section == .available ? $availableSearch : $rosterSearch
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Players", selection: $section) {
                ForEach(SectionKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .accessibilityIdentifier("adds-drops-sections")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(section == .available ? "Search available players" : "Find a rostered player", text: search)
                    .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                    .accessibilityIdentifier(section == .available ? "waiver-search" : "roster-search")
                if !search.wrappedValue.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { search.wrappedValue = "" }
                        .labelStyle(.iconOnly).foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16).padding(.bottom, 8)
            if section == .available {
                WaiversView(searchText: $availableSearch, rosterTools: roster, refreshRoster: loadRoster)
            } else {
                RosterActionListView(mode: .drops, tools: roster, searchText: rosterSearch)
                    .refreshable { await loadRoster() }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Adds / Drops").navigationBarTitleDisplayMode(.inline)
        .onChange(of: section) { searchFocused = false }
        .task(id: "\(model.workspace?.storageScope ?? "")|\(model.rosterRevision)") { await loadRoster() }
        .sheet(item: $roster.selected) { request in
            RosterActionSheet(player: roster.identity(request.playerID, candidates: model.waivers.candidates), request: request)
        }
    }

    private func loadRoster() async {
        guard let scope = model.workspace?.storageScope else { return }
        await model.loadPendingRosterChange()
        await roster.load(scope: scope) { try await model.loadRosterActionContext() }
    }
}

struct TradesView: View {
    @Environment(AppModel.self) private var app
    @Environment(TransactionsModel.self) private var trades
    @State private var section = 0
    @State private var visitedBlock = false
    @State private var composerSession: TradeComposerSession?
    @State private var selectedOffer: TradeOffer?
    @State private var showingManualResolution = false
    @State private var showingDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Trades", selection: $section) {
                Text("Offers").tag(0)
                Text("Trading Block").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)
                .accessibilityIdentifier("trades-section")
            ZStack {
            VStack(spacing: 0) {
            PrimaryActionButton(
                title: trades.draft == nil ? "Create trade" : "Resume trade",
                systemImage: trades.draft == nil ? "plus" : "square.and.pencil",
                isDisabled: trades.draft == nil ? !trades.canAct : trades.isBusy
            ) { composerSession = TradeComposerSession(savedDraft: trades.draft) }
            .accessibilityLabel(trades.draft == nil ? "Create trade" : "Resume trade")
            .accessibilityIdentifier(trades.draft == nil ? "trade-new" : "trade-resume-draft")
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)

            inbox
            }.opacity(section == 0 ? 1 : 0).allowsHitTesting(section == 0).accessibilityHidden(section != 0)
            if visitedBlock, let block = app.tradingBlock {
                TradingBlockView(block: block) { draft in
                    composerSession = TradeComposerSession(savedDraft: trades.draft, counteroffer: draft)
                }.opacity(section == 1 ? 1 : 0).allowsHitTesting(section == 1).accessibilityHidden(section != 1)
            }
            }
        }
        .onChange(of: section) { if section == 1 { visitedBlock = true } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if section == 0 {
                Menu {
                    Button("Refresh offers", systemImage: "arrow.clockwise") { Task { await trades.refresh() } }
                        .disabled(trades.isLoading || trades.isBusy || (trades.retryAfter.map { $0 > Date() } ?? false))
                    mflLink
                    if trades.draft != nil {
                        Button("Discard draft", role: .destructive) { showingDiscard = true }
                            .disabled(trades.isBusy)
                    }
                } label: { Label("Trade options", systemImage: "ellipsis") }
                .accessibilityIdentifier("trade-options")
                }
            }
        }
        .task { await trades.refresh(ifNeeded: true) }
        .refreshable { await trades.refresh() }
        .sheet(item: $composerSession) { session in TradeComposerView(session: session).id(session.id) }
        .sheet(item: $selectedOffer) { TradeDetailView(initial: $0) }
        .alert("Trades", isPresented: Binding(get: { trades.notice != nil }, set: { if !$0 { trades.notice = nil } })) {
            Button("OK") { trades.notice = nil }
        } message: { Text(trades.notice ?? "") }
        .confirmationDialog("Clear the unconfirmed-action warning?", isPresented: $showingManualResolution, titleVisibility: .visible) {
            Button("I verified the outcome on MFL") { Task { await trades.resolveAfterManualCheck() } }
        } message: { Text("Only clear this after checking MFL’s pending offers, transaction history, and roster. This does not send, accept, decline, or undo a trade.") }
        .alert("Discard trade draft?", isPresented: $showingDiscard) {
            Button("Cancel", role: .cancel) {}
            Button("Discard draft", role: .destructive) { trades.saveDraft(nil) }
        } message: { Text("Sent offers won’t change.") }
    }

    private var inbox: some View {
        List {
            if trades.isDemo { DemoBanner().listRowInsets(EdgeInsets()) }
            if trades.isLoading { TransactionLoadingRow(title: "Checking offers and tradable assets…") }
            if let error = trades.readError {
                Section {
                    Label(error, systemImage: "wifi.exclamationmark").font(.subheadline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(0, Int(ceil((trades.retryAfter ?? .distantPast).timeIntervalSince(context.date))))
                        Button(seconds > 0 ? "Retry in \(seconds)s" : "Retry") { Task { await trades.refresh() } }
                            .disabled(seconds > 0 || trades.isLoading || trades.isBusy)
                    }
                    mflLink
                }
            }
            if let pending = trades.pending {
                Section("Trade action needs verification") {
                    Label("A previous action is not confirmed. Nothing will be sent again automatically.", systemImage: "exclamationmark.shield")
                        .font(.subheadline).foregroundStyle(.orange)
                    TradeCommandSummary(command: pending.command)
                    Button("Check outcome without resending") { Task { await trades.checkPending() } }
                        .disabled(trades.isBusy)
                    mflLink
                    Button("I checked the outcome on MFL…") { showingManualResolution = true }.disabled(trades.isBusy)
                }
            }
            if trades.hasConfirmedEmptyInbox {
                ContentUnavailableView("No active trades", systemImage: "arrow.triangle.swap")
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("trade-empty-inbox")
            }
            if !trades.incoming.isEmpty {
                Section {
                    ForEach(trades.incoming) { offer in
                        Button { selectedOffer = offer } label: { TradeOfferRow(offer: offer) }
                            .buttonStyle(.plain).accessibilityIdentifier("trade-offer-\(offer.id)")
                    }
                } header: { Text("Received · \(trades.incoming.count)") }
            }
            if !trades.outgoing.isEmpty {
                Section {
                    ForEach(trades.outgoing) { offer in
                        Button { selectedOffer = offer } label: { TradeOfferRow(offer: offer) }
                            .buttonStyle(.plain).accessibilityIdentifier("trade-offer-\(offer.id)")
                    }
                } header: { Text("Sent · \(trades.outgoing.count)") }
            }
            if !trades.unresolved.isEmpty {
                Section("Needs review on MFL") {
                    Text("MFL returned \(trades.unresolved.count) offer(s) whose sender could not be verified. Open MFL to review the complete terms.")
                    mflLink
                }
            }
            if let date = trades.snapshot.updatedAt {
                Text("Checked \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 12, for: .scrollContent)
    }

    @ViewBuilder private var mflLink: some View {
        if let workspace = trades.workspace {
            Link(destination: workspace.reportURL("05")) { Label("Open on MFL", systemImage: "arrow.up.right.square") }
                .accessibilityIdentifier("trade-open-mfl")
        }
    }
}

private struct TradeOfferRow: View {
    @Environment(TransactionsModel.self) private var trades
    let offer: TradeOffer
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TradeTeamLabel(team: trades.team(offer.otherTeam(for: trades.ownerID)))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("You receive · \(offer.getting(for: trades.ownerID).map(\.name).joined(separator: ", "))")
                    .font(.subheadline.weight(.semibold))
                Text("You send · \(offer.sending(for: trades.ownerID).map(\.name).joined(separator: ", "))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let expires = offer.expires {
                Text(offer.isExpired ? "Expired" : "Expires \(expires.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(offer.isExpired ? .orange : .secondary)
            }
        }.padding(.vertical, 6)
    }
}

struct TradeTeamLabel: View {
    let team: TradeTeam?
    var body: some View {
        HStack(spacing: 10) {
            TeamMark(abbreviation: team?.abbreviation ?? "?", seed: Int(team?.id ?? "") ?? 0, size: 36, artworkURLs: team?.artworkURLs ?? [])
            Text(team?.name ?? "Unconfirmed trading partner").font(.headline)
        }
    }
}

struct TradeAssetRow: View {
    let asset: TradeAsset
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: asset.kind == .player ? "person.fill" : asset.kind == .pick ? "ticket.fill" : asset.kind == .budget ? "dollarsign.circle.fill" : "questionmark.circle")
                .foregroundStyle(Color.blitzGreen).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name).font(.body.weight(.semibold))
                Text(asset.detail).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(minHeight: 44)
    }
}

struct TradeTerms: View {
    let sending: [TradeAsset]
    let receiving: [TradeAsset]
    var body: some View {
        Section("You receive") { ForEach(receiving) { asset in HStack { TradeAssetRow(asset: asset); Spacer(); TradePlayerResearchLink(asset: asset) } } }
        Section("You send") { ForEach(sending) { asset in HStack { TradeAssetRow(asset: asset); Spacer(); TradePlayerResearchLink(asset: asset) } } }
    }
}

struct TradePlayerResearchLink: View {
    @Environment(AppModel.self) private var model
    let asset: TradeAsset
    var body: some View {
        if asset.kind == .player, let scope = model.browseScope {
            NavigationLink(value: PlayerRoute(scope: scope, playerID: asset.id, inspectedWeek: model.currentWeek,
                previewIdentity: PlayerIdentity(id: asset.id, name: asset.name))) {
                Image(systemName: "info.circle").frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Research \(asset.name)")
            .accessibilityIdentifier("trade-research-\(asset.id)")
        }
    }
}

private struct TradeCommandSummary: View {
    @Environment(TransactionsModel.self) private var trades
    let command: TradeCommand
    var body: some View {
        switch command {
        case .propose(let draft):
            Text("Offer to \(trades.team(draft.partnerID)?.name ?? draft.partnerID)")
            Text("Send: \(trades.assets(draft.giving, teamID: trades.ownerID).map(\.name).joined(separator: ", "))").font(.footnote)
            Text("Receive: \(trades.assets(draft.receiving, teamID: draft.partnerID).map(\.name).joined(separator: ", "))").font(.footnote)
        case .respond(let offer, let response, _): Text("\(response.title) · Offer \(offer.id)")
        }
    }
}

private struct TradeDetailView: View {
    @Environment(TransactionsModel.self) private var trades
    @Environment(\.dismiss) private var dismiss
    let initial: TradeOffer
    @State private var response: ResponseSelection?
    @State private var counterSession: TradeComposerSession?
    private var current: TradeOffer? { trades.snapshot.offers.first { $0.id == initial.id } }

    // Carry the selected action into presentation atomically. Separate action
    // and visibility state can present the previous action on the first tap.
    private struct ResponseSelection: Identifiable {
        let id = UUID()
        let action: MFLTradeResponse
    }

    var body: some View {
        LeagueBrowseStack {
            List {
                if let offer = current {
                    Section { TradeTeamLabel(team: trades.team(offer.otherTeam(for: trades.ownerID))) }
                    TradeTerms(sending: offer.sending(for: trades.ownerID), receiving: offer.getting(for: trades.ownerID))
                    Section {
                        if !offer.comments.isEmpty { Text(offer.comments) }
                        if let expires = offer.expires { LabeledContent("Expires", value: expires.formatted(date: .abbreviated, time: .shortened)) }
                        Text("Offer \(offer.id)").font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        if offer.offeredTo == trades.ownerID {
                            Button("Review acceptance", systemImage: "checkmark.circle") { response = ResponseSelection(action: .accept) }
                                .accessibilityIdentifier("trade-review-accept")
                            Button("Draft counteroffer", systemImage: "arrow.triangle.swap") {
                                let draft = TradeDraft(partnerID: offer.offeredBy ?? "",
                                    giving: Set(offer.receiving.map(\.id)), receiving: Set(offer.giving.map(\.id)), countering: offer)
                                counterSession = TradeComposerSession(savedDraft: trades.draft, counteroffer: draft)
                            }.disabled(trades.draft != nil)
                            Button("Decline offer", role: .destructive) { response = ResponseSelection(action: .reject) }
                                .accessibilityIdentifier("trade-review-decline")
                        } else if offer.offeredBy == trades.ownerID {
                            Button("Withdraw offer", role: .destructive) { response = ResponseSelection(action: .revoke) }
                                .accessibilityIdentifier("trade-review-withdraw")
                        }
                    } footer: {
                        if !offer.isActionable { Text("This offer is expired or contains details that could not be fully verified. Review it on MFL.") }
                        else if trades.draft != nil { Text("Finish or discard your saved draft before drafting a counteroffer.") }
                    }
                    .disabled(!trades.canAct || !offer.isActionable)
                } else {
                    ContentUnavailableView("No longer pending", systemImage: "checkmark.circle", description: Text("This offer is no longer in MFL’s pending list. Check Activity for processing details."))
                }
                if let workspace = trades.workspace { Link("View trades on MFL", destination: workspace.reportURL("05")) }
            }
            .navigationTitle("Trade offer").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(trades.isBusy) } }
            .refreshable { await trades.refresh() }
            .sheet(item: $response) { selection in
                if let current { TradeResponseReviewView(offer: current, response: selection.action).id(selection.id) }
            }
            .sheet(item: $counterSession) { session in TradeComposerView(session: session).id(session.id) }
        }.interactiveDismissDisabled(trades.isBusy)
    }
}

private struct TradeResponseReviewView: View {
    @Environment(TransactionsModel.self) private var trades
    @Environment(\.dismiss) private var dismiss
    let offer: TradeOffer
    let response: MFLTradeResponse
    @State private var comments = ""

    var body: some View {
        LeagueBrowseStack {
            List {
                Section { TradeTeamLabel(team: trades.team(offer.otherTeam(for: trades.ownerID))) }
                TradeTerms(sending: offer.sending(for: trades.ownerID), receiving: offer.getting(for: trades.ownerID))
                if response == .reject {
                    Section("Optional reply") { TextField("Message to the sender", text: $comments, axis: .vertical).lineLimit(3...6) }
                }
                Section {
                    Text(response == .accept
                        ? "Accepting commits to this exact trade. MFL may process it immediately or require league approval. Roster limits and trading deadlines still apply."
                        : response == .reject ? "This declines the offer on MFL and may notify the sender. It does not create a counteroffer."
                        : "This withdraws your offer on MFL. The recipient will no longer be able to accept it.")
                        .font(.subheadline)
                    if trades.isDemo { Text("Preview only · No MFL action will be sent.").foregroundStyle(.orange) }
                    Button {
                        Task { if await trades.perform(.respond(offer, response, comments: comments)) { dismiss() } }
                    } label: {
                        HStack { Spacer(); if trades.isBusy { ProgressView() }; Text(response.title).fontWeight(.semibold); Spacer() }.frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(response == .accept ? .blitzGreen : .red)
                    .foregroundStyle(response == .accept ? Color.blitzNavy : .white)
                    .disabled(!trades.canAct || comments.count > 1_000)
                    .accessibilityIdentifier("trade-confirm-response")
                }
                if let notice = trades.notice { Section { Text(notice).font(.subheadline) } }
            }
            .navigationTitle(response.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(trades.isBusy) } }
        }.interactiveDismissDisabled(trades.isBusy)
    }
}

extension MFLTradeResponse {
    var title: String {
        switch self { case .accept: "Accept trade"; case .reject: "Decline offer"; case .revoke: "Withdraw offer" }
    }
}

struct TransactionActivityView: View {
    @Environment(TransactionsModel.self) private var trades
    @State private var tradesOnly = false
    private var filteredActivity: [TransactionActivity] { trades.activity.filter { !tradesOnly || $0.isTrade } }
    var body: some View {
        List {
            Section { Toggle("Trades only", isOn: $tradesOnly) }
            if trades.isLoadingActivity { TransactionLoadingRow(title: "Loading activity…") }
            if let error = trades.activityError {
                Section {
                    Label(error, systemImage: "wifi.exclamationmark").font(.subheadline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(0, Int(ceil((trades.retryAfter ?? .distantPast).timeIntervalSince(context.date))))
                        Button(seconds > 0 ? "Retry in \(seconds)s" : "Retry activity") { Task { await trades.refreshActivity() } }
                            .disabled(seconds > 0 || trades.isLoadingActivity)
                    }
                }
            }
            ForEach(filteredActivity) { item in
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(item.title, systemImage: item.isTrade ? "arrow.triangle.swap" : "list.bullet.rectangle").font(.headline)
                        if let team = item.teamName {
                            Text(item.partnerName.map { "\(team) ↔ \($0)" } ?? team).font(.subheadline.weight(.semibold))
                        }
                        if item.moves.isEmpty { Text(item.detail).font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(Array(item.moves.enumerated()), id: \.offset) { _, move in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(move.label).font(.caption).foregroundStyle(.secondary)
                                Text(move.names).font(.subheadline)
                            }
                        }
                        if let amount = item.bid { Text("\(amount.formatted(.currency(code: "USD"))) bid").font(.subheadline.weight(.semibold)) }
                        if let date = item.date { Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 6)
                }
            }
            if filteredActivity.isEmpty && !trades.isLoadingActivity && trades.activityError == nil && trades.lastActivityRefresh != nil {
                ContentUnavailableView(tradesOnly ? "No recent trades" : "No recent activity", systemImage: "clock", description: Text("MFL’s recent transactions will appear here."))
            }
            if let workspace = trades.workspace { Link("Full transaction history on MFL", destination: workspace.reportURL("03")) }
        }
        .navigationTitle("League Activity").navigationBarTitleDisplayMode(.inline)
        .task { await trades.refreshActivity(ifNeeded: true) }
        .refreshable { await trades.refreshActivity() }
    }
}

struct TransactionLoadingRow: View {
    let title: String
    var body: some View {
        ProgressView(title)
            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 16)
            .listRowBackground(Color.clear)
    }
}
