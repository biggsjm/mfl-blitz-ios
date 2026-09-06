import SwiftUI

struct MatchupDetailView: View {
    @Environment(AppModel.self) private var model
    let matchupID: String

    @State private var benchIsExpanded = false

    var body: some View {
        ScrollView {
            if let matchup {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let message = model.scoreRefreshError {
                        Label(message, systemImage: "wifi.exclamationmark")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    MatchupFreshnessLabel(
                        date: model.scores.lastUpdated,
                        isRefreshing: model.isRefreshing
                    )

                    MatchupDetailHeader(
                        matchup: matchup,
                        isDemo: model.isDemo,
                        scorePrecision: model.scores.scorePrecision
                    )

                    sectionHeading(
                        title: "Starting lineups",
                        subtitle: "Player points by position"
                    )

                    if matchup.away.starters.isEmpty && matchup.home.starters.isEmpty {
                        Group {
                            if matchup.away.players.isEmpty && matchup.home.players.isEmpty {
                                ContentUnavailableView(
                                    "Player scoring unavailable",
                                    systemImage: "figure.american.football",
                                    description: Text("MFL returned the team totals but no player scoring for this matchup.")
                                )
                            } else {
                                ContentUnavailableView(
                                    "Starting lineups unavailable",
                                    systemImage: "questionmark.circle",
                                    description: Text("MFL returned player scoring but did not identify any starting players.")
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(positions(for: matchup, showingBench: false), id: \.self) { position in
                            PositionComparisonCard(
                                position: position,
                                scorePrecision: model.scores.scorePrecision,
                                awayTeam: matchup.away,
                                homeTeam: matchup.home,
                                awayPlayers: players(
                                    in: matchup.away.starters,
                                    at: position
                                ),
                                homePlayers: players(
                                    in: matchup.home.starters,
                                    at: position
                                ),
                                footer: nil
                            )
                        }
                    }

                    if !matchup.away.bench.isEmpty || !matchup.home.bench.isEmpty {
                        DisclosureGroup(isExpanded: $benchIsExpanded) {
                            LazyVStack(spacing: 12) {
                                ForEach(positions(for: matchup, showingBench: true), id: \.self) { position in
                                    PositionComparisonCard(
                                        position: position,
                                        scorePrecision: model.scores.scorePrecision,
                                        awayTeam: matchup.away,
                                        homeTeam: matchup.home,
                                        awayPlayers: players(
                                            in: matchup.away.bench,
                                            at: position
                                        ),
                                        homePlayers: players(
                                            in: matchup.home.bench,
                                            at: position
                                        ),
                                        footer: "Bench points · not included in team totals"
                                    )
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bench scoring")
                                    .font(.title3.bold())
                                Text("Bench points do not count toward the matchup total")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }

                    if !matchup.away.unclassifiedPlayers.isEmpty
                        || !matchup.home.unclassifiedPlayers.isEmpty
                    {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeading(
                                title: "Other player scoring",
                                subtitle: "MFL did not identify these players as starters or bench players"
                            )
                            ForEach(positionsForUnclassifiedPlayers(in: matchup), id: \.self) { position in
                                PositionComparisonCard(
                                    position: position,
                                    scorePrecision: model.scores.scorePrecision,
                                    awayTeam: matchup.away,
                                    homeTeam: matchup.home,
                                    awayPlayers: players(
                                        in: matchup.away.unclassifiedPlayers,
                                        at: position
                                    ),
                                    homePlayers: players(
                                        in: matchup.home.unclassifiedPlayers,
                                        at: position
                                    ),
                                    footer: "MFL did not report whether these points count toward the team total"
                                )
                            }
                        }
                    }

                    Label(
                        model.isDemo
                            ? "Sample scoring data for exploring this screen."
                            : "Team and player totals come directly from MyFantasyLeague.",
                        systemImage: model.isDemo ? "sparkles" : "checkmark.seal"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, BlitzMetrics.pagePadding)
                .padding(.bottom, 28)
                .readablePageWidth()
            } else {
                ContentUnavailableView(
                    "Matchup unavailable",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    description: Text("This matchup is no longer in the current scoring response. Go back and refresh the scores.")
                )
                .padding(.horizontal, BlitzMetrics.pagePadding)
                .padding(.top, 48)
            }
        }
        .pageBackground()
        .navigationTitle("Week \(model.scores.week) Matchup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if matchup?.status.isLive == true {
                ToolbarItem(placement: .topBarTrailing) {
                    StatusPill(
                        text: "Live",
                        systemImage: "dot.radiowaves.left.and.right",
                        tone: .live
                    )
                }
            }
        }
        .refreshable { await model.refreshScores() }
        .accessibilityIdentifier("matchup-detail")
    }

    private var matchup: Matchup? {
        model.scores.matchups.first(where: { $0.id == matchupID })
    }

    private func sectionHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func players(in players: [MatchupPlayer], at position: String) -> [MatchupPlayer] {
        players.filter { normalizedPosition($0.position) == position }
    }

    private func positions(for matchup: Matchup, showingBench: Bool) -> [String] {
        let awayPlayers = showingBench ? matchup.away.bench : matchup.away.starters
        let homePlayers = showingBench ? matchup.home.bench : matchup.home.starters
        let available = Set((awayPlayers + homePlayers).map { normalizedPosition($0.position) })
        let preferred = ["QB", "RB", "WR", "TE", "K", "DEF"]
        return preferred.filter(available.contains)
            + available.subtracting(preferred).sorted()
    }

    private func positionsForUnclassifiedPlayers(in matchup: Matchup) -> [String] {
        let available = Set(
            (matchup.away.unclassifiedPlayers + matchup.home.unclassifiedPlayers)
                .map { normalizedPosition($0.position) }
        )
        let preferred = ["QB", "RB", "WR", "TE", "K", "DEF"]
        return preferred.filter(available.contains)
            + available.subtracting(preferred).sorted()
    }

    private func normalizedPosition(_ position: String) -> String {
        switch position.uppercased() {
        case "PK": "K"
        case "DF", "D/ST", "DST": "DEF"
        default: position.uppercased()
        }
    }
}

private struct MatchupFreshnessLabel: View {
    let date: Date
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Updating scores")
            } else {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(Color.blitzGreen)
                Text("Updated \(date, style: .relative)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}

private struct MatchupDetailHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let matchup: Matchup
    let isDemo: Bool
    let scorePrecision: Int

    var body: some View {
        VStack(spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    statusLabel
                    sourceLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    statusLabel
                    Spacer()
                    sourceLabel
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 14) {
                    MatchupHeaderTeam(
                        team: matchup.away,
                        isLeading: matchup.leaderID == matchup.away.id,
                        scorePrecision: scorePrecision
                    )
                    Divider().overlay(.white.opacity(0.16))
                    MatchupHeaderTeam(
                        team: matchup.home,
                        isLeading: matchup.leaderID == matchup.home.id,
                        scorePrecision: scorePrecision
                    )
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    MatchupHeaderTeam(
                        team: matchup.away,
                        isLeading: matchup.leaderID == matchup.away.id,
                        scorePrecision: scorePrecision
                    )

                    Text("–")
                        .font(.title2.bold())
                        .foregroundStyle(.white.opacity(0.42))

                    MatchupHeaderTeam(
                        team: matchup.home,
                        isLeading: matchup.leaderID == matchup.home.id,
                        scorePrecision: scorePrecision
                    )
                }
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
                .font(.system(size: 88))
                .foregroundStyle(Color.blitzGreen.opacity(0.065))
                .offset(x: -10, y: 18)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        "\(matchup.away.name), \(matchup.away.score.pointsText(precision: scorePrecision)) points. \(matchup.home.name), \(matchup.home.score.pointsText(precision: scorePrecision)) points. \(matchup.status.label)."
    }

    private var statusLabel: some View {
        Label(
            matchup.status.label.uppercased(),
            systemImage: statusSystemImage
        )
        .font(.caption.bold())
        .foregroundStyle(.white.opacity(0.78))
        .lineLimit(2)
    }

    private var sourceLabel: some View {
        Text(isDemo ? "PREVIEW DATA" : "OFFICIAL MFL TOTALS")
            .font(.caption2.bold())
            .foregroundStyle(.white.opacity(0.54))
            .lineLimit(2)
    }

    private var statusSystemImage: String {
        switch matchup.status {
        case .pregame: "clock"
        case .live: "dot.radiowaves.left.and.right"
        case .final: "checkmark.circle"
        }
    }
}

private struct MatchupHeaderTeam: View {
    let team: MatchupTeam
    let isLeading: Bool
    let scorePrecision: Int

    var body: some View {
        VStack(spacing: 7) {
            TeamMark(abbreviation: team.abbreviation, seed: team.accentSeed, size: 48, artworkURLs: team.artworkURLs)
            Text(team.name)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 38, alignment: .top)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(team.score.pointsText(precision: scorePrecision))
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .monospacedDigit()
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

private struct PositionComparisonCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let position: String
    let scorePrecision: Int
    let awayTeam: MatchupTeam
    let homeTeam: MatchupTeam
    let awayPlayers: [MatchupPlayer]
    let homePlayers: [MatchupPlayer]
    let footer: String?

    private var rowCount: Int { max(awayPlayers.count, homePlayers.count) }

    var body: some View {
        SurfaceCard {
            VStack(spacing: 13) {
                HStack(alignment: .center, spacing: 8) {
                    PositionPoints(
                        abbreviation: awayTeam.abbreviation,
                        points: pointsTotal(for: awayPlayers),
                        side: .away,
                        scorePrecision: scorePrecision
                    )
                    PositionBadge(position: position, isAccessibilityHidden: false)
                        .accessibilityLabel("\(position) position comparison")
                        .accessibilityIdentifier("position-\(position)")
                    PositionPoints(
                        abbreviation: homeTeam.abbreviation,
                        points: pointsTotal(for: homePlayers),
                        side: .home,
                        scorePrecision: scorePrecision
                    )
                }

                Divider()

                if dynamicTypeSize.isAccessibilitySize {
                    TeamPositionStack(
                        team: awayTeam,
                        players: awayPlayers,
                        side: .away,
                        scorePrecision: scorePrecision
                    )
                    Divider()
                    TeamPositionStack(
                        team: homeTeam,
                        players: homePlayers,
                        side: .home,
                        scorePrecision: scorePrecision
                    )
                } else {
                    ForEach(0 ..< rowCount, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            MatchupPlayerCell(
                                player: awayPlayers.indices.contains(index) ? awayPlayers[index] : nil,
                                teamName: awayTeam.name,
                                side: .away,
                                scorePrecision: scorePrecision
                            )

                            Rectangle()
                                .fill(Color.secondary.opacity(0.18))
                                .frame(width: 1)
                                .frame(minHeight: 74)
                                .accessibilityHidden(true)

                            MatchupPlayerCell(
                                player: homePlayers.indices.contains(index) ? homePlayers[index] : nil,
                                teamName: homeTeam.name,
                                side: .home,
                                scorePrecision: scorePrecision
                            )
                        }

                        if index < rowCount - 1 {
                            Divider()
                        }
                    }
                }

                if let footer {
                    Text(footer)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func pointsTotal(for players: [MatchupPlayer]) -> Double? {
        let points = players.compactMap(\.livePoints)
        guard points.count == players.count else { return nil }
        return points.reduce(0, +)
    }
}

private struct PositionPoints: View {
    let abbreviation: String
    let points: Double?
    let side: MatchupSide
    let scorePrecision: Int

    private var alignment: HorizontalAlignment { side == .away ? .leading : .trailing }
    private var frameAlignment: Alignment { side == .away ? .leading : .trailing }

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            if let points {
                Text(points.pointsText(precision: scorePrecision))
                    .font(.headline.bold().monospacedDigit())
            } else {
                Text("—")
                    .font(.headline.bold())
                    .accessibilityLabel("Points unavailable")
            }
            Text(abbreviation.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let points {
            return "\(abbreviation), \(points.pointsText(precision: scorePrecision)) points at this position"
        }
        return "\(abbreviation), points unavailable at this position"
    }
}

private struct TeamPositionStack: View {
    let team: MatchupTeam
    let players: [MatchupPlayer]
    let side: MatchupSide
    let scorePrecision: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(team.name)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if players.isEmpty {
                Text("No player at this position")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(players) { player in
                    MatchupPlayerCell(
                        player: player,
                        teamName: team.name,
                        side: side,
                        scorePrecision: scorePrecision
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum MatchupSide { case away, home }

private struct MatchupPlayerCell: View {
    let player: MatchupPlayer?
    let teamName: String
    let side: MatchupSide
    let scorePrecision: Int

    private var alignment: HorizontalAlignment { side == .away ? .leading : .trailing }
    private var frameAlignment: Alignment { side == .away ? .leading : .trailing }

    var body: some View {
        Group {
            if let player {
                VStack(alignment: alignment, spacing: 4) {
                    Text(player.name)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(side == .away ? .leading : .trailing)
                        .lineLimit(2)

                    if let livePoints = player.livePoints {
                        Text(livePoints.pointsText(precision: scorePrecision))
                            .font(.title3.weight(.black).monospacedDigit())
                            .contentTransition(.numericText())
                    } else {
                        Text("—")
                            .font(.title3.weight(.black))
                            .accessibilityLabel("Score unavailable")
                    }

                    Label(gameStateLabel(for: player), systemImage: gameStateIcon(for: player))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(gameStateColor(for: player))

                    Text(player.nflTeam)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    if let statLine = player.statLine?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !statLine.isEmpty
                    {
                        Text(statLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(side == .away ? .leading : .trailing)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: player))
            } else {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 74, alignment: frameAlignment)
                    .accessibilityHidden(true)
            }
        }
    }

    private func gameStateLabel(for player: MatchupPlayer) -> String {
        switch player.gameState {
        case .pregame: "Yet to play"
        case .live: "In progress"
        case .final: "Final / no game"
        case .unknown: "Status unavailable"
        }
    }

    private func gameStateIcon(for player: MatchupPlayer) -> String {
        switch player.gameState {
        case .pregame: "clock"
        case .live: "dot.radiowaves.left.and.right"
        case .final: "checkmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private func gameStateColor(for player: MatchupPlayer) -> Color {
        player.gameState == .live ? .red : .secondary
    }

    private func accessibilityLabel(for player: MatchupPlayer) -> String {
        let points = player.livePoints.map {
            "\($0.pointsText(precision: scorePrecision)) points"
        } ?? "score unavailable"
        var label = "\(teamName), \(player.name), \(player.position), \(player.nflTeam), \(points), \(gameStateLabel(for: player))"
        if let statLine = player.statLine, !statLine.isEmpty { label += ", \(statLine)" }
        return label
    }
}
