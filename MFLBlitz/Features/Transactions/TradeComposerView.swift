import SwiftUI
import MFLCore

/// A fresh presentation identity and immutable rollback snapshot for each edit.
struct TradeComposerSession: Identifiable {
    let id = UUID()
    let initial: TradeDraft
    let savedDraft: TradeDraft?

    init(savedDraft: TradeDraft?, counteroffer: TradeDraft? = nil) {
        self.savedDraft = savedDraft
        initial = counteroffer ?? savedDraft ?? TradeDraft()
    }
}

struct TradeComposerView: View {
    @Environment(TransactionsModel.self) private var trades
    @Environment(\.dismiss) private var dismiss
    private let session: TradeComposerSession
    @State private var draft: TradeDraft
    @State private var appeared = false
    @State private var isClosing = false
    @State private var showingDiscardChanges = false

    init(session: TradeComposerSession) {
        self.session = session
        _draft = State(initialValue: session.initial)
    }

    private var hasChanges: Bool { draft != session.initial }

    private func cancel() {
        isClosing = true
        trades.saveDraft(session.savedDraft)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Trade with", selection: Binding(get: { draft.partnerID }, set: { partnerID in
                        guard partnerID != draft.partnerID else { return }
                        var updated = draft
                        updated.partnerID = partnerID
                        updated.receiving = []
                        draft = updated
                    })) {
                        Text("Choose a team").tag("")
                        ForEach(trades.snapshot.teams.filter { $0.id != trades.ownerID }) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.navigationLink).disabled(draft.countering != nil)
                    .accessibilityIdentifier("trade-partner")
                    if let partner = trades.team(draft.partnerID) { TradeTeamLabel(team: partner) }
                } footer: { Text("Build an offer, then review both sides before sending it to MFL.") }

                assetSection(title: "You receive", teamID: draft.partnerID, selection: $draft.receiving)
                assetSection(title: "You send", teamID: trades.ownerID, selection: $draft.giving)

                Section("Offer details") {
                    TextField("Optional message", text: $draft.comments, axis: .vertical).lineLimit(3...6)
                        .accessibilityIdentifier("trade-message")
                    DatePicker("Expires", selection: $draft.expires, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Text("\(draft.comments.count)/1,000 characters").font(.caption).foregroundStyle(.secondary)
                }
                if let original = draft.countering {
                    Section("Counteroffer · original \(original.id)") {
                        Text("MFL treats this as a new offer. The original offer remains open and can still be acted on. Decline it separately if you no longer want it.")
                            .font(.subheadline)
                        Toggle("I understand the original stays open", isOn: $draft.acknowledgesOriginalStaysOpen)
                    }
                }
                Section {
                    NavigationLink {
                        TradeProposalReviewView(draft: draft) { isClosing = true; dismiss() }
                    } label: {
                        Label("Review offer", systemImage: "list.clipboard").font(.headline).frame(minHeight: 44)
                    }
                    .disabled(!trades.canAct || trades.validationMessage(for: draft) != nil)
                    .accessibilityIdentifier("trade-review-offer")
                } footer: {
                    Text(trades.validationMessage(for: draft) ?? "Ready for review. Your draft has not been sent.")
                }
            }
            .leagueBrowseDestinations()
            .navigationTitle(draft.countering == nil ? "Build a trade" : "Counteroffer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { showingDiscardChanges = true } else { cancel() }
                    }.disabled(trades.isBusy).accessibilityIdentifier("trade-cancel-draft")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & close") { isClosing = true; trades.saveDraft(draft); dismiss() }
                        .disabled(!draft.hasContent || trades.isBusy).accessibilityIdentifier("trade-save-draft")
                }
            }
            .onAppear {
                guard !appeared, !isClosing else { return }
                appeared = true
                if draft.hasContent { trades.saveDraft(draft) }
            }
            .onChange(of: draft) { _, newValue in
                guard !isClosing else { return }
                trades.saveDraft(newValue)
            }
            .alert("Discard changes?", isPresented: $showingDiscardChanges) {
                Button("Keep editing", role: .cancel) {}
                Button("Discard changes", role: .destructive) { cancel() }
            }
        }
        .interactiveDismissDisabled(trades.isBusy || hasChanges)
    }

    private func assetSection(title: String, teamID: String, selection: Binding<Set<String>>) -> some View {
        Section {
            ForEach(trades.assets(selection.wrappedValue, teamID: teamID)) { asset in
                HStack {
                    HStack { TradeAssetRow(asset: asset); Spacer(); TradePlayerResearchLink(asset: asset) }
                    Spacer()
                    Button("Remove \(asset.name)", systemImage: "minus.circle") { selection.wrappedValue.remove(asset.id) }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).disabled(trades.isBusy)
                }
            }
            if let team = trades.team(teamID) {
                NavigationLink {
                    TradeAssetPicker(team: team, selected: selection)
                } label: { Label("Choose assets", systemImage: "plus.circle").frame(minHeight: 44) }
                    .accessibilityIdentifier(teamID == trades.ownerID ? "trade-choose-send" : "trade-choose-receive")
            } else { Text("Choose a trading partner first.").foregroundStyle(.secondary) }
        } header: { Text(title) }
    }
}

