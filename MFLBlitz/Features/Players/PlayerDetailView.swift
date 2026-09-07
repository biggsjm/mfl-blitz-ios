import SwiftUI

struct PlayerDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var detailModel = PlayerDetailModel()
    @State private var season = PlayerSeasonSummaryModel()
    @State private var research = PlayerResearchModel()
    @State private var rosterRequest: RosterActionRequest?
    @State private var showingBiography = false
    @State private var loadedRosterRevision: Int?
    let playerID: String
    let inspectedWeek: Int?
    let previewIdentity: PlayerIdentity?

    init(playerID: String, inspectedWeek: Int? = nil, previewIdentity: PlayerIdentity? = nil) {
        self.playerID = playerID
        self.inspectedWeek = inspectedWeek
        self.previewIdentity = previewIdentity
    }

    var body: some View {
        List {
            if model.isUsingCachedSession {
                ConnectionStatusBanner().listRowBackground(Color.clear)
            }
            if model.isDemo { DemoBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            if let message = detailModel.errorMessage {
                Section {
                    Label(message, systemImage: "wifi.exclamationmark").font(.subheadline)
                    Button("Retry player") { Task { await load(refresh: true) } }
                        .disabled(detailModel.isLoading)
                }
            }
            if let displayedIdentity {
                Section {
                    PlayerSummaryCard(player: displayedIdentity,
                        seasonTotal: season.summary?.total, weeklyAverage: season.summary?.average,
                        health: currentHealth, scorePrecision: model.scores.scorePrecision)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    if let detail {
                        ownershipRows(detail)
                    } else {
                        Text(detailModel.errorMessage == nil ? "Checking league status…" : "League status unavailable")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("player-ownership-pending")
                    }
                }
                if let error = season.errorMessage {
                    Section {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("Retry season scoring") { Task { await loadSeason(force: true) } }
                            .disabled(season.isLoading)
                    }
                } else if let issues = season.summary?.issues, !issues.isEmpty {
                    Section {
                        ForEach(issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                WatchListStatusSection()
                PlayerWeekSection(player: displayedIdentity, week: contextWeek, metrics: metrics)
                PlayerResearchSections(research: research, scorePrecision: model.scores.scorePrecision,
                    retry: { Task { await loadResearch() } },
                    loadMore: { Task { await loadResearch(more: true) } })
                Section {
                    DisclosureGroup("Player bio", isExpanded: $showingBiography) {
                        if let bio = detailModel.biography, !bio.isEmpty {
                            if let jersey = bio.jerseyNumber { LabeledContent("Jersey", value: jersey) }
                            if let birthDate = bio.birthDate { LabeledContent("Born", value: birthDateText(birthDate)) }
                            if let height = bio.height { LabeledContent("Height", value: height) }
                            if let weight = bio.weight { LabeledContent("Weight", value: weight) }
                            if let year = bio.draftYear { LabeledContent("NFL draft year", value: String(year)) }
                            if let round = bio.draftRound { LabeledContent("NFL draft round", value: String(round)) }
                        } else if detailModel.isLoadingBiography {
                            ProgressView("Loading biography…")
                        } else if detailModel.hasLoadedBiography {
                            Text("No biography provided.").foregroundStyle(.secondary)
                        }
                        if let error = detailModel.biographyErrorMessage {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            Button("Retry biography") { Task { await loadBiography(force: true) } }
                                .disabled(detailModel.isLoadingBiography)
                        }
                    }
                    .accessibilityIdentifier("player-bio")
                }
                if let issues = detail?.issues, !issues.isEmpty {
                    Section {
                        ForEach(issues) { issue in
                            Label(issue.message, systemImage: "info.circle")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    if detailModel.isLoading { ProgressView("Updating player…") }
                    if let verifiedAt = detail?.ownershipVerifiedAt {
                        Text("Ownership refreshed \(verifiedAt.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("Player information from MFL · Pull to refresh")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            } else if detailModel.isLoading {
                ProgressView("Loading player…")
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if model.isUsingCachedSession {
                ContentUnavailableView("Connect to view player", systemImage: "wifi",
                    description: Text("Details will load when your league reconnects."))
                    .listRowBackground(Color.clear)
            } else if detailModel.errorMessage == nil {
                ContentUnavailableView("Player unavailable", systemImage: "person.crop.circle",
                    description: Text("Pull to refresh this player’s information."))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(displayedIdentity?.name ?? "Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let status = ownAssignment?.status {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if status == .injuredReserve {
                            menuAction("Activate player", symbol: "arrow.up.circle", kind: .activate)
                        } else if [.rostered, .starter, .nonstarter].contains(status), irIneligibilityReason == nil {
                            menuAction("Move to IR", symbol: "cross.case", kind: .reserve)
                        }
                        Divider()
                        menuAction("Drop player…", symbol: "person.badge.minus", kind: .drop)
                    } label: {
                        Image(systemName: "ellipsis").frame(minWidth: 28, minHeight: 28)
                    }
                    .accessibilityLabel("Player actions")
                    .accessibilityIdentifier("player-actions-\(playerID)")
                    .tint(.primary)
                    .disabled(actionsUnavailable)
                }
            }
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
        .task(id: "\(model.workspace?.storageScope ?? "none")|\(playerID)|\(model.rosterRevision)|\(model.isUsingCachedSession)") { await load(refresh: false) }
        .task(id: "biography|\(readKey)|\(detail != nil)|\(showingBiography)") {
            if showingBiography, detail != nil { await loadBiography() }
        }
        .task(id: "availability|\(model.workspace?.storageScope ?? "none")|\(contextWeek)|\(model.isUsingCachedSession)") {
            await model.loadPlayerAvailability(week: contextWeek)
        }
        .task(id: "watchlist|\(model.workspace?.storageScope ?? "none")|\(model.isUsingCachedSession)") { await model.loadWatchList() }
        .task(id: "current-health|\(readKey)|\(model.currentWeek)") {
            if displayedIdentity != nil { await model.loadPlayerAvailability(week: model.currentWeek) }
        }
        .task(id: "season|\(readKey)") {
            if displayedIdentity != nil { await loadSeason() }
        }
        .task(id: "research|\(readKey)|\(contextWeek)") {
            if displayedIdentity != nil { await loadResearch() }
        }
        .refreshable {
            await load(refresh: true)
            await loadSeason(force: true)
            await loadResearch()
            await model.loadPlayerAvailability(week: model.currentWeek, refresh: true)
            if contextWeek != model.currentWeek {
                await model.loadPlayerAvailability(week: contextWeek, refresh: true)
            }
        }
        .sheet(item: $rosterRequest) { request in
            RosterActionSheet(player: detail?.identity ?? PlayerIdentity(id: playerID, name: "Player \(playerID)"), request: request)
        }
    }

    private var contextWeek: Int { inspectedWeek ?? model.workspace?.lineupWeek ?? model.currentWeek }
    private var readKey: String {
        "\(model.workspace?.storageScope ?? "none")|\(playerID)|\(displayedIdentity != nil)|\(model.isUsingCachedSession)"
    }
    private var currentHealth: PlayerHealth? {
        guard let value = model.playerTools.availability[model.currentWeek],
              value.scope == model.workspace?.storageScope else { return nil }
        return value.injuries[playerID]
    }
    private var ownAssignment: PlayerOwnershipAssignment? {
        detail?.ownership?.assignments.first { $0.team.id == model.workspace?.franchiseID }
    }
    private var irIneligibilityReason: String? {
        model.playerTools.irIneligibilityReason(playerID: playerID, week: model.currentWeek)
    }
    private var isWatched: Bool { model.playerTools.watchList?.playerIDs.contains(playerID) == true }

    private func loadSeason(force: Bool = false) async {
        guard let scope = model.workspace?.storageScope, !model.isUsingCachedSession else { return }
        await season.load(scope: scope, playerID: playerID, force: force) {
            try await model.loadPlayerSeasonSummary(playerID: playerID)
        }
    }

    private func loadBiography(force: Bool = false) async {
        guard let scope = model.workspace?.storageScope, !model.isUsingCachedSession else { return }
        await detailModel.loadBiography(scope: scope, playerID: playerID, force: force) {
            try await model.loadPlayerBiography(playerID: playerID)
        }
    }

    private func loadResearch(more: Bool = false) async {
        guard let scope = model.workspace?.storageScope, !model.isUsingCachedSession else { return }
        await research.load(scope: scope, playerID: playerID, contextWeek: contextWeek, more: more) { before in
            try await model.loadPlayerResearch(playerID: playerID, beforeWeek: before, contextWeek: contextWeek)
        }
    }

    private var detail: PlayerDetailSnapshot? {
        guard let value = detailModel.detail, value.scope == model.workspace?.storageScope,
              value.identity.id == playerID else { return nil }
        return value
    }

    private var displayedIdentity: PlayerIdentity? {
        if let detail { return detail.identity }
        guard !model.isUsingCachedSession, previewIdentity?.id == playerID else { return nil }
        return previewIdentity
    }

    private var metrics: PlayerWeekMetrics? {
        guard displayedIdentity != nil, let workspace = model.workspace else { return nil }
        let week = inspectedWeek ?? (workspace.weekIsConfirmed ? model.currentWeek : nil)
        guard let week else { return nil }
        return .matching(playerID: playerID, week: week, scores: model.scores,
            lineup: model.lineup, waivers: model.waivers, history: research.page, scope: workspace.storageScope)
    }

    @ViewBuilder
    private func ownershipRows(_ detail: PlayerDetailSnapshot) -> some View {
            if let ownership = detail.ownership, let workspace = model.workspace {
                if ownership.isFreeAgent == true {
                    Label("Free agent", systemImage: "person.crop.circle")
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(ownership.assignments) { assignment in
                    if assignment.team.id == workspace.franchiseID {
                        ownershipLabel(assignment)
                            .accessibilityIdentifier("player-owner-\(assignment.team.id)")
                    } else {
                        NavigationLink(value: TeamRoute(scope: LeagueBrowseScope(workspace: workspace),
                            franchiseID: assignment.team.id, initialSection: .roster)) {
                            ownershipLabel(assignment)
                        }
                        .accessibilityIdentifier("player-owner-\(assignment.team.id)")
                    }
                }
                if ownership.assignments.isEmpty, ownership.isFreeAgent != true {
                    Text("Ownership not provided").foregroundStyle(.secondary)
                }
                rosterActions(ownership)
            } else {
                Text("Ownership unavailable").foregroundStyle(.secondary)
            }
    }

    private func ownershipLabel(_ assignment: PlayerOwnershipAssignment) -> some View {
        HStack(spacing: 10) {
            TeamMark(abbreviation: assignment.team.abbreviation, seed: assignment.team.accentSeed,
                     size: 36, artworkURLs: assignment.team.artworkURLs)
            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.team.name).font(.subheadline.weight(.semibold))
                Text(assignment.status.label).font(.caption).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: BlitzMetrics.minimumTapTarget)
        .accessibilityElement(children: .combine)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    @ViewBuilder
    private func rosterActions(_ ownership: PlayerOwnership) -> some View {
        if let workspace = model.workspace {
            if ownAssignment == nil, ownership.isFreeAgent == true {
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

    private var actionsUnavailable: Bool {
        detail == nil || model.isUsingCachedSession || detailModel.isLoading || detailModel.errorMessage != nil || model.isBusy ||
            model.transactions.isBusy || model.pendingRosterChange != nil
    }

    private func menuAction(_ title: String, symbol: String, kind: RosterActionKind) -> some View {
        Button(role: kind == .drop ? .destructive : nil) {
            rosterRequest = .init(kind: kind, playerID: playerID)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(kind == .drop ? Color.red : Color.primary)
            }
        }
        .tint(kind == .drop ? .red : .primary)
        .accessibilityIdentifier("player-action-\(kind.rawValue)-\(playerID)")
        .accessibilityHint(kind == .drop ? "Review removing this player from your roster, not benching them" : "Review roster move")
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
        .disabled(actionsUnavailable)
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
        guard !model.isUsingCachedSession else { return }
        let rosterRevision = model.rosterRevision
        let shouldRefresh = refresh || (loadedRosterRevision != nil && loadedRosterRevision != rosterRevision)
        await detailModel.load(scope: workspace.storageScope, playerID: playerID, force: shouldRefresh) {
            try await model.loadPlayerDetail(playerID: playerID, refresh: shouldRefresh)
        }
        if !Task.isCancelled, detailModel.errorMessage == nil, detail != nil {
            loadedRosterRevision = rosterRevision
        }
    }
}
