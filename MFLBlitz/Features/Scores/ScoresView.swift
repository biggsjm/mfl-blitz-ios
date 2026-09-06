import SwiftUI

struct ScoresView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSettings = false

    private let columns = [GridItem(.adaptive(minimum: 330), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if model.isDemo { DemoBanner() }

                HStack {
                    WeekPicker(selection: weekBinding, range: 1...18)
                    Spacer()
                    UpdatedLabel(date: model.scores.lastUpdated, isRefreshing: model.isRefreshing)
                }
                .padding(.horizontal, BlitzMetrics.pagePadding)

                if let featured = model.scores.featuredMatchup {
                    FeaturedMatchupCard(matchup: featured)
                        .padding(.horizontal, BlitzMetrics.pagePadding)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Around the league")
                        .font(.title3.bold())
                        .padding(.horizontal, BlitzMetrics.pagePadding)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.scores.matchups.filter { !$0.isUserMatchup }) { matchup in
                            MatchupCard(matchup: matchup)
                        }
                    }
                    .padding(.horizontal, BlitzMetrics.pagePadding)
                }
            }
            .padding(.bottom, 24)
            .readablePageWidth()
        }
        .pageBackground()
        .navigationTitle(model.workspace?.leagueName ?? "Scores")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.scores.isLive {
                    StatusPill(text: "Live", systemImage: "dot.radiowaves.left.and.right", tone: .live)
                }
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
            }
        }
        .refreshable { await model.refreshAll() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }

    private var weekBinding: Binding<Int> {
        Binding(
            get: { model.selectedWeek },
            set: { week in Task { await model.changeWeek(to: week) } }
        )
    }
}

private struct UpdatedLabel: View {
    let date: Date
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isRefreshing {
                ProgressView().controlSize(.small)
                Text("Updating")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Updated \(date, style: .relative)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct FeaturedMatchupCard: View {
    let matchup: Matchup

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR MATCHUP")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.blitzGreen)
                    Text(matchup.status.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                if matchup.status.isLive {
                    HStack(spacing: 5) {
                        Circle().fill(.red).frame(width: 7, height: 7)
                        Text("LIVE")
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 28)
                    .background(.red.opacity(0.85), in: Capsule())
                    .accessibilityLabel("Live scoring")
                }
            }

            HStack(alignment: .top, spacing: 10) {
                FeaturedTeam(team: matchup.away, isLeading: matchup.leaderID == matchup.away.id)
                Text("–")
                    .font(.title.bold())
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.top, 49)
                FeaturedTeam(team: matchup.home, isLeading: matchup.leaderID == matchup.home.id)
            }

            Divider().overlay(.white.opacity(0.16))

            HStack(spacing: 0) {
                ProjectionMetric(title: "Projection", value: projectionText)
                Divider().frame(height: 34).overlay(.white.opacity(0.16))
                ProjectionMetric(title: "Win outlook", value: winOutlook)
                Divider().frame(height: 34).overlay(.white.opacity(0.16))
                ProjectionMetric(title: "Still playing", value: "\(matchup.away.playersRemaining + matchup.home.playersRemaining)")
            }
        }
        .padding(18)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.blitzNavy, Color(red: 0.05, green: 0.13, blue: 0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 78))
                .foregroundStyle(Color.blitzGreen.opacity(0.07))
                .offset(x: -12, y: 8)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var winOutlook: String {
        guard let awayProjection = matchup.away.projectedScore,
              let homeProjection = matchup.home.projectedScore else { return "—" }
        let total = awayProjection + homeProjection
        guard total > 0 else { return "Even" }
        let percent = Int((awayProjection / total * 100).rounded())
        return "\(percent)%"
    }

    private var projectionText: String {
        "\(matchup.away.projectedScore.pointsText) – \(matchup.home.projectedScore.pointsText)"
    }

    private var accessibilitySummary: String {
        let awayScore = matchup.away.score.formatted(.number.precision(.fractionLength(1)))
        let homeScore = matchup.home.score.formatted(.number.precision(.fractionLength(1)))
        return "Your matchup. \(matchup.away.name), \(awayScore) points. \(matchup.home.name), \(homeScore) points. \(matchup.status.label)."
    }
}

private struct FeaturedTeam: View {
    let team: MatchupTeam
    let isLeading: Bool

    var body: some View {
        VStack(spacing: 8) {
            TeamMark(abbreviation: team.abbreviation, seed: team.accentSeed, size: 48)
            Text(team.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 38, alignment: .top)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(team.score, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 33, weight: .black, design: .rounded))
                    .contentTransition(.numericText())
                if isLeading {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.blitzGreen)
                        .accessibilityLabel("Leading")
                }
            }
            Text("\(team.playersRemaining) remaining")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProjectionMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold())
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MatchupCard: View {
    let matchup: Matchup

    var body: some View {
        SurfaceCard {
            VStack(spacing: 12) {
                HStack {
                    statusLabel
                    Spacer()
                    Text(matchup.status.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                CompactTeamRow(team: matchup.away, isLeader: matchup.leaderID == matchup.away.id)
                CompactTeamRow(team: matchup.home, isLeader: matchup.leaderID == matchup.home.id)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(matchup.away.name) \(matchup.away.score, format: .number.precision(.fractionLength(1))), \(matchup.home.name) \(matchup.home.score, format: .number.precision(.fractionLength(1))). \(matchup.status.label).")
    }

    private var statusLabel: some View {
        Group {
            if matchup.status.isLive {
                Label("Live", systemImage: "circle.fill")
                    .foregroundStyle(.red)
            } else {
                Text(matchup.status.label == "Final" ? "Final" : "Upcoming")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.bold())
    }
}

private struct CompactTeamRow: View {
    let team: MatchupTeam
    let isLeader: Bool

    var body: some View {
        HStack(spacing: 10) {
            TeamMark(abbreviation: team.abbreviation, seed: team.accentSeed, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.subheadline.weight(isLeader ? .bold : .medium))
                    .lineLimit(1)
                Text("Proj \(team.projectedScore.pointsText) · \(team.playersRemaining) left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(team.score, format: .number.precision(.fractionLength(1)))
                .font(.title3.weight(isLeader ? .black : .semibold).monospacedDigit())
        }
    }
}