private struct TradeAssetPicker: View {
    @Environment(\.dismiss) private var dismiss
    let team: TradeTeam
    @Binding var selected: Set<String>
    @State private var search = ""
    @State private var budgetText = ""
    private var budgetCode: String { "BB_" + budgetText.replacingOccurrences(of: ",", with: ".") }
    private var budgetAmount: Decimal? { MFLTradeAssetCode.blindBidAmount(budgetCode) }

    var body: some View {
        List {
            Section { TradeTeamLabel(team: team) }
            ForEach([TradeAsset.Kind.player, .pick], id: \.rawValue) { kind in
                let assets = team.assets.filter { $0.kind == kind && (search.isEmpty || "\($0.name) \($0.detail)".localizedCaseInsensitiveContains(search)) }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if !assets.isEmpty {
                    Section(kind == .player ? "Players" : "Draft picks") {
                        ForEach(assets) { asset in
                            HStack {
                            Button {
                                var updated = selected
                                if updated.contains(asset.id) { updated.remove(asset.id) } else { updated.insert(asset.id) }
                                selected = updated
                            } label: {
                                HStack {
                                    TradeAssetRow(asset: asset)
                                    Spacer()
                                    Image(systemName: selected.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(asset.id) ? Color.blitzGreen : .secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(asset.name), \(asset.detail), \(selected.contains(asset.id) ? "selected" : "not selected")")
                            .accessibilityIdentifier("trade-asset-\(asset.id)")
                            TradePlayerResearchLink(asset: asset)
                            }
                        }
                    }
                }
            }
            if let available = team.blindBidBalance, available > 0 {
                Section("Blind-bid budget") {
                    TextField("FAAB amount", text: $budgetText).keyboardType(.decimalPad)
                    Button("Use FAAB amount") {
                        selected = selected.filter { !$0.hasPrefix("BB_") }
                        if let amount = budgetAmount, amount > 0 { selected.insert("BB_\(NSDecimalNumber(decimal: amount).stringValue)") }
                        dismiss()
                    }
                    .disabled(budgetAmount == nil || (budgetAmount ?? -1) < 0 || (budgetAmount ?? -1) > available)
                    if selected.contains(where: { $0.hasPrefix("BB_") }) {
                        Button("Remove FAAB from this offer", role: .destructive) {
                            selected = selected.filter { !$0.hasPrefix("BB_") }; budgetText = ""
                        }
                    }
                    Text("Available to trade: \(available.formatted(.currency(code: "USD"))). MFL rechecks the balance when the offer is sent or accepted.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Choose assets").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Player, position, or draft pick")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { budgetText = selected.first(where: { $0.hasPrefix("BB_") }).map { String($0.dropFirst(3)) } ?? "" }
    }
}

private struct TradeProposalReviewView: View {
    @Environment(TransactionsModel.self) private var trades
    let draft: TradeDraft
    let didSend: () -> Void
    var body: some View {
        List {
            Section { TradeTeamLabel(team: trades.team(draft.partnerID)) }
            TradeTerms(sending: trades.assets(draft.giving, teamID: trades.ownerID), receiving: trades.assets(draft.receiving, teamID: draft.partnerID))
            Section {
                if !draft.comments.isEmpty { Text(draft.comments) }
                LabeledContent("Expires", value: draft.expires.formatted(date: .abbreviated, time: .shortened))
                Text("The other owner can accept until this offer expires or you withdraw it. League deadlines, roster limits, and approval rules apply.").font(.subheadline)
                if draft.countering != nil { Text("The original offer remains open. Decline it separately if you no longer want it.").foregroundStyle(.orange) }
                if trades.isDemo { Text("Preview only · Nothing will be sent to MFL.").foregroundStyle(.orange) }
                Button {
                    Task { if await trades.perform(.propose(draft)) { didSend() } }
                } label: {
                    HStack { Spacer(); if trades.isBusy { ProgressView() }; Text(draft.countering == nil ? "Send trade offer" : "Send counteroffer").fontWeight(.semibold); Spacer() }.frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(.blitzGreen).foregroundStyle(Color.blitzNavy)
                .disabled(!trades.canAct || trades.validationMessage(for: draft) != nil)
                .accessibilityIdentifier("trade-send-offer")
                if let error = trades.validationMessage(for: draft) { Text(error).foregroundStyle(.orange) }
            }
            if let notice = trades.notice { Section { Text(notice) } }
        }
        .navigationTitle("Review trade").navigationBarBackButtonHidden(trades.isBusy)
    }
}
