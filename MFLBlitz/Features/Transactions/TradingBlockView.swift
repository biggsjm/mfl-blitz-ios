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
    @State private var presentedNotice: String?

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
                let listings = snapshot.listings.filter { $0.id != block.workspace.franchiseID && snapshot.listing(for: $0.id) != nil }.sorted {
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
            }
        }
        .task { guard !app.isUsingCachedSession else { return }; await block.refresh() }
        .refreshable { await block.refresh(force: true) }
        .sheet(item: $editing, onDismiss: { presentedNotice = block.notice }) { session in
            TradingBlockEditor(block: block, session: session).id(session.id)
        }
        .onChange(of: block.notice) {
            if editing == nil { presentedNotice = block.notice }
        }
        .alert("Discard trading block draft?", isPresented: $discardingDraft) {
            Button("Cancel", role: .cancel) {}
            Button("Discard draft", role: .destructive) { Task { if await block.saveDraft(nil) { await block.refresh(force: true) } } }
        } message: { Text("Your published trading block won’t change.") }
        .alert("Trading Block", isPresented: Binding(get: { presentedNotice != nil }, set: { if !$0 { presentedNotice = nil; block.notice = nil } })) {
            Button("OK") { presentedNotice = nil; block.notice = nil }
        } message: { Text(presentedNotice ?? "") }
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
private struct TradingBlockEditor: View {
    @Environment(\.dismiss) private var dismiss
    let block: TradingBlockModel
    let session: BlockEditSession
    @State private var draft: TradingBlockDraft
    @State private var showingClose = false
    @State private var review: BlockReviewSelection?
    @State private var didSubmit = false
    init(block: TradingBlockModel, session: BlockEditSession) {
        self.block = block; self.session = session; _draft = State(initialValue: session.draft)
    }
    var body: some View {
        LeagueBrowseStack {
            List {
                Section {
                    if listed.isEmpty {
                        Text(draft.isRemoval ? "No players on the block." : "Use ↑ to put players on the block.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(listed) { asset in assetRow(asset, listed: true) }
                } header: {
                    HStack { Text("On the block"); Spacer(); Text("\(draft.codes.count)").monospacedDigit() }
                }
                if !draft.isRemoval { Section {
                    TextField("Looking for · optional", text: $draft.lookingFor, axis: .vertical).lineLimit(1...3)
                        .accessibilityIdentifier("block-looking-for")
                    if draft.lookingFor.count > 200 {
                        Text("\(draft.lookingFor.count)/256").font(.caption)
                            .foregroundStyle(draft.lookingFor.count > 256 ? Color.orange : .secondary)
                    }
                } }
                if let notice = block.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                Section("Your roster") {
                    if roster.isEmpty { Text("All available players are on the block.").foregroundStyle(.secondary) }
                    ForEach(roster) { asset in assetRow(asset, listed: false) }
                }
                if !picks.isEmpty {
                    Section {
                        DisclosureGroup("Draft picks") {
                            ForEach(picks) { asset in assetRow(asset, listed: false) }
                        }
                    }
                }
            }
            .navigationTitle("My trading block").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { if draft != session.draft { showingClose = true } else { dismiss() } }.disabled(block.isBusy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 7) {
                    if let validationMessage {
                        Text(validationMessage).font(.caption).foregroundStyle(.orange)
                    }
                    PrimaryActionButton(title: draft.isRemoval ? "Review removal" : "Review & submit trading block", systemImage: "checkmark.circle.fill",
                        isBusy: block.isBusy, isDisabled: !draft.canPublish || !block.canEdit || validationMessage != nil) {
                        review = BlockReviewSelection(draft: draft, assets: listed)
                    }.accessibilityIdentifier("block-review")
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8).background(.ultraThinMaterial)
            }
            .sheet(item: $review, onDismiss: {
                // Finish the child dismissal before closing its editor. Two
                // simultaneous dismissals can strand the receipt behind it.
                if didSubmit { dismiss() }
            }) { selection in
                TradingBlockSubmissionReview(block: block, selection: selection) {
                    didSubmit = true
                    review = nil
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

    private var listed: [TradeAsset] {
        draft.codes.map { code in
            block.owner?.assets.first { $0.id == code }
                ?? TradeAsset(id: code, name: "Unrecognized asset: \(code)", detail: "Check current ownership", kind: .unknown)
        }.sorted(by: BlockAssetSummary.precedes)
    }
    private var roster: [TradeAsset] {
        (block.owner?.assets ?? []).filter { $0.kind == .player && !draft.codes.contains($0.id) }.sorted(by: BlockAssetSummary.precedes)
    }
    private var picks: [TradeAsset] {
        (block.owner?.assets ?? []).filter { $0.kind == .pick && !draft.codes.contains($0.id) }.sorted(by: BlockAssetSummary.precedes)
    }
    private var validationMessage: String? {
        guard draft.canPublish, let snapshot = block.feed.snapshot else { return nil }
        return (try? TradingBlockPolicy.validate(draft, fresh: snapshot, ownerID: block.workspace.franchiseID)) == nil
            ? "Review the latest listing and current ownership before submitting." : nil
    }
    private func assetRow(_ asset: TradeAsset, listed: Bool) -> some View {
        HStack(spacing: 12) {
            BlockAssetSummary(asset: asset)
            Spacer(minLength: 8)
            Button {
                if listed { draft.codes.remove(asset.id) }
                else { draft.codes.insert(asset.id) }
            } label: {
                Image(systemName: listed ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.title3).foregroundStyle(listed ? Color.orange : Color.blitzGreen)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.borderless).disabled(block.isBusy)
                .accessibilityLabel("\(listed ? "Remove from trading block" : "Add to trading block"): \(asset.name)")
                .accessibilityHint("Review and submit when ready. Your roster and lineup stay unchanged.")
                .accessibilityIdentifier("block-\(listed ? "demote" : "promote")-\(asset.id)")
        }.padding(.vertical, 4)
    }
}

private struct BlockReviewSelection: Identifiable {
    let id = UUID()
    let draft: TradingBlockDraft
    let assets: [TradeAsset]
}

private struct TradingBlockSubmissionReview: View {
    @Environment(\.dismiss) private var dismiss
    let block: TradingBlockModel
    let selection: BlockReviewSelection
    let submitted: () -> Void
    var body: some View {
        NavigationStack {
            List {
                if selection.draft.isRemoval {
                    Section {
                        Label("Remove your trading block?", systemImage: "trash")
                        Text("Your listing and Looking for note will be cleared. Every player stays on your roster.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                Section("On the block · \(selection.assets.count)") {
                    ForEach(selection.assets) { BlockAssetSummary(asset: $0).padding(.vertical, 4) }
                }
                if !selection.draft.lookingFor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Looking for") { Text(selection.draft.lookingFor) }
                }
                Section {
                    Text("Visible to your league. Your roster and lineup won’t change.").font(.subheadline).foregroundStyle(.secondary)
                }
                }
                if let notice = block.notice { Text(notice).font(.footnote).foregroundStyle(.orange) }
            }
            .navigationTitle("Review trading block").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(block.isBusy) } }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: selection.draft.isRemoval ? "Remove listing" : "Submit trading block",
                    systemImage: selection.draft.isRemoval ? "trash" : "checkmark.circle.fill",
                    isBusy: block.isBusy, isDisabled: !block.canEdit || !selection.draft.canPublish) {
                    Task { if await block.publish(selection.draft) { submitted() } }
                }.accessibilityIdentifier("block-publish")
                    .padding(16).background(.ultraThinMaterial)
            }
        }.interactiveDismissDisabled(block.isBusy).presentationDetents([.large])
    }
}

private struct BlockAssetSummary: View {
    let asset: TradeAsset
    private var position: String? {
        guard asset.kind == .player else { return nil }
        let code = asset.detail.components(separatedBy: " · ").first ?? ""
        return Self.positions.contains(code) ? code : nil
    }
    private static let positions = ["QB", "RB", "WR", "TE", "PK", "K", "DEF", "DT", "DE", "DL", "LB", "CB", "S", "DB", "PN"]
    static func precedes(_ left: TradeAsset, _ right: TradeAsset) -> Bool {
        func order(_ asset: TradeAsset) -> Int {
            positions.firstIndex(of: asset.detail.components(separatedBy: " · ").first ?? "") ?? positions.count
        }
        if order(left) != order(right) { return order(left) < order(right) }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }
    var body: some View {
        HStack(spacing: 12) {
            if let position { PositionBadge(position: position) }
            else { Image(systemName: asset.kind == .pick ? "ticket" : "person.crop.circle").foregroundStyle(Color.blitzGreen).frame(width: 40) }
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(asset.detail).font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}
