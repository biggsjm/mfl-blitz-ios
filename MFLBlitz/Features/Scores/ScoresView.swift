import SwiftUI

struct ScoresView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let columns = [GridItem(.adaptive(minimum: 330), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ConnectionStatusBanner().padding(.horizontal, BlitzMetrics.pagePadding)
                if model.isDemo { DemoBanner() }
                if model.workspace?.weekIsConfirmed == false {
                    Label("MFL’s current week couldn’t be confirmed. Choose a week to continue.", systemImage: "calendar.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(.orange)
                        .padding(.horizontal, BlitzMetrics.pagePadding)
                }
                if model.selectedWeek != model.currentWeek && !model.isDemo,
                   model.availableWeeks.contains(model.currentWeek) {
                    Button("Go to current week · \(model.currentWeek)") {
                        Task { await model.changeWeek(to: model.currentWeek, followingCurrent: true) }
                    }
                    .font(.subheadline)
                }
                if model.configuredWeekRange == nil {
                    Text("League week range unavailable. Only known weeks are shown.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, BlitzMetrics.pagePadding)
                }

                ScoreFreshnessLabel(snapshot: model.scores, refreshing: model.isLoadingScores,
                    failed: model.scoreRefreshError != nil, offline: model.scoresOffline,
                    saved: model.isUsingCachedSession || model.cachedScoresDate != nil, preview: model.isDemo)
                    .padding(.horizontal, BlitzMetrics.pagePadding)

                if model.scores.matchups.isEmpty {
                    if model.isLoadingScores {
                        ProgressView("Loading Week \(model.selectedWeek) scores…")
                            .padding(.top, 44)
                    } else if model.scores.lastUpdated == .distantPast {
                        ContentUnavailableView {
                            Label("Scores unavailable", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                        } description: {
                            Text("MFL scores couldn’t be loaded. Pull to refresh and try again.")
                        }
                        .padding(.top, 44)
                        .padding(.horizontal, BlitzMetrics.pagePadding)
                    } else {
                        ContentUnavailableView {
                            Label("Scores start soon", systemImage: "calendar.badge.clock")
                        } description: {
                            Text("MFL live scoring isn’t available until the season starts. You can still check your roster, standings, waivers, and league board.")
                        }
                        .padding(.top, 44)
                        .padding(.horizontal, BlitzMetrics.pagePadding)
                    }
                    seasonScheduleLink
                        .padding(.horizontal, BlitzMetrics.pagePadding)
                } else {
                    if let featured = model.scores.featuredMatchup, let scope = model.browseScope {
                        NavigationLink(value: LiveMatchupRoute(scope: scope, week: model.scores.week, matchupID: featured.id)) {
                            ScoringMatchupHero(matchup: featured, snapshot: model.scores,
                                failed: model.scoreRefreshError != nil,
                                saved: model.isUsingCachedSession || model.cachedScoresDate != nil, featured: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("matchup-\(featured.id)")
                        .accessibilityHint("Opens live player scoring for this matchup")
                            .padding(.horizontal, BlitzMetrics.pagePadding)
                    } else if model.scores.featuredMatchup == nil {
                        SurfaceCard {
                            Label("No matchup listed for your team in Week \(model.scores.week)", systemImage: "calendar")
                                .font(.subheadline)
                        }
                        .padding(.horizontal, BlitzMetrics.pagePadding)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text("Around the league").font(.headline).fixedSize()
                                Spacer(minLength: 12)
                                seasonScheduleLink.fixedSize()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Around the league").font(.headline)
                                seasonScheduleLink
                            }
                        }
                        .padding(.horizontal, BlitzMetrics.pagePadding)

                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(model.scores.matchups.filter {
                                $0.id != model.scores.featuredMatchup?.id
                            }) { matchup in
                                NavigationLink(value: model.browseScope.map {
                                    LiveMatchupRoute(scope: $0, week: model.scores.week, matchupID: matchup.id)
                                }) {
                                    MatchupCard(
                                        matchup: matchup,
                                        snapshot: model.scores
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("matchup-\(matchup.id)")
                                .accessibilityHint("Opens live player scoring for this matchup")
                            }
                        }
                        .padding(.horizontal, BlitzMetrics.pagePadding)
                    }
                    RecentScoringChanges().padding(.horizontal, BlitzMetrics.pagePadding)
                }
            }
            .padding(.bottom, 24)
            .readablePageWidth()
        }
        .pageBackground()
        .playerSearch {
            WeekPicker(selection: weekBinding, weeks: model.availableWeeks)
                .disabled(model.isUsingCachedSession || model.availableWeeks.isEmpty)
        }
        .navigationTitle(model.workspace?.leagueName ?? "Scores")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshScores() }
    }

    private var weekBinding: Binding<Int> {
        Binding(
            get: { model.selectedWeek },
            set: { week in Task { await model.changeWeek(to: week) } }
        )
    }

    @ViewBuilder
    private var seasonScheduleLink: some View {
        if let scope = model.browseScope {
            NavigationLink(value: ScheduleRoute(scope: scope)) {
                Label("Season schedule", systemImage: "calendar")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("scores-season-schedule")
        }
    }
}

private struct MatchupCard: View {
    @Environment(AppModel.self) private var model
    let matchup: Matchup
    let snapshot: ScoresSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let freshness = ScoreFreshness(snapshot: snapshot, failed: model.scoreRefreshError != nil,
                saved: model.isUsingCachedSession || model.cachedScoresDate != nil, preview: model.isDemo, now: context.date)
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    team(matchup.away, freshness: freshness, now: context.date)
                    Divider()
                    team(matchup.home, freshness: freshness, now: context.date)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }
    }

    private func team(_ team: MatchupTeam, freshness: ScoreFreshness, now: Date) -> some View {
        let projection = ScoringGamePresentation.projection(for: team, in: matchup, stale: freshness.qualifiesGameState)
        return HStack(alignment: .center, spacing: 8) {
            TeamMark(abbreviation: team.abbreviation, seed: team.accentSeed, size: 28, artworkURLs: team.artworkURLs)
            VStack(alignment: .leading, spacing: 3) {
                Text(team.name).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                GameStateLabel(text: ScoringGamePresentation.label(for: matchup, stale: freshness.qualifiesGameState),
                    live: matchup.status.isLive && !freshness.qualifiesGameState)
            }
            .accessibilityIdentifier("league-identity-\(team.id)")
            Spacer(minLength: 4)
            ScoreValue(points: team.reportedScore, projection: projection.points, precision: snapshot.scorePrecision,
                font: .title3.weight(.medium),
                liveEstimate: projection.isLiveEstimate, showProjection: projection.isVisible,
                change: freshness.qualifiesGameState ? nil : model.scoringChanges.change(for: .init(matchupID: matchup.id, teamID: team.id), now: now), compact: true)
                .accessibilityIdentifier("league-score-\(team.id)")
        }
        .padding(.vertical, 16)
    }
}
