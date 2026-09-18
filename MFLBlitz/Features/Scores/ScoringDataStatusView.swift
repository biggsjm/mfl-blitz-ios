import SwiftUI

struct ScoringDataStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let snapshot: ScoresSnapshot
    var players: [MatchupPlayer]?
    var scopeTitle: String?
    var refreshing = false
    var failed = false
    var offline = false
    var saved = false
    var preview = false

    private var viewedPlayers: [MatchupPlayer] {
        players ?? snapshot.matchups.flatMap { $0.away.players + $0.home.players }
    }

    private var hasLiveGames: Bool {
        let season = model.workspace?.season ?? 0
        return (players == nil && snapshot.isLive) || viewedPlayers.contains { player in
            MatchupGameInfo(player: player, availability: model.playerTools.availability[snapshot.week],
                scope: model.workspace?.storageScope, week: snapshot.week, scoringGames: model.scoringGames[snapshot.week],
                nflGame: model.nflStats.feed(season: season, week: snapshot.week)?.game(team: player.nflTeam)).isLive
        }
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                List {
                    Section {
                        row("MFL scores", id: "mfl", status: .mfl(snapshot: snapshot,
                            live: hasLiveGames,
                            refreshing: refreshing, failed: failed, offline: offline, saved: saved,
                            preview: preview, now: timeline.date), now: timeline.date)
                        row("NFL player stats", id: "nfl", status: model.nflDataStatus(players: viewedPlayers,
                            snapshot: snapshot, now: timeline.date), now: timeline.date)
                    } header: {
                        Text(scopeTitle ?? "Week \(snapshot.week)")
                    } footer: {
                        Text("Status for the games shown.")
                    }
                    Section("This iPhone") {
                        let sync = model.matchupActivity.backgroundSync
                        row("Background updates", id: "background", status: preview
                            ? .init(state: .preview, detail: "Background updates stay off in preview.")
                            : .background(enabled: model.matchupActivity.enabled, configured: sync.canRequestPush,
                                tracking: sync.isTracking, registered: sync.isRegistered,
                                attention: sync.connectionNeedsAttention, expiresAt: sync.expiresAt,
                                checkedAt: sync.connectedAt, now: timeline.date), now: timeline.date)
                        if model.lineupAlerts.options.enabled {
                            let alerts = model.lineupAlerts
                            row("Lineup alerts", id: "alerts", status: .alerts(
                                permissionKnown: alerts.authorizationStatus != nil, permissionRequired: alerts.permissionRequired,
                                busy: alerts.busy, week: model.currentWeek, acknowledgedWeek: alerts.acknowledgedWeek,
                                expiresAt: alerts.acknowledgedUntil, now: timeline.date), now: timeline.date)
                        }
                    }
                    Section {
                        NavigationLink("About projections") { ProjectionExplanationView() }
                            .accessibilityIdentifier("about-projections")
                    }
                }
            }
            .navigationTitle("Data status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ title: String, id: String, status: ScoringDataStatus, now: Date) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(status.detail).font(.subheadline)
                if let checked = status.checkedAt {
                    Text("Last received \(ScoreFreshness.age(checked, now: now))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(title)
                    Spacer(minLength: 12)
                    badge(status)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                    badge(status)
                }
            }
            .padding(.vertical, 2)
            .foregroundStyle(.primary)
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("data-status-\(id)")
    }

    private func badge(_ status: ScoringDataStatus) -> some View {
        HStack(spacing: 5) {
            Image(systemName: status.state.symbol).foregroundStyle(status.state.color).accessibilityHidden(true)
            Text(status.state.rawValue)
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension ScoringDataStatus.State {
    var color: Color {
        switch self {
        case .updating, .connected, .current: ScoringStyle.positive
        case .delayed, .attention: .orange
        case .unavailable: .red
        default: .secondary
        }
    }
}

private struct ProjectionExplanationView: View {
    var body: some View {
        List {
            Section("Pregame projection") {
                Text("An estimate made before the game. It stays the same after kickoff.")
            }
            Section("Live estimate") {
                Text("Points scored plus each starter’s pregame projection for their remaining game time.")
                Text("It assumes a steady scoring pace. Injuries and game situation aren’t included.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About projections")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension AppModel {
    func nflDataStatus(players: [MatchupPlayer], snapshot: ScoresSnapshot, now: Date) -> ScoringDataStatus {
        let season = workspace?.season ?? 0
        return .nfl(players: players, week: snapshot.week,
            feed: nflStats.feed(season: season, week: snapshot.week), scoringGames: scoringGames[snapshot.week],
            availability: playerTools.availability[snapshot.week], scope: workspace?.storageScope, mflCheckedAt: snapshot.checkedAt,
            configured: usesNFLStats && nflStats.isConfigured,
            failures: nflStats.failureCount(season: season, week: snapshot.week),
            loading: nflStats.loading(season: season, week: snapshot.week), preview: isDemo, now: now)
    }
}
