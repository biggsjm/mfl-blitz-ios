import SwiftUI

struct PlayerDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var detailModel = PlayerDetailModel()
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
        .task(id: "\(model.workspace?.storageScope ?? "none")|\(playerID)") { await load(refresh: false) }
        .refreshable { await load(refresh: true) }
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
                if ownership.cannotAdd == true || ownership.acquisitionLocked == true {
                    Label("Adding is currently unavailable", systemImage: "lock")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
