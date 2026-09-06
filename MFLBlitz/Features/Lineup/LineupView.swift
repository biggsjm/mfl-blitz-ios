import SwiftUI

struct LineupView: View {
    @Environment(AppModel.self) private var model
    @State private var submittedStarterIDs: Set<String> = []
    @State private var submittedTiebreakerIDs: [String] = []
    @State private var hasSubmissionBaseline = false
    @State private var showingSubmitConfirmation = false

    var body: some View {
        List {
            if model.isDemo {
                DemoBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } else if !model.canSubmitChanges {
                LiveWriteSafetyBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if model.lineup.players.isEmpty {
                EmptyState(
                    title: "Lineup unavailable",
                    message: "MFL didn’t return a roster for Week \(model.lineup.week). Pull to refresh and try again.",
                    systemImage: "person.3.sequence"
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } else {
                Section {
                    LineupSummaryCard(
                        lineup: model.lineup,
                        isDirty: isDirty,
                        hasValidationIssue: model.lineupValidationMessage != nil
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
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
                    ForEach(model.lineup.starters) { player in
                        LineupPlayerRow(
                            player: player,
                            actionTitle: "Bench",
                            actionIcon: "arrow.down.circle",
                            isEditable: model.canSubmitChanges
                        ) {
                            withAnimation(.snappy) { model.toggleStarter(player.id) }
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
                            actionIcon: "arrow.up.circle",
                            isEditable: model.canSubmitChanges
                        ) {
                            withAnimation(.snappy) { model.toggleStarter(player.id) }
                        }
                    }
                }

                if model.lineup.requiredTiebreakerCount > 0 {
                    Section {
                        Picker("Bench tiebreaker", selection: tiebreakerBinding) {
                            Text("Choose a player").tag("")
                            ForEach(model.lineup.bench.filter { $0.injuryStatus != .injuredReserve }) { player in
                                Text("\(player.name) · \(player.position)").tag(player.id)
                            }
                        }
                        .disabled(!model.canSubmitChanges)
                    } header: {
                        Text("Tiebreaker")
                    } footer: {
                        Text("Your league uses a nonstarter’s score to resolve tied matchups.")
                    }
                }

                Section {
                    Label("Players lock individually at their NFL kickoff. Locked players stay visible but can’t be moved.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Lineup")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                WeekPicker(selection: weekBinding, range: 1...18)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isDirty {
                submitBar
            }
        }
        .refreshable { await model.refreshAll() }
        .confirmationDialog(
            "Submit Week \(model.lineup.week) lineup?",
            isPresented: $showingSubmitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Submit \(model.lineup.starters.count) starters") {
                Task {
                    if let receipt = await model.submitLineup(), receipt.week == model.lineup.week {
                        submittedStarterIDs = receipt.starterIDs
                        submittedTiebreakerIDs = receipt.tiebreakerPlayerIDs
                        hasSubmissionBaseline = true
                    }
                }
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("This sends your full starting lineup to MyFantasyLeague. Projected total: \(model.lineup.projectedTotal.pointsText) points.")
        }
        .onAppear {
            synchronizeSubmissionBaseline()
        }
        .onChange(of: model.lineupRevision) { _, _ in
            synchronizeSubmissionBaseline()
        }
    }

    private var isDirty: Bool {
        hasSubmissionBaseline
            && (submittedStarterIDs != Set(model.lineup.starters.map(\.id))
            || submittedTiebreakerIDs != model.lineup.tiebreakerPlayerIDs
            )
    }

    private var displayedValidationMessage: String? {
        guard let validationMessage = model.lineupValidationMessage else { return nil }
        guard model.canSubmitChanges else {
            return "MFL reports an incomplete Week \(model.lineup.week) lineup."
        }
        return validationMessage
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
                isDisabled: model.lineupValidationMessage != nil || !model.canSubmitChanges
            ) {
                showingSubmitConfirmation = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func synchronizeSubmissionBaseline() {
        submittedStarterIDs = Set(model.lineup.starters.map(\.id))
        submittedTiebreakerIDs = model.lineup.tiebreakerPlayerIDs
        hasSubmissionBaseline = true
    }
}

private struct LineupSummaryCard: View {
    let lineup: LineupSnapshot
    let isDirty: Bool
    let hasValidationIssue: Bool

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Week \(lineup.week) projection")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(lineup.projectedTotal.pointsText)
                            .font(.system(.largeTitle, design: .rounded, weight: .black))
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    StatusPill(
                        text: status.text,
                        systemImage: status.systemImage,
                        tone: status.tone
                    )
                }

                Divider()

                HStack {
                    if let deadline = lineup.deadline {
                        Label(deadline.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    } else {
                        Label("Locks at each kickoff", systemImage: "clock")
                    }
                    Spacer()
                    if let submitted = lineup.lastSubmitted {
                        Label(submitted.formatted(date: .omitted, time: .shortened), systemImage: "checkmark.circle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
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

private struct LineupPlayerRow: View {
    let player: LineupPlayer
    let actionTitle: String
    let actionIcon: String
    let isEditable: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PositionBadge(position: player.position)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(player.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if let injury = player.injuryStatus {
                        Text(injury.rawValue)
                            .font(.caption2.bold())
                            .foregroundStyle(injury == .questionable ? Color.orange : Color.red)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background((injury == .questionable ? Color.orange : Color.red).opacity(0.12), in: Capsule())
                            .accessibilityLabel(injury.label)
                    }
                    if player.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Locked")
                    }
                }
                Text(playerMetadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(player.projectedPoints.pointsText)
                    .font(.body.bold().monospacedDigit())
                Text("proj")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Menu {
                Button(actionTitle, systemImage: actionIcon, action: action)
                    .disabled(player.isLocked)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: BlitzMetrics.minimumTapTarget, height: BlitzMetrics.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(player.name)")
            .disabled(!isEditable)
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: action) {
                Label(actionTitle, systemImage: actionIcon)
            }
            .tint(actionTitle == "Start" ? .green : .orange)
            .disabled(player.isLocked || !isEditable)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityActions {
            if isEditable, !player.isLocked {
                Button(actionTitle, action: action)
            }
        }
    }

    private var playerMetadata: String {
        guard !player.opponent.isEmpty, player.opponent != "—" else {
            return player.nflTeam
        }
        return "\(player.nflTeam) · \(player.opponent) · \(player.gameTime.formatted(date: .omitted, time: .shortened))"
    }

    private var accessibilityLabel: String {
        var value = "\(player.name), \(player.position), \(player.nflTeam)"
        if !player.opponent.isEmpty, player.opponent != "—" { value += ", \(player.opponent)" }
        value += ", projected \(player.projectedPoints.pointsText) points"
        if let injury = player.injuryStatus { value += ", \(injury.label)" }
        if player.isLocked { value += ", locked" }
        return value
    }
}

struct PositionBadge: View {
    let position: String

    var body: some View {
        Text(position)
            .font(.caption2.bold())
            .foregroundStyle(Color.blitzNavy)
            .frame(width: 38, height: 32)
            .background(Color.blitzGreen.opacity(0.9), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}
