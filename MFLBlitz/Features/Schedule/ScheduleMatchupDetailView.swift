import SwiftUI
import Observation

@MainActor
@Observable
final class ScheduleMatchupDetailModel {
    let id = UUID()
    private(set) var scores: ScoresSnapshot?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private var generation = 0

    func load(route: MatchupRoute, app: AppModel, force: Bool = false) async {
        guard !isLoading, route.scope == app.browseScope else { return }
        isLoading = true
        generation &+= 1
        let request = generation
        defer { if request == generation { isLoading = false } }
        do {
            let result = try await app.loadMatchupScores(week: route.week, refresh: force)
            guard request == generation, route.scope == app.browseScope, !Task.isCancelled else { return }
            guard result.week == route.week else {
                throw RepositoryError.server("MFL returned a different scoring week. Pull to refresh.")
            }
            scores = result
            errorMessage = nil
        } catch is CancellationError {
            // Leaving a route isn't a failed league refresh.
        } catch {
            guard request == generation, route.scope == app.browseScope, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func cancel() {
        generation &+= 1
        isLoading = false
    }

    /// Schedule IDs and live-scoring IDs are different wire identities. Match
    /// only a proven source ID or an unambiguous participant pair; never index
    /// into a week's results and accidentally open another doubleheader game.
    static func matchingGame(_ game: SeasonScheduleMatchup, in scores: ScoresSnapshot,
                             schedule: SeasonScheduleSnapshot) -> Matchup? {
        guard scores.week == game.week else { return nil }
        let ids = game.participants.map(\.franchiseID).sorted()
        guard ids.count == 2 else { return nil }
        let candidates = scores.matchups.filter { matchup in
            guard [matchup.away.id, matchup.home.id].sorted() == ids else { return false }
            return game.participants.allSatisfy { participant in
                guard let isHome = participant.isHome else { return true }
                return participant.franchiseID == (isHome ? matchup.home.id : matchup.away.id)
            }
        }
        if let sourceID = game.sourceMatchupID {
            let exact = candidates.filter { $0.id == sourceID }
            let sameSource = schedule.weeks.first { $0.week == game.week }?.matchups.filter {
                $0.sourceMatchupID == sourceID
            } ?? []
            if exact.count == 1, sameSource.count == 1 { return exact[0] }
        }
        let scheduledPairCount = schedule.weeks.first { $0.week == game.week }?.matchups.filter {
            $0.participants.map(\.franchiseID).sorted() == ids
        }.count ?? 0
        guard scheduledPairCount == 1, candidates.count == 1 else { return nil }
        return candidates[0]
    }
}

struct ScheduleMatchupDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(SeasonScheduleModel.self) private var schedule
    @Environment(\.scenePhase) private var scenePhase
    let route: MatchupRoute
    @State private var detail = ScheduleMatchupDetailModel()

    private var snapshot: SeasonScheduleSnapshot? {
        guard let value = schedule.snapshot,
              value.season == route.scope.season, value.leagueID == route.scope.leagueID else { return nil }
        return value
    }

    private var game: SeasonScheduleMatchup? { snapshot?.matchup(id: route.matchupID, week: route.week) }

    var body: some View {
        Group {
            if let snapshot, let game {
                if let scores = detail.scores,
                   let match = ScheduleMatchupDetailModel.matchingGame(game, in: scores, schedule: snapshot) {
                    MatchupDetailView(matchupID: match.id, snapshot: scores,
                                      refreshError: detail.errorMessage, isRefreshingSnapshot: detail.isLoading,
                                      refreshAction: { await refresh(force: true) })
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if app.isDemo { DemoBanner() }
                            Text(game.state.label).font(.headline).foregroundStyle(.secondary)
                            SurfaceCard {
                                VStack(spacing: 20) {
                                    ForEach(Array(game.participants.enumerated()), id: \.offset) { _, participant in
                                        participantRow(participant, game: game)
                                    }
                                }
                            }
                            if detail.isLoading {
                                ProgressView("Loading player scoring…").frame(maxWidth: .infinity)
                            } else if let error = detail.errorMessage {
                                Label(error, systemImage: "wifi.exclamationmark")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button("Retry") { Task { await refresh(force: true) } }.frame(minHeight: 44)
                            } else if game.state == .scheduled {
                                Text("Player scoring will appear when this matchup is played.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else if game.state == .unknown {
                                Text("MFL hasn’t confirmed this week’s scoring status.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                Text("Player scoring couldn’t be matched to this game. Team totals above are from the schedule.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            if !app.isDemo, let url = app.workspace?.leagueURL {
                                Link("Open league on MFL", destination: url).frame(minHeight: 44)
                            }
                        }
                        .padding(BlitzMetrics.pagePadding)
                        .readablePageWidth()
                    }
                    .pageBackground()
                    .refreshable { await refresh(force: true) }
                }
            } else if schedule.isLoading || schedule.snapshot == nil {
                VStack(spacing: 16) {
                    if let error = schedule.errorMessage {
                        ContentUnavailableView("Schedule unavailable", systemImage: "calendar.badge.exclamationmark",
                                               description: Text(error))
                        Button("Retry") { Task { await schedule.refresh() } }
                    } else { ProgressView("Loading schedule…") }
                }
            } else {
                ContentUnavailableView("Matchup changed", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("Go back to the schedule to open the latest matchup."))
            }
        }
        .navigationTitle("Week \(route.week) Matchup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { app.scopedScoreInspection = detail.id }
        .onDisappear {
            detail.cancel()
            if app.scopedScoreInspection == detail.id { app.scopedScoreInspection = nil }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, app.browseScope == route.scope else { return }
            await schedule.loadIfNeeded()
            await refresh(force: false)
            // Replaces (does not add to) the main scoreboard poller while this
            // scoped current-week detail is visible. Future weeks never poll.
            guard game?.state == .current, !app.isDemo else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(90 + Double.random(in: 0...10))) }
                catch { return }
                guard !Task.isCancelled, app.scopedScoreInspection == detail.id else { return }
                await schedule.loadIfNeeded()
                if game?.state == .completed {
                    // Read official results once at rollover before ending the
                    // current-week poller; do not leave the last live feed behind.
                    await detail.load(route: route, app: app, force: true)
                    return
                }
                guard game?.state == .current else { return }
                await detail.load(route: route, app: app)
            }
        }
    }

