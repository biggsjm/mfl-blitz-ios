import SwiftUI
import MFLCore

struct TradingBlockView: View {
    @Environment(AppModel.self) private var app
    @Environment(TransactionsModel.self) private var trades
    let block: TradingBlockModel
    let makeOffer: (TradeDraft) -> Void
    @State private var editing: BlockEditSession?
    @State private var offerToReplace: TradeDraft?
    @State private var discardingDraft = false

    var body: some View {
        List {
            if app.isDemo {
                Label("Preview · No live changes", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if let pending = block.pending {
                Section {
                    Label("Publication needs a check", systemImage: "exclamationmark.shield")
                    Text("Your previous change hasn’t been confirmed.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Check status") { Task { await block.checkStatus() } }.disabled(block.isBusy)
                    Text(pending.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("My trading block") {
                if let listing = block.listing {
                    assets(listing)
                    if !listing.lookingFor.isEmpty { Text("Looking for · \(listing.lookingFor)").font(.subheadline).foregroundStyle(.secondary) }
                }
                HStack {
                Button {
                    editing = BlockEditSession(draft: block.initialDraft)
                } label: {
                    Label(block.draft != nil ? "Resume draft" : block.listing == nil ? "Add to trading block" : "Edit block", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .disabled(!block.canEdit)
                .accessibilityIdentifier("block-edit")
                if block.draft != nil {
                    Spacer()
                    Button("Discard saved draft", systemImage: "trash", role: .destructive) { discardingDraft = true }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).buttonStyle(.borderless)
                        .disabled(block.isBusy || block.pending != nil)
                }
                }
            }
            if block.feed.isLoading && block.feed.snapshot == nil {
                TransactionLoadingRow(title: "Loading trading block…")
            }
            if let error = block.feed.errorMessage {
                Section {
                    Label(error, systemImage: "wifi.exclamationmark").font(.subheadline)
                    Button("Retry") { Task { await block.refresh(force: true) } }
                        .disabled(block.feed.isLoading || (block.feed.retryAfter.map { $0 > Date() } ?? false))
                }
            }
            if let snapshot = block.feed.snapshot {
                let listings = snapshot.listings.filter { $0.id != block.workspace.franchiseID }.sorted {
                    teamName($0.id).localizedStandardCompare(teamName($1.id)) == .orderedAscending
                }
                if listings.isEmpty {
                    ContentUnavailableView("No other listings yet", systemImage: "rectangle.stack",
                        description: Text("Owners can still trade players who aren’t on the block."))
                        .listRowBackground(Color.clear)
                }
                ForEach(listings) { listing in
                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            if let team = snapshot.teams.first(where: { $0.id == listing.id }) {
                                HStack {
                                    TeamMark(abbreviation: team.abbreviation, seed: Int(team.id) ?? 0, artworkURLs: team.artworkURLs)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(team.name).font(.headline)
                                        if !team.ownerName.isEmpty { Text(team.ownerName).font(.subheadline).foregroundStyle(.secondary) }
                                    }
                                }
                            } else { Text(teamName(listing.id)).font(.headline) }
                            assets(listing)
                            if !listing.lookingFor.isEmpty { Text("Looking for · \(listing.lookingFor)").font(.subheadline).foregroundStyle(.secondary) }
                            Button("Make offer", systemImage: "arrow.triangle.swap") {
                                let draft = TradeDraft(partnerID: listing.id, receiving: listing.codes)
                                if trades.draft != nil { offerToReplace = draft }
                                else { makeOffer(draft) }
                            }
                            .buttonStyle(.bordered).disabled(block.isBusy || !trades.canAct)
                            .accessibilityIdentifier("block-offer-\(listing.id)")
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section {
                Link("Open MFL", destination: block.workspace.leagueURL)
                    .font(.footnote).foregroundStyle(.secondary).listRowBackground(Color.clear)
            } footer: {
                if block.listing != nil { Text("To remove your entire listing, use MFL for now.") }
            }
        }
        .task { guard !app.isUsingCachedSession else { return }; await block.refresh() }
        .refreshable { await block.refresh(force: true) }
        .sheet(item: $editing) { session in TradingBlockEditor(block: block, session: session).id(session.id) }
        .alert("Discard trading block draft?", isPresented: $discardingDraft) {
            Button("Cancel", role: .cancel) {}
            Button("Discard draft", role: .destructive) { Task { if await block.saveDraft(nil) { await block.refresh(force: true) } } }
        } message: { Text("Your published trading block won’t change.") }
        .alert("Trading Block", isPresented: Binding(get: { block.notice != nil && editing == nil }, set: { if !$0 { block.notice = nil } })) {
            Button("OK") { block.notice = nil }
        } message: { Text(block.notice ?? "") }
        .confirmationDialog("You have a saved trade draft", isPresented: Binding(get: { offerToReplace != nil }, set: { if !$0 { offerToReplace = nil } }), titleVisibility: .visible) {
            Button("Resume existing draft") { if let draft = trades.draft { makeOffer(draft) }; offerToReplace = nil }
            Button("Replace with this offer", role: .destructive) {
                if let draft = offerToReplace { trades.saveDraft(nil); makeOffer(draft) }
                offerToReplace = nil
            }
            Button("Cancel", role: .cancel) { offerToReplace = nil }
        }
    }

    private func teamName(_ id: String) -> String { block.feed.snapshot?.teams.first { $0.id == id }?.name ?? "Team \(id)" }

    @ViewBuilder private func assets(_ listing: MFLTradingBlockListing) -> some View {
        let team = block.feed.snapshot?.teams.first { $0.id == listing.id }
        ForEach(listing.codes.sorted(), id: \.self) { code in
            let asset = team?.assets.first { $0.id == code }
            if asset?.kind == .player, let scope = app.browseScope {
                NavigationLink(value: PlayerRoute(scope: scope, playerID: code,
                    previewIdentity: PlayerIdentity(id: code, name: asset?.name ?? "Player"))) {
                    Text(asset?.name ?? code).font(.subheadline.weight(.medium))
                }
            } else {
                Label(asset?.name ?? "Unrecognized asset: \(code)", systemImage: asset?.kind == .pick ? "ticket" : "questionmark.circle")
                    .font(.subheadline)
            }
        }
    }
}

struct BlockEditSession: Identifiable { let id = UUID(); var draft: TradingBlockDraft }
private enum BlockEditorRoute: Hashable { case assets }

private struct TradingBlockEditor: View {
    @Environment(\.dismiss) private var dismiss
    let block: TradingBlockModel
    let session: BlockEditSession
    @State private var draft: TradingBlockDraft
    @State private var showingClose = false
    init(block: TradingBlockModel, session: BlockEditSession) {
        self.block = block; self.session = session; _draft = State(initialValue: session.draft)
    }
    var body: some View {
        LeagueBrowseStack {
            Form {
                Section {
                    if let owner = block.owner {
                        NavigationLink(value: BlockEditorRoute.assets) {
                            LabeledContent("Available to trade", value: draft.codes.isEmpty ? "Choose players or picks" : "\(draft.codes.count) selected")
                        }.accessibilityIdentifier("block-choose-assets")
                        ForEach(draft.codes.sorted(), id: \.self) { code in
                            Text(owner.assets.first { $0.id == code }?.name ?? "Unrecognized asset: \(code)")
                                .font(.subheadline)
                        }
                    }
                } footer: { Text("Visible to your league.") }
                Section("Looking for") {
                    TextField("Players, positions, or picks", text: $draft.lookingFor, axis: .vertical).lineLimit(3...5)
                        .accessibilityIdentifier("block-looking-for")
                    if draft.lookingFor.count > 200 {
                        Text("\(draft.lookingFor.count)/256").font(.caption)
                            .foregroundStyle(draft.lookingFor.count > 256 ? Color.orange : .secondary)
                    }
                }
                if block.isBusy { ProgressView("Publishing…").frame(maxWidth: .infinity) }
                if let notice = block.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                if let snapshot = block.feed.snapshot, draft.canPublish,
                   (try? TradingBlockPolicy.validate(draft, fresh: snapshot, ownerID: block.workspace.franchiseID)) == nil {
                    Text("Review the latest listing and selected assets before publishing.").font(.footnote).foregroundStyle(.orange)
                }
            }
            .navigationDestination(for: BlockEditorRoute.self) { _ in
                if let owner = block.owner {
                    TradeAssetPicker(team: TradeTeam(id: owner.id, name: owner.name, abbreviation: owner.abbreviation,
                        assets: owner.assets.filter { [.player, .pick].contains($0.kind) }, blindBidBalance: nil), selected: $draft.codes)
                }
            }
            .navigationTitle("My trading block").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { if draft != session.draft { showingClose = true } else { dismiss() } }.disabled(block.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.baseline == nil ? "Publish" : "Save changes") {
                        Task { if await block.publish(draft) { dismiss() } }
                    }.disabled(!draft.canPublish || !block.canEdit)
                        .accessibilityIdentifier("block-publish")
                }
            }
            .interactiveDismissDisabled(draft != session.draft || block.isBusy)
            .confirmationDialog("Save this draft?", isPresented: $showingClose, titleVisibility: .visible) {
                Button("Save draft") { Task { if await block.saveDraft(draft) { dismiss() } } }.disabled(!draft.hasContent)
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
        }
    }
}
