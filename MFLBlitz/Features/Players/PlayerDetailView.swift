import SwiftUI

struct PlayerDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var detailModel = PlayerDetailModel()
    @State private var research = PlayerResearchModel()
    @State private var rosterRequest: RosterActionRequest?
    @State private var showingResearch = false
    let playerID: String
    let inspectedWeek: Int?

    init(playerID: String, inspectedWeek: Int? = nil) {
        self.playerID = playerID
        self.inspectedWeek = inspectedWeek
    }

    var body: some View {
        List {
            if model.isDemo { DemoBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            if let message = detailModel.errorMessage {
                Section {
                    Label(message, systemImage: "wifi.exclamationmark").font(.subheadline)
                    Button("Retry player") { Task { await load(refresh: true) } }
                        .disabled(detailModel.isLoading)
                }
            }
            if let detail {
                Section {
                    PlayerIdentityView(player: detail.identity)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("player-detail-\(playerID)")
                }
                ownershipSection(detail)
                WatchListStatusSection()
                PlayerAvailabilitySection(player: detail.identity, week: contextWeek)
                if let metrics {
                    Section("Week \(metrics.week)") {
                        if let points = metrics.points {
                            LabeledContent("Fantasy points", value: points.pointsText(precision: model.scores.scorePrecision))
                        }
                        if let projection = metrics.projection {
                            LabeledContent("Projection", value: projection.pointsText)
                        }
                        if let statLine = metrics.statLine {
                            Text(statLine).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("Your league’s scoring").font(.caption).foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
                if showingResearch {
                    PlayerResearchSections(research: research,
                        retry: { Task { await loadResearch() } },
                        loadMore: { Task { await loadResearch(more: true) } })
                } else {
                    Section {
                        Button("View scoring history", systemImage: "chart.bar") { showingResearch = true }
                            .accessibilityIdentifier("player-load-history")
                    }
                }
                if let bio = detail.bio, !bio.isEmpty {
                    Section("Bio") {
                        if let jersey = bio.jerseyNumber { LabeledContent("Jersey", value: jersey) }
                        if let birthDate = bio.birthDate { LabeledContent("Born", value: birthDateText(birthDate)) }
                        if let height = bio.height { LabeledContent("Height", value: height) }
                        if let weight = bio.weight { LabeledContent("Weight", value: weight) }
                        if let year = bio.draftYear { LabeledContent("NFL draft year", value: String(year)) }
                        if let round = bio.draftRound { LabeledContent("NFL draft round", value: String(round)) }
                    }
                }
                if !detail.issues.isEmpty {
                    Section {
                        ForEach(detail.issues) { issue in
                            Label(issue.message, systemImage: "info.circle")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    if detailModel.isLoading { ProgressView("Updating player…") }
                    if let verifiedAt = detail.ownershipVerifiedAt {
                        Text("Ownership refreshed \(verifiedAt.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("Player information from MFL · Pull to refresh")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            } else if detailModel.isLoading {
                ProgressView("Loading player…")
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if detailModel.errorMessage == nil {
                ContentUnavailableView("Player unavailable", systemImage: "person.crop.circle",
                    description: Text("Pull to refresh this player’s information."))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(detail?.identity.name ?? "Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.setWatched(playerID: playerID, isWatched: !isWatched) }
                } label: { Image(systemName: isWatched ? "star.fill" : "star") }
                .accessibilityLabel(isWatched ? "Remove from watchlist" : "Add to watchlist")
                .accessibilityIdentifier("player-watch-\(playerID)")
                .disabled(detail == nil || model.playerTools.watchList == nil || model.playerTools.isLoadingWatchList ||
                    model.playerTools.isChangingWatchList || model.playerTools.unconfirmedWatch != nil)
            }
        }
        .task(id: "\(model.workspace?.storageScope ?? "none")|\(playerID)|\(model.rosterRevision)") { await load(refresh: detailModel.detail != nil) }
        .task(id: "availability|\(model.workspace?.storageScope ?? "none")|\(contextWeek)") {
            await model.loadPlayerAvailability(week: contextWeek)
        }
        .task(id: "watchlist|\(model.workspace?.storageScope ?? "none")") { await model.loadWatchList() }
        .task(id: "ir|\(model.workspace?.storageScope ?? "none")|\(model.currentWeek)|\(isOwnedPlayer)") {
            if isOwnedPlayer { await model.loadPlayerAvailability(week: model.currentWeek) }
        }
        .task(id: "research|\(model.workspace?.storageScope ?? "none")|\(playerID)|\(contextWeek)|\(showingResearch)") {
            if showingResearch { await loadResearch() }
        }
        .refreshable {
            await load(refresh: true)
            if isOwnedPlayer { await model.loadPlayerAvailability(week: model.currentWeek, refresh: true) }
        }
        .sheet(item: $rosterRequest) { request in
            RosterActionSheet(player: detail?.identity ?? PlayerIdentity(id: playerID, name: "Player \(playerID)"), request: request)
        }
    }

    private var contextWeek: Int { inspectedWeek ?? model.workspace?.lineupWeek ?? model.currentWeek }
    private var isOwnedPlayer: Bool {
        detail?.ownership?.assignments.contains(where: { $0.team.id == model.workspace?.franchiseID }) == true
    }
    private var irIneligibilityReason: String? {
        model.playerTools.irIneligibilityReason(playerID: playerID, week: model.currentWeek)
    }
    private var isWatched: Bool { model.playerTools.watchList?.playerIDs.contains(playerID) == true }

    private func loadResearch(more: Bool = false) async {
        guard let scope = model.workspace?.storageScope else { return }
        await research.load(scope: scope, playerID: playerID, contextWeek: contextWeek, more: more) { before in
            try await model.loadPlayerResearch(playerID: playerID, beforeWeek: before, contextWeek: contextWeek)
        }
    }

    private var detail: PlayerDetailSnapshot? {
        guard let value = detailModel.detail, value.scope == model.workspace?.storageScope,
              value.identity.id == playerID else { return nil }
        return value
    }

    private var metrics: PlayerWeekMetrics? {
        guard detail != nil, let workspace = model.workspace else { return nil }
        let week = inspectedWeek ?? (workspace.weekIsConfirmed ? model.currentWeek : nil)
        guard let week else { return nil }
        return .matching(playerID: playerID, week: week, scores: model.scores,
            lineup: model.lineup, waivers: model.waivers)
    }

    @ViewBuilder
    private func ownershipSection(_ detail: PlayerDetailSnapshot) -> some View {
        Section {
            if let ownership = detail.ownership, let workspace = model.workspace {
                if ownership.isFreeAgent == true {
                    Label("Free agent in your player pool", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(ownership.assignments) { assignment in
                    NavigationLink(value: TeamRoute(scope: LeagueBrowseScope(workspace: workspace),
                        franchiseID: assignment.team.id, initialSection: .roster)) {
                        HStack(spacing: 12) {
                            TeamMark(abbreviation: assignment.team.abbreviation, seed: assignment.team.accentSeed,
                                size: 40, artworkURLs: assignment.team.artworkURLs)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(assignment.team.name).font(.body.weight(.semibold))
                                Text(assignment.status.label).font(.caption).foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: BlitzMetrics.minimumTapTarget)
                    }
                    .accessibilityIdentifier("player-owner-\(assignment.team.id)")
                }
                if ownership.assignments.isEmpty, ownership.isFreeAgent != true {
                    Text("Ownership not provided").foregroundStyle(.secondary)
                }
                rosterActions(ownership)
            } else {
                Text("Ownership unavailable").foregroundStyle(.secondary)
            }
        } header: {
            Text("Current league status")
                .textCase(nil)
                .accessibilityIdentifier("player-ownership-heading")
        } footer: {
            Text(model.workspace?.leagueName ?? "Ownership is specific to your league.")
        }
    }

    @ViewBuilder
    private func rosterActions(_ ownership: PlayerOwnership) -> some View {
        if let workspace = model.workspace {
            if let own = ownership.assignments.first(where: { $0.team.id == workspace.franchiseID }) {
                VStack(alignment: .leading, spacing: 8) {
                    let layout = own.status == .injuredReserve && dynamicTypeSize >= .xxLarge
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(spacing: 12))
                    layout { ownedPlayerButtons(own.status) }
                }
                .accessibilityElement(children: .contain)
                .listRowSeparator(.hidden, edges: .top)
            } else if ownership.isFreeAgent == true {
                VStack(alignment: .leading, spacing: 8) {
                    rosterActionButton("Add player", symbol: "person.badge.plus", kind: .add)
                        .disabled(!ownership.allowsImmediateAdd(for: workspace.franchiseID))
                        .accessibilityHint(ownership.acquisitionRestriction ?? "Review adding this player")
                    if let reason = ownership.acquisitionRestriction {
                        Label(reason, systemImage: "lock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .contain)
                .listRowSeparator(.hidden, edges: .top)
            }
        }
    }

    @ViewBuilder
    private func ownedPlayerButtons(_ status: PlayerLineupAssignment) -> some View {
        if status == .injuredReserve {
            rosterActionButton("Activate", symbol: "arrow.up.circle", kind: .activate)
        } else if [.rostered, .starter, .nonstarter].contains(status), irIneligibilityReason == nil {
            rosterActionButton("Move to IR", symbol: "cross.case", kind: .reserve)
                .accessibilityHint("Review a move to injured reserve")
        }
        rosterActionButton("Drop", symbol: "person.badge.minus", kind: .drop)
    }

    private func rosterActionButton(_ title: String, symbol: String, kind: RosterActionKind) -> some View {
        Button(role: kind == .drop ? .destructive : nil) {
            rosterRequest = .init(kind: kind, playerID: playerID)
        } label: {
            if kind != .activate {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(kind == .drop ? Color.red : Color.primary)
                    .frame(width: 32, height: 32)
            } else {
                Label(title, systemImage: symbol)
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 28)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(kind != .activate ? .circle : .capsule)
        .controlSize(kind != .activate ? .regular : .large)
        .frame(width: kind != .activate ? 48 : nil,
               height: kind != .activate ? 48 : nil)
        .frame(minHeight: BlitzMetrics.minimumTapTarget)
        .tint(kind == .drop ? .red : .primary)
        .accessibilityLabel("\(title)\(kind == .drop ? " player" : ""), \(detail?.identity.name ?? "player")")
        .accessibilityIdentifier("player-action-\(kind.rawValue)-\(playerID)")
        .disabled(detailModel.isLoading || detailModel.errorMessage != nil || model.isBusy ||
            model.transactions.isBusy || model.pendingRosterChange != nil)
    }

    private func birthDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func load(refresh: Bool) async {
        guard let workspace = model.workspace else { detailModel.invalidate(); return }
        await detailModel.load(scope: workspace.storageScope, playerID: playerID, force: refresh) {
            try await model.loadPlayerDetail(playerID: playerID, refresh: refresh)
        }
    }
}