    private func refresh(force: Bool) async {
        guard app.browseScope == route.scope, !Task.isCancelled else { return }
        if force { await schedule.refresh() }
        guard let game, game.state == .current || game.state == .completed else { return }
        await detail.load(route: route, app: app, force: force)
    }

    @ViewBuilder
    private func participantRow(_ participant: SeasonScheduleParticipant, game: SeasonScheduleMatchup) -> some View {
        HStack(spacing: 14) {
            if let team = app.teams.first(where: { $0.id == participant.franchiseID }) {
                NavigationLink(value: TeamRoute(scope: route.scope, franchiseID: team.id, initialSection: .schedule)) {
                    HStack(spacing: 12) {
                        TeamMark(abbreviation: team.abbreviation, seed: team.accentSeed, size: 48,
                                 artworkURLs: team.artworkURLs)
                        Text(team.name).font(.headline).foregroundStyle(.primary)
                    }
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("schedule-detail-team-\(team.id)")
            } else {
                Text(participant.isExplicitBye ? "Bye" : "Team \(participant.franchiseID)")
                    .font(.headline).foregroundStyle(.secondary)
            }
            Spacer()
            if game.state != .scheduled, let score = participant.score {
                Text(NSDecimalNumber(decimal: score).doubleValue.pointsText(precision: app.scores.scorePrecision))
                    .font(.title2.bold().monospacedDigit())
            }
        }
    }
}
