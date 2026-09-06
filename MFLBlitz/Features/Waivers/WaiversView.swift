import SwiftUI

struct WaiversView: View {
    @Environment(AppModel.self) private var model
    @Binding var searchText: String
    @State private var position = "All"
    @State private var sort = CandidateSort.projection
    @State private var editingClaim: WaiverClaim?
    @State private var showingReview = false

    private enum CandidateSort: String, CaseIterable, Identifiable {
        case trending = "Trending"
        case projection = "Projection"
        case rostered = "Rostered"
        case name = "Name"

        var id: Self { self }
    }

    var body: some View {
        List {
            if model.isLoadingWaivers {
                ProgressView("Loading waivers…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("waiver-loading")
            }
            if let error = model.waiverReadError {
                Section {
                    Label(error, systemImage: "wifi.exclamationmark").font(.subheadline)
                    Button("Refresh waivers") { Task { await model.refreshWaivers() } }.disabled(model.isLoadingWaivers)
                }
            }
            if model.isDemo {
                DemoBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } else if !model.isLoadingWaivers, let reason = model.waivers.unavailableReason {
                Section {
                    Label("Manage waivers on MFL", systemImage: "info.circle").font(.headline)
                    Text(reason).font(.subheadline).foregroundStyle(.secondary)
                    if let workspace = model.workspace { Link("Open MyFantasyLeague", destination: workspace.leagueURL) }
                }
            }

            if let conflict = model.waiverConflict {
                Section("Save needs review") {
                    Text(conflict).font(.subheadline)
                    if model.waiverServerReadFailed {
                        Label("Saved queue unavailable. Pull to refresh before resolving this save.", systemImage: "wifi.exclamationmark")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if model.savedWaiverClaims.isEmpty {
                        Text("MFL currently has no saved bids.").foregroundStyle(.secondary)
                    }
                    ForEach(groupClaims(model.savedWaiverClaims)) { group in
                        Text("Saved on MFL · Round \(group.round)").font(.caption.bold())
                        ForEach(group.claims) { ClaimRow(claim: $0) }
                    }
                    Button("I reviewed MFL’s queue · keep my draft") {
                        model.resolveWaiverConflict(keepDraft: true)
                    }
                    .disabled(model.waiverServerReadFailed || model.isBusy)
                    Button("Discard my draft and use MFL’s queue", role: .destructive) {
                        model.resolveWaiverConflict(keepDraft: false)
                    }
                    .disabled(model.waiverServerReadFailed || model.isBusy)
                }
            }

            if model.hasWaiverChanges {
                Section {
                    Label(model.waivers.claims.isEmpty ? "Draft: cancel every saved bid" : "Draft saved on this device · not submitted yet", systemImage: "square.and.pencil")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }

            Section {
                WaiverHeaderCard(snapshot: model.waivers)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            Section {
                if let workspace = model.workspace {
                    Link("League calendar & waiver tools on MFL", destination: workspace.leagueURL)
                        .font(.footnote)
                }
                if let note = model.waivers.projectionNote {
                    Text(note)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if !model.waivers.claims.isEmpty {
                ForEach(groupClaims(model.waivers.claims)) { group in
                    Section {
                        ForEach(group.claims) { claim in
                            Button {
                                editingClaim = claim
                            } label: {
                                ClaimRow(claim: claim)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edit bid, drop player, or conditional round")
                        }
                        .onDelete { offsets in
                            model.removeClaims(inRound: group.round, at: offsets)
                        }
                        .onMove { offsets, destination in
                            model.moveClaims(inRound: group.round, from: offsets, to: destination)
                        }
                    } header: {
                        HStack {
                            Text("Acquisition round \(group.round)")
                            Spacer()
                            Text("\(group.claims.count) choice\(group.claims.count == 1 ? "" : "s")")
                        }
                    } footer: {
                        Text("MFL tries these bids in order and stops after one succeeds in this round.")
                    }
                }
            }

            Section {
                DisclosureGroup("Recent waiver results") { resultRows }
            }

            Section {
                filterControls
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)

                ForEach(filteredCandidates) { candidate in
                    let hasClaim = model.waivers.claims.contains(where: { $0.player.id == candidate.id })
                    WaiverCandidateRow(
                        candidate: candidate,
                        hasClaim: hasClaim,
                        canAdd: model.waivers.maxRounds > 0,
                        showTrends: model.isDemo
                    ) {
                        if let claim = model.waivers.claims.first(where: { $0.player.id == candidate.id }) {
                            editingClaim = claim
                        } else if model.waivers.maxRounds > 0 {
                            let round = suggestedRound
                            editingClaim = WaiverClaim(
                                player: candidate,
                                bid: model.waivers.minimumBid,
                                dropPlayerID: nil,
                                dropPlayerName: nil,
                                round: round,
                                priority: model.waivers.claims.count(where: { $0.round == round }) + 1
                            )
                        }
                    }
                }
            } header: {
                Text("Available players")
            } footer: {
                if filteredCandidates.isEmpty && !model.isLoadingWaivers && model.waiverReadError == nil {
                    Text("No players match these filters.")
                }
            }

        }
        .listStyle(.insetGrouped)
        .navigationTitle("Transactions")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !model.waivers.claims.isEmpty {
                    EditButton()
                }
                if model.hasWaiverChanges {
                    Button("Review \(model.waivers.claims.count)") { showingReview = true }
                        .fontWeight(.semibold)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.hasWaiverChanges {
                Button {
                    showingReview = true
                } label: {
                    Label(model.waivers.claims.isEmpty ? "Review cancellation of all bids" : "Review \(model.waivers.claims.count) requests", systemImage: "list.clipboard.fill")
                        .font(.headline)
                        .foregroundStyle(Color.blitzNavy)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.blitzGreen, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial)
            }
        }
        .sheet(item: $editingClaim) { claim in
            ClaimEditorView(claim: claim)
        }
        .sheet(isPresented: $showingReview) {
            WaiverReviewView()
        }
        .refreshable { await model.refreshWaivers() }
    }

    private var filterControls: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["All", "QB", "RB", "WR", "TE"], id: \.self) { item in
                        Button {
                            position = item
                        } label: {
                            Text(item)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(position == item ? Color.blitzNavy : Color.primary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 38)
                                .background(position == item ? Color.blitzGreen : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(position == item ? .isSelected : [])
                    }
                }
            }

            HStack {
                Text("Sort by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Sort available players", selection: $sort) {
                    ForEach(CandidateSort.allCases.filter { model.isDemo || ![CandidateSort.trending, .rostered].contains($0) }) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Sort available players")
            }
        }
    }

    @ViewBuilder
    private var resultRows: some View {
        ForEach(model.waivers.results) { result in
            VStack(alignment: .leading, spacing: 4) {
                Text(result.franchise).font(.subheadline.bold())
                Text(result.description).font(.subheadline)
                if let date = result.date {
                    Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if model.waivers.results.isEmpty {
            Text(model.waivers.resultsUnavailable ? "Results couldn’t be loaded. Check MFL for the latest processing report." : "No recent processed claims returned by MFL.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var filteredCandidates: [WaiverCandidate] {
        model.waivers.candidates
            .filter { candidate in
                (position == "All" || candidate.position == position)
                    && (searchText.isEmpty || candidate.name.localizedCaseInsensitiveContains(searchText) || candidate.nflTeam.localizedCaseInsensitiveContains(searchText))
            }
            .sorted { lhs, rhs in
                switch sort {
                case .trending: lhs.trend > rhs.trend
                case .projection: (lhs.projectedPoints ?? -.infinity) > (rhs.projectedPoints ?? -.infinity)
                case .rostered: lhs.rosteredPercent > rhs.rosteredPercent
                case .name: lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
    }

    private var suggestedRound: Int {
        let validRounds = 1 ... max(1, model.waivers.maxRounds)
        let usedRounds = Set(model.waivers.claims.map(\.round))
        return validRounds.first(where: { !usedRounds.contains($0) })
            ?? model.waivers.claims.last?.round
            ?? validRounds.lowerBound
    }
}

private struct WaiverHeaderCard: View {
    let snapshot: WaiverSnapshot

    var body: some View {
        SurfaceCard {
            VStack(spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Waiver budget")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(snapshot.availableBudget, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.system(.largeTitle, design: .rounded, weight: .black))
                    }
                    Spacer()
                    StatusPill(text: "Blind bids", systemImage: "envelope", tone: .neutral)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if let processesAt = snapshot.processesAt {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Next blind-bid run", systemImage: "clock")
                            Text(processesAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                        }
                    } else {
                        Label("Next run: check MFL’s calendar", systemImage: "calendar")
                    }
                    Text(snapshot.claims.isEmpty ? "No bids in your queue" : "\(snapshot.claims.count) bid\(snapshot.claims.count == 1 ? "" : "s") in your queue")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ClaimRow: View {
    let claim: WaiverClaim

    var body: some View {
        HStack(spacing: 12) {
            Text("\(claim.priority)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.blitzNavy)
                .frame(width: 34, height: 34)
                .background(Color.blitzGreen, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(claim.player.name).font(.body.weight(.semibold))
                Text(claim.priority == 1 ? "Round \(claim.round) · First choice" : "Round \(claim.round) · Fallback \(claim.priority)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(claim.dropPlayerName.map { "Drop \($0)" } ?? "No drop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(claim.bid, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.headline.monospacedDigit())
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Round \(claim.round), choice \(claim.priority). Add \(claim.player.name) for \(claim.bid, format: .currency(code: "USD")). \(claim.dropPlayerName.map { "Drop \($0)." } ?? "No drop.")")
    }
}

private struct WaiverCandidateRow: View {
    let candidate: WaiverCandidate
    let hasClaim: Bool
    let canAdd: Bool
    let showTrends: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PositionBadge(position: candidate.position)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(candidate.name).font(.body.weight(.semibold))
                    if let injury = candidate.injuryStatus {
                        Text(injury.rawValue)
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }
                Text(showTrends ? "\(candidate.nflTeam) · \(candidate.rosteredPercent)% rostered · +\(candidate.trend)%" : candidate.nflTeam)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(candidate.projectedPoints.pointsText)
                    .font(.body.bold().monospacedDigit())
                Text("proj").font(.caption2).foregroundStyle(.secondary)
            }
            Button(action: action) {
                Image(systemName: hasClaim ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(hasClaim ? Color.green : Color.blitzGreen)
                    .frame(width: BlitzMetrics.minimumTapTarget, height: BlitzMetrics.minimumTapTarget)
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .opacity(canAdd ? 1 : 0.45)
            .accessibilityLabel(
                hasClaim
                    ? "Edit claim for \(candidate.name)"
                    : canAdd
                        ? "Add claim for \(candidate.name)"
                        : "Maximum conditional rounds reached"
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ClaimEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var claim: WaiverClaim
    @State private var bidText: String
    @FocusState private var bidFocused: Bool

    init(claim: WaiverClaim) {
        _claim = State(initialValue: claim)
        _bidText = State(initialValue: NSDecimalNumber(decimal: claim.bid).stringValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        PositionBadge(position: claim.player.position)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(claim.player.name).font(.headline)
                            Text("\(claim.player.nflTeam) · Projected \(claim.player.projectedPoints.pointsText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("$").foregroundStyle(.secondary)
                        TextField("Amount", text: $bidText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold().monospacedDigit())
                            .focused($bidFocused)
                        Spacer()
                        Text("of \(model.waivers.availableBudget, format: .currency(code: "USD").precision(.fractionLength(0)))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Bid")
                } footer: {
                    Text("Minimum bid: \(model.waivers.minimumBid, format: .currency(code: "USD").precision(.fractionLength(0))). Use \(model.waivers.increment, format: .currency(code: "USD").precision(.fractionLength(0))) increments. Bids stay private until MFL processes them.")
                }

                Section("If successful") {
                    Picker("Drop player", selection: $claim.dropPlayerID) {
                        Text("No drop").tag(String?.none)
                        ForEach(model.lineup.players) { player in
                            Text("\(player.name) · \(player.position)").tag(String?.some(player.id))
                        }
                    }
                    .onChange(of: claim.dropPlayerID) { _, playerID in
                        claim.dropPlayerName = model.lineup.players.first(where: { $0.id == playerID })?.name
                    }
                }

                Section {
                    Picker("Acquisition round", selection: $claim.round) {
                        ForEach(1 ... max(1, model.waivers.maxRounds), id: \.self) { round in
                            Text("Round \(round)").tag(round)
                        }
                    }
                    Label("Within a round, MFL tries bids in priority order and stops after one succeeds. Drag choices in the queue to reprioritize them.", systemImage: "arrow.triangle.branch")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Conditional logic")
                }
            }
            .navigationTitle("Waiver claim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let parsedBid else { return }
                        claim.bid = parsedBid
                        model.upsertClaim(claim)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!validBid)
                }
            }
            .onAppear { bidFocused = true }
        }
    }

    private var parsedBid: Decimal? {
        Decimal(string: bidText, locale: .current)
    }

    private var validBid: Bool {
        guard let parsedBid else { return false }
        return parsedBid >= model.waivers.minimumBid
            && parsedBid <= model.waivers.availableBudget
            && parsedBid.isWholeMultiple(of: model.waivers.increment)
    }
}

private struct WaiverReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showingConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                if model.waivers.claims.isEmpty {
                    Section {
                        Label("Cancel all saved blind-bid requests", systemImage: "trash")
                        Text("This clears every saved acquisition round after you confirm. It does not drop any players from your roster.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                ForEach(groupClaims(model.waivers.claims)) { group in
                    Section("Acquisition round \(group.round)") {
                        ForEach(group.claims) { claim in
                            ClaimRow(claim: claim)
                        }
                    }
                }

                Section("Budget check") {
                    LabeledContent("Available", value: model.waivers.availableBudget, format: .currency(code: "USD").precision(.fractionLength(0)))
                    LabeledContent("Highest single bid", value: highestBid, format: .currency(code: "USD").precision(.fractionLength(0)))
                }
            }
            .navigationTitle("Review waivers")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(
                    title: model.waivers.claims.isEmpty ? "Cancel saved bids on MFL" : "Submit to MFL",
                    systemImage: "paperplane.fill",
                    isBusy: model.isBusy,
                    isDisabled: !model.canSubmitWaivers
                ) {
                    showingConfirmation = true
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .confirmationDialog("Replace saved waiver rounds?", isPresented: $showingConfirmation, titleVisibility: .visible) {
                Button(model.waivers.claims.isEmpty ? "Cancel all saved bids" : "Submit \(model.waivers.claims.count) requests") {
                    Task {
                        if await model.submitWaivers() {
                            dismiss()
                        }
                    }
                }
                Button("Keep reviewing", role: .cancel) {}
            } message: {
                Text("This replaces the complete saved queue across all \(model.waivers.maxRounds) rounds. MFL has no undo API; verify each fallback before continuing.")
            }
        }
    }

    private var highestBid: Decimal {
        model.waivers.claims.map(\.bid).max() ?? 0
    }
}

private struct WaiverRoundGroup: Identifiable {
    let round: Int
    let claims: [WaiverClaim]

    var id: Int { round }
}

private func groupClaims(_ claims: [WaiverClaim]) -> [WaiverRoundGroup] {
    Dictionary(grouping: claims, by: \.round)
        .map { round, claims in
            WaiverRoundGroup(
                round: round,
                claims: claims.sorted(using: KeyPathComparator(\.priority))
            )
        }
        .sorted(using: KeyPathComparator(\.round))
}
