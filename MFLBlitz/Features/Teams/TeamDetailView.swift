import SwiftUI

struct TeamDetailView<ScheduleContent: View>: View {
    @Environment(AppModel.self) private var model
    @State private var detailModel = TeamDetailModel()
    @State private var section: TeamDetailSection
    let franchiseID: String
    private let scheduleContent: (String) -> ScheduleContent

    init(franchiseID: String, initialSection: TeamDetailSection = .roster,
         @ViewBuilder scheduleContent: @escaping (String) -> ScheduleContent) {
        self.franchiseID = franchiseID
        _section = State(initialValue: initialSection)
        self.scheduleContent = scheduleContent
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            if isOwnTeam {
                transactionsLink
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            if let message = detailModel.headerErrorMessage {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            Picker("Team section", selection: $section) {
                ForEach(TeamDetailSection.allCases.filter { isOwnTeam || $0 != .watchlist }) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("team-section-picker")

            if section == .roster {
                rosterContent
                    .task(id: rosterKey) { await loadRoster(refresh: false) }
            } else if section == .watchlist && isOwnTeam {
                WatchListView()
            } else {
                scheduleContent(franchiseID)
            }
        }
        .pageBackground()
        .navigationTitle(isOwnTeam ? "My Team" : team.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(headerKey)|availability|\(assignmentWeek ?? model.currentWeek)") {
            await model.loadPlayerAvailability(week: assignmentWeek ?? model.currentWeek)
        }
        .task(id: headerKey) {
            guard let workspace = model.workspace else { detailModel.invalidate(); return }
            await detailModel.loadHeader(scope: workspace.storageScope, franchiseID: franchiseID) {
                try await model.loadTeams(refresh: false)
            }
        }
    }

    private var isOwnTeam: Bool { model.workspace?.franchiseID == franchiseID }
    private var headerKey: String { "\(model.workspace?.storageScope ?? "none")|\(franchiseID)" }
    private var rosterKey: String { "\(headerKey)|\(assignmentWeek.map(String.init) ?? "none")|\(model.rosterRevision)" }
    private var assignmentWeek: Int? {
        guard let workspace = model.workspace else { return nil }
        return workspace.lineupWeek ?? (workspace.weekIsConfirmed ? model.currentWeek : nil)
    }
    private var standing: StandingRow? { model.standings.first { $0.id == franchiseID } }
    private var team: TeamSummary {
        if let summary = detailModel.summary, summary.id == franchiseID,
           detailModel.summaryScope == model.workspace?.storageScope { return summary }
        if let summary = model.teams.first(where: { $0.id == franchiseID }) { return summary }
        if let standing {
            return TeamSummary(id: standing.id, name: standing.name, abbreviation: standing.abbreviation,
                ownerName: standing.ownerName, artworkURLs: standing.artworkURLs, accentSeed: standing.accentSeed)
        }
        return TeamSummary(id: franchiseID,
            name: isOwnTeam ? (model.workspace?.franchiseName ?? "My Team") : "Team \(franchiseID)",
            abbreviation: String(franchiseID.suffix(3)))
    }

    private var header: some View {
        HStack(spacing: 14) {
            TeamMark(abbreviation: team.abbreviation, seed: team.accentSeed, size: 52, artworkURLs: team.artworkURLs)
            VStack(alignment: .leading, spacing: 4) {
                Text(team.name).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                if let owner = team.ownerName {
                    Text(owner).font(.subheadline).foregroundStyle(.secondary)
                }
                if let standing {
                    Text(standing.ties > 0
                         ? "\(standing.wins)–\(standing.losses)–\(standing.ties) · \(standing.division)"
                         : "\(standing.wins)–\(standing.losses) · \(standing.division)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: BlitzMetrics.maxReadableWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("team-header-\(franchiseID)")
    }

    private var transactionsLink: some View {
        NavigationLink(value: model.browseScope.map { TeamToolsRoute(scope: $0, destination: .transactions) }) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.swap").font(.title3).foregroundStyle(Color.blitzNavy)
                    .frame(width: 42, height: 42)
                    .background(Color.blitzGreen, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transactions").font(.headline).foregroundStyle(.primary)
                    Text("Waivers, trades & activity").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if model.transactions.needsAttentionCount > 0 {
                    Text("\(model.transactions.needsAttentionCount)")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.red, in: Capsule())
                        .accessibilityLabel("\(model.transactions.needsAttentionCount) trade items need attention")
                }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: BlitzMetrics.maxReadableWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("my-team-transactions")
    }

    private var rosterContent: some View {
        List {
            if isOwnTeam {
                PendingRosterChangeSection()
                Section {
                    NavigationLink("Manage roster", value: model.browseScope.map { TeamToolsRoute(scope: $0, destination: .rosterMoves) })
                }
            }
            if model.isDemo { DemoBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            if let message = detailModel.errorMessage {
                Section {
                    Label(message, systemImage: "wifi.exclamationmark").font(.subheadline)
                    Button("Retry roster") { Task { await loadRoster(refresh: true) } }
                        .disabled(detailModel.isLoading)
                }
            }
            if let roster = detailModel.roster, roster.scope == model.workspace?.storageScope,
               roster.team.id == franchiseID {
                Section {
                    if let week = roster.lineupWeek {
                        Text("Current roster · Week \(week) assignments").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Current roster").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(roster.issues) { issue in
                        Label(issue.message, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if roster.players.isEmpty {
                    ContentUnavailableView("No rostered players", systemImage: "person.3",
                        description: Text("MFL returned an empty roster for this team."))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(TeamRosterGroup.allCases) { group in
                        let players = roster.players(in: group)
                        if !players.isEmpty {
                            Section("\(group.rawValue) · \(players.count)") {
                                ForEach(players) { player in rosterRow(player) }
                            }
                        }
                    }
                }
                Section {
                    if detailModel.isLoading { ProgressView("Updating roster…") }
                    if let date = roster.rosterVerifiedAt {
                        Text("Roster refreshed \(date.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("Roster from MFL · Pull to refresh")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            } else if detailModel.isLoading {
                ProgressView("Loading roster…").frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if detailModel.errorMessage == nil {
                ContentUnavailableView("Roster unavailable", systemImage: "person.3",
                    description: Text("Pull to refresh this team's roster."))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadRoster(refresh: true) }
        .accessibilityIdentifier("team-roster")
        .task(id: headerKey) { if isOwnTeam { await model.loadPendingRosterChange() } }
    }

    @ViewBuilder
    private func rosterRow(_ player: RosterPlayerSummary) -> some View {
        if let workspace = model.workspace {
            NavigationLink(value: PlayerRoute(scope: LeagueBrowseScope(workspace: workspace),
                playerID: player.id, inspectedWeek: assignmentWeek)) {
                VStack(alignment: .leading, spacing: 6) {
                    PlayerIdentityView(player: player.identity, subtitle: contractSummary(player))
                    PlayerAvailabilityCaption(playerID: player.id, nflTeam: player.identity.nflTeam ?? "",
                        week: assignmentWeek ?? model.currentWeek)
                }
            }
            .accessibilityIdentifier("roster-player-\(player.id)")
        } else {
            PlayerIdentityView(player: player.identity, subtitle: contractSummary(player))
        }
    }

    private func contractSummary(_ player: RosterPlayerSummary) -> String? {
        var parts: [String] = []
        if case .unknown = player.membership { parts.append("Roster status unavailable") }
        else if case .unknown = player.lineupAssignment { parts.append("Lineup status unavailable") }
        if let salary = player.salary { parts.append("Salary \(salary.formatted())") }
        if let year = player.contractYear { parts.append("Contract year \(year)") }
        if let status = player.contractStatus { parts.append(status) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func loadRoster(refresh: Bool) async {
        guard let workspace = model.workspace else { detailModel.invalidate(); return }
        let week = assignmentWeek
        await detailModel.loadRoster(scope: workspace.storageScope, franchiseID: franchiseID,
            lineupWeek: week, force: refresh) {
            try await model.loadTeamRoster(franchiseID: franchiseID, lineupWeek: week, refresh: refresh)
        }
    }
}
