import SwiftUI

struct LineupView: View {
    @Environment(AppModel.self) private var model
    @State private var reviewedLineup: LineupReviewRequest?
    @State private var replacementRequest: AppModel.LineupReplacementRequest?
    @State private var startRequest: AppModel.LineupStartRequest?
    @State private var showingLineupCheck = false
    @State private var readinessReplacement: AppModel.LineupReplacementRequest?

    private struct LineupReviewRequest: Identifiable {
        let id = UUID()
        let lineup: LineupSnapshot
    }

    var body: some View {
      ScrollViewReader { proxy in
        List {
            if model.connectionMessage != nil {
                ConnectionStatusBanner().listRowBackground(Color.clear)
            }
            if !model.isDemo, let upcoming = model.workspace?.lineupWeek, upcoming != model.selectedWeek,
               model.availableWeeks.contains(upcoming) {
                Section {
                    Button("Open MFL’s lineup week · \(upcoming)") {
                        Task { await model.changeWeek(to: upcoming) }
                    }
                }
            }

            if let error = model.lineupRefreshError {
                Label(error, systemImage: "exclamationmark.triangle").font(.subheadline)
            }
            if model.configuredWeekRange == nil {
                Text("League week range unavailable. Only known weeks are shown.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.isDemo {
                DemoBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } else if let saved = model.cachedLineupDate {
                SavedDataLabel(date: saved, detail: model.isLoadingLineup || model.isRestoringSession ? "Updating lineup" : "Refresh to edit")
                    .listRowBackground(Color.clear)
            } else if !model.canEditLineup {
                LiveWriteSafetyBanner(
                    message: model.lineup.editState.unavailableMessage
                        ?? "Lineup changes unavailable"
                )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if let conflict = model.lineupConflict {
                Section("Draft needs review") {
                    Text(conflict).font(.subheadline)
                    Button("Discard draft and load MFL starters", role: .destructive) { model.discardLineupDraft() }
                }
            }

            if model.lineup.players.isEmpty && model.isLoadingLineup {
                ProgressView("Loading Week \(model.selectedWeek) lineup…")
                    .listRowBackground(Color.clear)
            } else if model.lineup.players.isEmpty {
                EmptyState(
                    title: "Lineup unavailable",
                    message: model.lineup.editState.unavailableMessage
                        ?? "MFL didn’t return a roster for Week \(model.lineup.week). Pull to refresh and try again.",
                    systemImage: "person.3.sequence"
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } else {
                Section {
                    LineupSummaryCard(
                        lineup: model.lineup,
                        comparison: model.lineupProjectionComparison,
                        isDirty: isDirty,
                        hasValidationIssue: model.starterValidationMessage != nil
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                } footer: {
                    if let note = model.lineup.projectionNote { Text(note) }
                }

                if let message = displayedValidationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Lineup issue: \(message)")
                    }
                }

                Section {
                    ForEach(model.lineup.startingSlots) { slot in
                        LineupPlayerRow(
                            player: slot.player,
                            slotLabel: slot.label,
                            actionTitle: "Replace",
                            actionIcon: "arrow.down.circle.fill",
                            isEditable: model.canChangeLineupDraft
                        ) {
                            replacementRequest = model.replacementRequest(for: slot.id)
                        }
                    }
                } header: {
                    HStack {
                        Text("Starting")
                        Spacer()
                        Text("\(model.lineup.starters.count) of \(model.lineup.requiredStarterCount)")
                            .foregroundStyle(model.lineupValidationMessage == nil ? Color.secondary : Color.orange)
                    }
                }

                Section("Bench") {
                    ForEach(model.lineup.bench) { player in
                        LineupPlayerRow(
                            player: player,
                            actionTitle: "Start",
                            actionIcon: "arrow.up.circle.fill",
                            isEditable: model.canChangeLineupDraft
                        ) {
                            if model.lineup.starters.count >= model.lineup.requiredStarterCount {
                                startRequest = model.startRequest(for: player.id)
                            } else {
                                withAnimation(.snappy) { model.toggleStarter(player.id) }
                            }
                        }
                    }
                }.id("lineup-bench")

                if model.lineup.requiredTiebreakerCount > 0 {
                    Section {
                        Picker("Bench tiebreaker", selection: tiebreakerBinding) {
                            Text("Choose a player").tag("")
                            ForEach(model.lineup.bench.filter {
                                $0.injuryStatus != .injuredReserve && !$0.isLocked
                            }) { player in
                                Text("\(player.name) · \(player.position)").tag(player.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("lineup-tiebreaker")
                        .disabled(!model.canChangeLineupDraft)
                    } header: {
                        Text("Tiebreaker")
                    } footer: {
                        Text("Your league uses a nonstarter’s score to resolve tied matchups. MFL accepts this choice but does not expose the saved tiebreaker for the app to read back.")
                    }
                }

                Section {
                    Label("Players whose NFL games have started are locked here. MFL applies your league’s final lock rules when you submit.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .playerJerseyMetadata(for: model.lineup.players.map(\.id))
        .playerSearch {
            WeekPicker(selection: weekBinding, weeks: model.availableWeeks)
                .disabled(model.isUsingCachedSession || model.availableWeeks.isEmpty)
        }
        .navigationTitle("Lineup")
        .task(id: "\(model.workspace?.storageScope ?? "none")|\(model.selectedWeek)|\(model.isUsingCachedSession)") {
            await model.loadPlayerAvailability(week: model.selectedWeek)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Lineup check and alerts", systemImage: lineupNeedsAttention ? "bell.badge" : "bell") {
                    showingLineupCheck = true
                }
                .accessibilityIdentifier("lineup-alerts-toolbar")
                .accessibilityValue("\(lineupReadiness.title). \(model.lineupAlerts.coverageTitle(week: model.lineup.week))")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isDirty {
                submitBar
            }
        }
        .refreshable { await model.refreshLineup() }
        .sheet(isPresented: $showingLineupCheck, onDismiss: {
            if let request = readinessReplacement {
                readinessReplacement = nil
                replacementRequest = request
            }
        }) {
            NavigationStack {
                Form {
                    Section {
                        LineupReadinessView(replace: { playerID in
                            showingLineupCheck = false
                            if let slot = model.lineup.startingSlots.first(where: { $0.player.id == playerID }) {
                                readinessReplacement = model.replacementRequest(for: slot.id)
                            }
                        }, reviewBench: {
                            showingLineupCheck = false
                            proxy.scrollTo("lineup-bench", anchor: .top)
                        })
                    }
                }
                .navigationTitle("Lineup check")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingLineupCheck = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $replacementRequest) { request in
            LineupReplacementPicker(request: request)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $startRequest) { request in
            LineupStartPicker(request: request)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $reviewedLineup) { review in
            LineupSubmissionReview(lineup: review.lineup)
        }
      }
    }

    private var isDirty: Bool {
        model.hasLineupChanges
    }

    private var lineupReadiness: LineupReadiness {
        LineupReadiness(lineup: model.lineup, availability: model.playerTools.availability[model.lineup.week],
                        scope: model.workspace?.storageScope)
    }

    private var lineupNeedsAttention: Bool {
        lineupReadiness.attentionCount > 0 || (model.lineupAlerts.options.enabled && !model.lineupAlerts.busy &&
            (model.lineupAlerts.permissionRequired || model.lineupAlerts.acknowledgedWeek != model.lineup.week ||
             (model.lineupAlerts.acknowledgedUntil ?? .distantPast) <= Date()))
    }

    private var displayedValidationMessage: String? {
        guard model.canEditLineup else { return nil }
        return model.lineupValidationMessage
    }

    private var weekBinding: Binding<Int> {
        Binding(
            get: { model.selectedWeek },
            set: { week in Task { await model.changeWeek(to: week) } }
        )
    }

    private var tiebreakerBinding: Binding<String> {
        Binding(
            get: { model.lineup.tiebreakerPlayerIDs.first ?? "" },
            set: { model.setTiebreaker($0) }
        )
    }

    private var submitBar: some View {
        VStack(spacing: 7) {
            if let message = model.lineupValidationMessage {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            PrimaryActionButton(
                title: "Review & submit lineup",
                systemImage: "checkmark.circle.fill",
                isBusy: model.isBusy,
                isDisabled: model.lineupValidationMessage != nil || !model.canSubmitLineup
            ) {
                reviewedLineup = LineupReviewRequest(lineup: model.lineup)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

}

private struct LineupSubmissionReview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let lineup: LineupSnapshot

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Week", value: String(lineup.week))
                    LabeledContent("Starting", value: "\(lineup.starters.count) of \(lineup.requiredStarterCount)")
                    LabeledContent("Projected total", value: lineup.projectedTotal.pointsText)
                }
                Section("Starters to submit") {
                    ForEach(lineup.startingSlots) { slot in
                        HStack(spacing: 12) {
                            PositionBadge(position: slot.label)
                            VStack(alignment: .leading, spacing: 3) {
                                PlayerNameCaption(name: slot.player.name, playerID: slot.player.id,
                                    nflTeam: slot.player.nflTeam, jerseyNumber: slot.player.jerseyNumber,
                                    position: slot.label == "FLEX" ? slot.player.position : nil)
                            }
                            Spacer(minLength: 8)
                            Text(slot.player.projectedPoints.pointsText).font(.body.monospacedDigit())
                        }.padding(.vertical, 3)
                    }
                }
                if lineup.requiredTiebreakerCount > 0 {
                    Section("Bench tiebreaker") {
                        ForEach(lineup.players.filter { lineup.tiebreakerPlayerIDs.contains($0.id) }) { Text($0.name) }
                        Text("Your tiebreaker is sent too, but MFL does not expose it for readback.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("This sends your full starting lineup to MyFantasyLeague. MFL Blitz will read it back and confirm every starter.").font(.subheadline)
                    if model.isDemo { Text("Preview only · Nothing is submitted to MFL.").foregroundStyle(.orange) }
                    if !model.lineupMatchesReview(lineup) {
                        Label("The lineup changed. Cancel and review the updated starters.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Review lineup").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isBusy) }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Submit \(lineup.starters.count) starters", systemImage: "checkmark.circle.fill",
                    isBusy: model.isBusy, isDisabled: !model.canSubmitLineup || !model.lineupMatchesReview(lineup) || model.lineupValidationMessage != nil) {
                    Task { if await model.submitLineup(reviewing: lineup) != nil { dismiss() } }
                }
                .accessibilityIdentifier("lineup-confirm-submit")
                .padding(16).background(.ultraThinMaterial)
            }
        }
        .interactiveDismissDisabled(model.isBusy)
        .presentationDetents([.large])
    }
}

private struct LineupStartPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: AppModel.LineupStartRequest

    var body: some View {
        let candidates = model.startCandidates(for: request)
        NavigationStack {
            List {
                Section {
                    Text(request.player.name).font(.headline)
                    Text("Choose a starter to move to the bench.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Replace") {
                    if candidates.isEmpty {
                        Text(model.lineup.starters.count > model.lineup.requiredStarterCount
                            ? "Your lineup has too many starters. Close this picker, tap Replace on a starter, then Move to bench."
                            : "No eligible starters can be replaced. A player may be locked, or the lineup has changed.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { candidate in
                        Button {
                            if model.startPlayer(request, replacing: candidate.starter.id) { dismiss() }
                        } label: {
                            LineupReplacementCandidateRow(player: candidate.starter,
                                detail: "\(candidate.slotLabel) → Bench",
                                actionIcon: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Replace \(candidate.starter.name), \(candidate.slotLabel), with \(request.player.name)")
                        .accessibilityHint("Moves \(candidate.starter.name) to the bench. Review and submit your lineup to save.")
                        .accessibilityIdentifier("lineup-start-replacing-\(candidate.starter.id)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Choose a starter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct LineupReplacementPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: AppModel.LineupReplacementRequest
    @State private var path: [String] = []

    var body: some View {
        let candidates = model.replacementCandidates(for: request)
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: 12) {
                        PositionBadge(position: request.slotLabel)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(request.starter.name).font(.headline)
                            Text("\(request.starter.position) · Week \(request.week)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(request.starter.projectedPoints.pointsText)
                                .font(.body.bold().monospacedDigit())
                                .accessibilityIdentifier("lineup-replacement-starter-projection")
                            Text("proj").font(.caption2).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Section {
                    Button {
                        if model.benchStarter(request) { dismiss() }
                    } label: {
                        Label("Move to bench", systemImage: "arrow.down.circle")
                    }
                    .disabled(!model.canBenchStarter(request))
                    .accessibilityLabel("Move \(request.starter.name) to bench")
                    .accessibilityHint("Removes this starter from your draft. Fill the open spot before submitting.")
                    .accessibilityIdentifier("lineup-bench-\(request.starter.id)")
                }

                if model.isLoadingLineup {
                    Section {
                        ProgressView("Updating eligible players…")
                    }
                } else if candidates.isEmpty {
                    Section {
                        Text("No eligible \(request.slotLabel) replacements")
                            .font(.headline)
                        Text(model.lineup.starters.count > model.lineup.requiredStarterCount
                            ? "Move a starter to the bench to bring your lineup back within the limit."
                            : "No unlocked players meet this slot’s league rules, or the lineup has changed. No swap was made.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    let bench = candidates.filter { !$0.isStarter }
                    let starters = candidates.filter(\.isStarter)
                    if !bench.isEmpty {
                        Section {
                            ForEach(bench) { candidateButton($0) }
                        } header: {
                            Text("Bench")
                        }
                    }
                    if !starters.isEmpty {
                        Section {
                            ForEach(starters) { candidateButton($0) }
                        } header: {
                            Text("Already starting")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Replace \(request.slotLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(for: String.self) { playerID in
                LineupVacatedSlotPicker(request: request, movingPlayerID: playerID) { dismiss() }
            }
        }
    }

    private func candidateButton(_ player: LineupPlayer) -> some View {
        let source = model.lineup.startingSlots.first { $0.id == player.id }?.label
        let needsFollowUp = model.replacementNeedsFollowUp(for: request, with: player.id)
        let detail = source.map { $0 == request.slotLabel ? "Starting · \($0)" : "\($0) → \(request.slotLabel)" }
        return Button {
            if needsFollowUp { path.append(player.id) }
            else if model.replaceStarter(request, with: player.id) { dismiss() }
        } label: {
            LineupReplacementCandidateRow(player: player, detail: detail,
                actionIcon: needsFollowUp ? "chevron.right" : player.isStarter ? "arrow.up.arrow.down.circle.fill" : "arrow.up.circle.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(player.name), \(player.position), \(player.nflTeam), \(detail ?? "Bench"), projected \(player.projectedPoints.pointsText) points\(player.injuryStatus.map { ", \($0.label)" } ?? "")")
        .accessibilityHint(needsFollowUp ? "Choose who fills the vacated position before applying this move."
            : player.isStarter ? "Swap slots with \(request.starter.name). Both players remain starters."
            : "Replace \(request.starter.name). Review and submit your lineup to save.")
        .accessibilityIdentifier("lineup-replacement-\(player.id)")
    }
}

private struct LineupVacatedSlotPicker: View {
    @Environment(AppModel.self) private var model
    let request: AppModel.LineupReplacementRequest
    let movingPlayerID: String
    let onComplete: () -> Void

    var body: some View {
        let source = model.lineup.startingSlots.first { $0.id == movingPlayerID }
        let candidates = model.replacementFollowUpCandidates(for: request, with: movingPlayerID)
        List {
            Section {
                if let source {
                    Text("\(source.player.name) → \(request.slotLabel)").font(.headline)
                        .padding(.vertical, 4)
                }
            }
            Section {
                if candidates.isEmpty {
                    Text("No eligible replacements are available, or the lineup has changed. Go back and choose another player.")
                        .foregroundStyle(.secondary)
                }
                ForEach(candidates) { player in
                    Button {
                        if model.replaceStarter(request, with: movingPlayerID, fillingVacatedSlotWith: player.id) { onComplete() }
                    } label: {
                        LineupReplacementCandidateRow(player: player,
                            detail: "\(player.isStarter ? "FLEX" : "Bench") → \(source?.label ?? "position")\n\(request.starter.name) → \(player.isStarter ? "FLEX" : "Bench")",
                            actionIcon: player.isStarter ? "arrow.up.arrow.down.circle.fill" : "arrow.up.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(player.name), \(player.position), projected \(player.projectedPoints.pointsText) points. Moves from \(player.isStarter ? "FLEX" : "bench") to \(source?.label ?? "the open position"). \(request.starter.name) moves to \(player.isStarter ? "the other FLEX slot" : "the bench").")
                    .accessibilityHint(player.isStarter ? "Rotates three starters between slots. All remain in your lineup."
                        : "Completes both moves. Review and submit your lineup to save.")
                    .accessibilityIdentifier("lineup-fill-\(player.id)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fill \(source?.label ?? "position")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { onComplete() } }
        }
    }
}

private struct LineupReplacementCandidateRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let player: LineupPlayer
    let detail: String?
    let actionIcon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    PlayerNameCaption(name: player.name, playerID: player.id, nflTeam: player.nflTeam,
                        jerseyNumber: player.jerseyNumber, position: player.position)
                        .accessibilityIdentifier("lineup-candidate-name-\(player.id)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                        Text(player.projectedPoints.pointsText)
                            .font(.body.bold().monospacedDigit()).foregroundStyle(.primary)
                        Text("proj").font(.caption2).foregroundStyle(.secondary)
                    }
                    Image(systemName: actionIcon).font(.title3).foregroundStyle(Color.blitzAction)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            PlayerAvailabilityCaption(playerID: player.id, nflTeam: player.nflTeam, week: model.lineup.week,
                fallbackInjury: player.injuryStatus, isLocked: player.isLocked)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

private struct LineupSummaryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    let lineup: LineupSnapshot
    let comparison: LineupProjectionComparison?
    let isDirty: Bool
    let hasValidationIssue: Bool

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Week \(lineup.week) projection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))
                    layout {
                        Text(lineup.projectedTotal.pointsText)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .layoutPriority(1)
                            .contentTransition(.numericText())
                            .accessibilityLabel("Week \(lineup.week) projection, \(lineup.projectedTotal.pointsText) points")
                            .accessibilityIdentifier("lineup-summary-projection")
                        if let comparison {
                            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                                Text(comparison.margin == 0 ? comparison.marginText : "\(comparison.marginText) pts")
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(marginColor(comparison.margin))
                                    .contentTransition(.numericText())
                                Text("vs \(comparison.opponentName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(comparison.accessibilityLabel)
                            .accessibilityIdentifier("lineup-projected-margin")
                        }
                    }
                }

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        lockNote.fixedSize()
                        Spacer(minLength: 0)
                        lineupStatus.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        lockNote
                        lineupStatus
                    }
                }
                .labelStyle(LineupSummaryLabelStyle())
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var lockNote: some View {
        Label(lineup.deadline.map { $0.formatted(date: .omitted, time: .shortened) }
              ?? "Locks at each kickoff", systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("lineup-lock-message")
    }

    private var lineupStatus: some View {
        Label(status.text, systemImage: status.systemImage)
            .font(.caption)
            .foregroundStyle(status.tone.foreground)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.text)
            .accessibilityValue(lineup.lastSubmitted.map {
                "Last submitted \($0.formatted(date: .omitted, time: .shortened))"
            } ?? "")
            .accessibilityIdentifier("lineup-summary-status")
    }

    private func marginColor(_ margin: Double) -> Color {
        if margin == 0 { return .secondary }
        // Darker semantic greens/oranges keep small numeric text legible on light surfaces.
        if colorScheme == .light {
            return margin > 0 ? Color(red: 0.12, green: 0.43, blue: 0.20)
                : Color(red: 0.68, green: 0.28, blue: 0.02)
        }
        return margin > 0 ? .green : .orange
    }

    private var status: (text: String, systemImage: String, tone: StatusPill.Tone) {
        if isDirty {
            return ("Unsaved changes", "pencil", .warning)
        }
        if hasValidationIssue {
            return ("Incomplete", "exclamationmark", .warning)
        }
        if lineup.lastSubmitted != nil {
            return ("Submitted", "checkmark", .positive)
        }
        return ("Current lineup", "checkmark.circle", .neutral)
    }
}

/// Avoid List's column-aligned label spacing inside the compact summary footer.
private struct LineupSummaryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon
            configuration.title
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LineupPlayerRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let player: LineupPlayer
    var slotLabel: String? = nil
    let actionTitle: String
    let actionIcon: String
    let isEditable: Bool
    let action: () -> Void

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            identityLink {
                HStack(spacing: 12) {
                    PositionBadge(position: slotLabel ?? player.position)

                    VStack(alignment: .leading, spacing: 4) {
                        PlayerNameCaption(name: player.name, playerID: player.id, nflTeam: player.nflTeam,
                            jerseyNumber: player.jerseyNumber, position: slotLabel == "FLEX" ? player.position : nil)
                        PlayerAvailabilityCaption(playerID: player.id, nflTeam: player.nflTeam, week: model.lineup.week,
                            fallbackInjury: player.injuryStatus, isLocked: player.isLocked)
                    }

                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 4)
                        projection
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
            }

            if dynamicTypeSize.isAccessibilitySize {
                HStack {
                    projection.accessibilityHidden(true)
                    Spacer()
                    actionButton
                }
            } else { actionButton }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: action) {
                Label(actionTitle, systemImage: actionIcon)
            }
            .tint(actionTitle == "Start" ? .green : .orange)
            .disabled(!actionIsAvailable)
        }
    }

    private var projection: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(player.projectedPoints.pointsText).font(.body.bold().monospacedDigit())
            Text("proj").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var actionButton: some View {
        Button(action: action) {
            if dynamicTypeSize.isAccessibilitySize {
                Label(actionTitle, systemImage: actionIcon)
                    .foregroundStyle(actionColor)
                    .frame(minHeight: BlitzMetrics.minimumTapTarget)
            } else {
                Image(systemName: actionIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(actionColor)
                    .frame(width: BlitzMetrics.minimumTapTarget, height: BlitzMetrics.minimumTapTarget)
                    .contentShape(Rectangle())
            }
        }
            .buttonStyle(.plain)
            .disabled(!actionIsAvailable)
            .accessibilityLabel("\(actionTitle) \(player.name)")
            .accessibilityHint(actionHint)
            .accessibilityIdentifier("lineup-\(actionTitle.lowercased())-\(player.id)")
    }

    private var actionIsAvailable: Bool {
        isEditable && !player.isLocked && player.injuryStatus != .injuredReserve
    }

    @ViewBuilder
    private func identityLink<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let scope = model.browseScope {
            NavigationLink(value: PlayerRoute(scope: scope, playerID: player.id, inspectedWeek: model.lineup.week,
                previewIdentity: PlayerIdentity(id: player.id, name: player.name, position: player.position, nflTeam: player.nflTeam))) {
                content()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lineup-player-\(player.id)")
            .accessibilityHint("Opens player details without changing your lineup")
        } else { content() }
    }

    private var actionColor: Color {
        guard actionIsAvailable else { return .secondary }
        return actionTitle == "Start" ? .blitzGreen : .orange
    }

    private var actionHint: String {
        if player.isLocked {
            return "This player is locked because their game has started"
        }
        if !isEditable {
            return "Lineup changes are unavailable"
        }
        if player.injuryStatus == .injuredReserve { return "Activate this player from injured reserve in My Team first" }
        if actionTitle == "Replace" {
            return slotLabel == "FLEX"
                ? "Shows eligible FLEX replacements and an option to move this player to the bench."
                : "Shows eligible \(player.position) replacements and an option to move this player to the bench."
        }
        if actionTitle == "Start", model.lineup.starters.count >= model.lineup.requiredStarterCount {
            return "Choose an eligible starter to replace. Review and submit to save the swap."
        }
        let destination = actionTitle == "Start" ? "starting lineup" : "bench"
        return "Moves this player to the \(destination). Review and submit to send the change to MFL."
    }

    private var accessibilityLabel: String {
        var value = "\(player.name), \(player.position), \(player.nflTeam)"
        if let jersey = model.playerTools.jerseyNumber(playerID: player.id, nflTeam: player.nflTeam, fallback: player.jerseyNumber) {
            value += ", number \(jersey)"
        }
        if slotLabel == "FLEX" { value += ", starting in FLEX" }
        var healthStatus = player.injuryStatus?.label
        if let availability = model.playerTools.availability[model.lineup.week], availability.scope == model.workspace?.storageScope {
            if availability.byeWeeks[player.nflTeam] == model.lineup.week { value += ", bye week" }
            else if let game = availability.games[player.nflTeam] {
                if let kickoff = game.kickoff { value += ", \(kickoff.formatted(date: .abbreviated, time: .shortened))" }
                value += ", \(game.opponentLabel)"
            }
            if let injury = availability.injuries[player.id] { healthStatus = injury.status }
        }
        if let healthStatus { value += ", injury report: \(healthStatus)" }
        if player.injuryStatus == .injuredReserve, !["IR", "INJURED RESERVE"].contains(healthStatus?.uppercased() ?? "") {
            value += ", injured reserve"
        }
        value += ", projected \(player.projectedPoints.pointsText) points"
        if player.isLocked { value += ", locked" }
        return value
    }
}

struct PositionBadge: View {
    let position: String
    var isAccessibilityHidden = true

    var body: some View {
        Text(position)
            .font(.caption2.bold())
            .foregroundStyle(Color.blitzNavy)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .frame(minWidth: 38, minHeight: 32)
            .background(Color.blitzGreen.opacity(0.9), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(isAccessibilityHidden)
    }
}
