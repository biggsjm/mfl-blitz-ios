import SwiftUI

struct MatchupDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.scenePhase) private var scenePhase
    let matchupID: String
    var snapshot: ScoresSnapshot? = nil
    var refreshError: String? = nil
    var isRefreshingSnapshot = false
    var refreshAction: (@MainActor () async -> Void)? = nil

    var offline = false

    @State private var benchIsExpanded = false
    @AppStorage("matchup-view-mode") private var viewMode = "lineups"
    @State private var heroOffscreen = false
    @State private var heroEnd: CGFloat = .infinity
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
      TimelineView(.periodic(from: .now, by: 30)) { context in
        ScrollView {
            if let matchup {
                VStack(alignment: .leading, spacing: 10) {
                    if let receipt = liveReceipt {
                        Text("Team totals from Live Activity · \(ScoreFreshness.age(receipt.state.updatedAt, now: context.date))")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("activity-score-receipt")
                        Text(matchup.away.players.isEmpty && matchup.home.players.isEmpty ? "Loading player scores…" : "Player scores below are from the last app check.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ScoreFreshnessLabel(snapshot: displayScores,
                        refreshing: snapshot == nil ? model.isLoadingScores : isRefreshingSnapshot,
                        failed: readFailed, offline: snapshot == nil ? model.scoresOffline : offline,
                        saved: model.isUsingCachedSession, preview: model.isDemo)
                    if viewMode != "matchup" {
                    ScoringMatchupHero(matchup: matchup, snapshot: displayScores,
                        failed: readFailed, saved: model.isUsingCachedSession, teamLinks: true)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.frame(in: .named("matchup-content")).maxY
                        } action: { bottom in
                            if bottom > 0 { heroEnd = bottom }
                        }
                    }
                    if matchup.isUserMatchup,model.matchupActivity.enabled,model.matchupActivity.needsContinuation {
                        Button("Continue Live Activity",systemImage:"arrow.clockwise") {
                            Task { await model.restartMatchupActivity() }
                        }.buttonStyle(.bordered).disabled(model.isDemo || model.isUsingCachedSession)
                            .accessibilityIdentifier("continue-live-activity")
                    }
                    if viewMode == "matchup" {
                        MatchupModeView(matchup: matchup, week: displayScores.week, precision: displayScores.scorePrecision,
                            showLineups: { viewMode = "lineups" })
                    } else {
                    sectionHeading(
                        title: "Starting lineups",
                        subtitle: MatchupGameInfo.timeZoneLabel(locale: locale, timeZone: timeZone)
                    )

                    if matchup.away.starters.isEmpty && matchup.home.starters.isEmpty {
                        Group {
                            if matchup.away.players.isEmpty && matchup.home.players.isEmpty,
                               (snapshot == nil ? model.isLoadingScores : isRefreshingSnapshot) {
                                ProgressView("Loading player scores…")
                            } else if matchup.away.players.isEmpty && matchup.home.players.isEmpty {
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
                        VStack(spacing: 6) {
                          ForEach(positions(for: matchup, showingBench: false), id: \.self) { position in
                            PositionComparisonCard(
                                position: position,
                                scorePrecision: displayScores.scorePrecision,
                                awayTeam: matchup.away,
                                homeTeam: matchup.home,
                                awayPlayers: players(
                                    in: matchup.away.starters,
                                    at: position,
                                    usingLineupSlots: true
                                ),
                                homePlayers: players(
                                    in: matchup.home.starters,
                                    at: position,
                                    usingLineupSlots: true
                                ),
                                footer: nil
                            )
                          }
                        }
                    }
                    }

                    if viewMode != "matchup" {
                    if !matchup.away.bench.isEmpty || !matchup.home.bench.isEmpty {
                      VStack(alignment: .leading, spacing: 8) {
                        DisclosureGroup(isExpanded: $benchIsExpanded) {
                            LazyVStack(spacing: 6) {
                                ForEach(positions(for: matchup, showingBench: true), id: \.self) { position in
                                    PositionComparisonCard(
                                        position: position,
                                        scorePrecision: displayScores.scorePrecision,
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
                                        footer: nil
                                    )
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("Bench scoring").font(.title3.bold())
                        }
                        .tint(.primary)
                        if !benchIsExpanded {
                            HStack(alignment: .top, spacing: 20) {
                                benchTotal(matchup.away, trailing: false)
                                benchTotal(matchup.home, trailing: true)
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("bench-score-summary")
                        }
                      }
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
                                    scorePrecision: displayScores.scorePrecision,
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
                            : "Scoring from MyFantasyLeague.",
                        systemImage: model.isDemo ? "sparkles" : "checkmark.seal"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .modifier(UniformMatchupPlayerAreas())
                .coordinateSpace(name: "matchup-content")
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
        .accessibilityIdentifier("matchup-detail")
        .coordinateSpace(name: "matchup-scroll")
        .modifier(MatchupScrollMemory(mode: viewMode))
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in
            scrollOffset = offset
            if !heroOffscreen && offset > heroEnd { heroOffscreen = true }
            else if heroOffscreen && offset < heroEnd - 80 { heroOffscreen = false }
        }
        .onChange(of: heroEnd) { _, end in
            if !heroOffscreen && scrollOffset > end { heroOffscreen = true }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let matchup {
                VStack(spacing: 8) {
                    if viewMode == "matchup" || heroOffscreen {
                        CompactMatchupScore(matchup: liveReceipt?.matchup ?? matchup, precision: displayScores.scorePrecision,
                            stale: ScoreFreshness(snapshot: liveReceipt?.snapshot ?? displayScores, failed: readFailed, saved: model.isUsingCachedSession, preview: model.isDemo).qualifiesGameState)
                    }
                    Picker("Scoring view", selection: $viewMode) {
                        Text("Lineups").tag("lineups")
                        Text("Live players").tag("matchup")
                    }.pickerStyle(.segmented).accessibilityIdentifier("matchup-view-mode")
                }.padding(.horizontal, BlitzMetrics.pagePadding).padding(.vertical, 8).background(.bar)
            }
        }
        .pageBackground()
        .navigationTitle("Week \(displayScores.week) Matchup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let matchup {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MatchupTimelineView(matchup: matchup, week: displayScores.week, precision: displayScores.scorePrecision)
                    } label: {
                        Label("Matchup timeline", systemImage: "clock.arrow.circlepath")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("open-matchup-timeline")
                }
            }
        }
        .refreshable {
            async let nfl: Void = refreshNFL()
            async let games: Void = model.refreshScoringGames(week: displayScores.week, force: true)
            if let refreshAction { await refreshAction() }
            else { await model.refreshScores() }
            _ = await (nfl, games)
        }
        .task(id: "\(model.workspace?.storageScope ?? "none")|\(displayScores.week)|\(model.isUsingCachedSession)") {
            guard matchup != nil, !model.isUsingCachedSession else { return }
            // Shared, cached weekly data is optional; never gate scores or player navigation on it.
            await model.loadPlayerAvailability(week: displayScores.week)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, snapshot == nil, !model.isUsingCachedSession else { return }
            await model.refreshScoresOnEntry()
        }
        .task(id: "games|\(scenePhase)|\(displayScores.week)") {
            guard scenePhase == .active else { return }
            await model.refreshScoringGames(week: displayScores.week)
        }
        .task(id: "nfl|\(scenePhase)|\(model.workspace?.season ?? 0)|\(displayScores.week)") {
            guard scenePhase == .active, model.usesNFLStats, !model.isUsingCachedSession,
                  let season = model.workspace?.season else { return }
            await model.nflStats.poll(season: season, week: displayScores.week,
                teams: nflPlayers.map(\.nflTeam), defenseTeams: nflPlayers.filter { NFLFeedGame.isDefense($0.position) }.map(\.nflTeam))
        }
        .task(id: displayScores.checkedAt) {
            guard let scope=model.workspace?.storageScope,!model.isUsingCachedSession else { return }
            await model.matchupTimeline.observe(displayScores,scope:scope,persist:!model.isDemo)
        }
        .environment(\.browsedScoringWeek, displayScores.week)
        .environment(\.scoringContext, ScoringDisplayContext(matchupID: matchupID,
            freshness: ScoreFreshness(snapshot: displayScores, failed: readFailed,
                offline: snapshot == nil ? model.scoresOffline : offline, saved: model.isUsingCachedSession,
                preview: model.isDemo, now: context.date)))
        .playerSearch()
      }
    }

    private var nflPlayers: [MatchupPlayer] { (matchup?.away.players ?? []) + (matchup?.home.players ?? []) }

    private func refreshNFL() async {
        guard model.usesNFLStats, let season = model.workspace?.season else { return }
        await model.nflStats.refresh(season: season, week: displayScores.week, force: true, teams: nflPlayers.map(\.nflTeam), defenseTeams: nflPlayers.filter { NFLFeedGame.isDefense($0.position) }.map(\.nflTeam))
    }

    private var readFailed: Bool { (snapshot == nil ? model.scoreRefreshError : refreshError) != nil }

    private var matchup: Matchup? {
        displayScores.matchups.first(where: { $0.id == matchupID })
    }

    private var displayScores: ScoresSnapshot {
        let stored = snapshot ?? model.scores
        if !stored.matchups.contains(where: { $0.id == matchupID }), stored.checkedAt == nil,
           let preview = model.matchupActivity.scorePreview(scope: model.workspace?.storageScope, week: stored.week, matchupID: matchupID) {
            return preview
        }
        return stored
    }
    private var liveReceipt: ScoringLiveReceipt? {
        guard let matchup else { return nil }
        return ScoringLiveReceipt(matchup: matchup, snapshot: displayScores,
            state: model.matchupActivity.latestScoreState(matchup: matchup, scope: model.workspace?.storageScope, week: displayScores.week))
    }

    private func benchTotal(_ team: MatchupTeam, trailing: Bool) -> some View {
        let points = ScoringGamePresentation.benchPoints(for: team)
        return VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            Text(points.map { "\($0.pointsText(precision: displayScores.scorePrecision)) pts" } ?? "—")
                .font(.title3.weight(.medium)).monospacedDigit()
            Text(team.name).font(.caption).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(trailing ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(team.name), bench points, \(points.map { $0.pointsText(precision: displayScores.scorePrecision) } ?? "not fully reported")")
        .accessibilityIdentifier("bench-total-\(team.id)")
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

    private func players(in players: [MatchupPlayer], at position: String, usingLineupSlots: Bool = false) -> [MatchupPlayer] {
        players.filter { normalizedPosition(usingLineupSlots ? ($0.lineupSlot ?? $0.position) : $0.position) == position }
    }

    private func positions(for matchup: Matchup, showingBench: Bool) -> [String] {
        let awayPlayers = showingBench ? matchup.away.bench : matchup.away.starters
        let homePlayers = showingBench ? matchup.home.bench : matchup.home.starters
        let available = Set((awayPlayers + homePlayers).map { normalizedPosition(showingBench ? $0.position : ($0.lineupSlot ?? $0.position)) })
        let preferred = ["QB", "RB", "WR", "TE", "FLEX", "K", "DEF"]
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
            VStack(spacing: 0) {
                if dynamicTypeSize.isAccessibilitySize {
                    slotLabel().padding(.vertical, 8)
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
                        HStack(alignment: .center, spacing: 7) {
                            MatchupPlayerCell(
                                player: awayPlayers.indices.contains(index) ? awayPlayers[index] : nil,
                                teamName: awayTeam.name,
                                teamID: awayTeam.id,
                                side: .away,
                                scorePrecision: scorePrecision
                            )

                            slotLabel(index: index)

                            MatchupPlayerCell(
                                player: homePlayers.indices.contains(index) ? homePlayers[index] : nil,
                                teamName: homeTeam.name,
                                teamID: homeTeam.id,
                                side: .home,
                                scorePrecision: scorePrecision
                            )
                        }
                        .padding(.vertical, 3)

                    }
                }

                if let footer {
                    Text(footer)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
    }

    private func slotLabel(index: Int = 0) -> some View {
        Text(position)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 24)
            .padding(.vertical, 3)
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 6 : 0)
            .accessibilityLabel("\(position) position comparison")
            .accessibilityIdentifier(index == 0 ? "position-\(position)" : "position-\(position)-\(index)")
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
                        teamID: team.id,
                        side: side,
                        scorePrecision: scorePrecision
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum MatchupSide { case away, home }

struct MatchupPlayerCell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.browsedScoringWeek) private var inspectedWeek
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scoringContext) private var scoringContext
    @ScaledMetric(relativeTo: .caption) private var scoreColumnWidth = 40
    let player: MatchupPlayer?
    let teamName: String
    let teamID: String
    let side: MatchupSide
    let scorePrecision: Int
    var showsGameDayStatus = false

    private var alignment: HorizontalAlignment { side == .away ? .leading : .trailing }
    private var frameAlignment: Alignment { side == .away ? .leading : .trailing }

    var body: some View {
        Group {
            if let player {
                playerIdentityLink(player) {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: alignment, spacing: 5) {
                                playerName(player)
                                score(player)
                                playerContext(player)
                            }
                        } else {
                            HStack(alignment: .top, spacing: 6) {
                                if side == .home { Color.clear.frame(width: scoreColumnWidth, height: 1) }
                                VStack(alignment: alignment, spacing: 3) {
                                    playerName(player)
                                    playerContext(player)
                                }
                                .frame(maxWidth: .infinity, alignment: frameAlignment)
                                if side == .away { Color.clear.frame(width: scoreColumnWidth, height: 1) }
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: side == .away ? .topLeading : .topTrailing)
                    .modifier(UniformMatchupPlayerArea())
                    .overlay(alignment: side == .away ? .trailing : .leading) {
                        if !dynamicTypeSize.isAccessibilitySize { score(player).padding(.horizontal, 8) }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(for: player))
                }
            } else {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: frameAlignment)
                    .accessibilityHidden(true)
                    .modifier(UniformMatchupPlayerArea())
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func healthLabel(_ player: MatchupPlayer) -> String? {
        guard let week = inspectedWeek, let availability = model.playerTools.availability[week],
              availability.scope == model.workspace?.storageScope, availability.week == week,
              let health = availability.injuries[player.id], health.needsAttention else { return nil }
        return health.shortLabel
    }

    private func playerName(_ player: MatchupPlayer) -> some View {
        HStack(spacing: 4) {
            if showsGameDayStatus { Text(player.position).font(.caption2.weight(.semibold)).foregroundStyle(Color.blitzAction) }
            ViewThatFits(in: .horizontal) {
                Text(player.name).fixedSize(horizontal: true, vertical: false)
                Text(shortName(player)).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.8)
            }
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(player.nflTeam).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).fixedSize()
            }
        }
    }

    private func shortName(_ player: MatchupPlayer) -> String {
        guard !NFLFeedGame.isDefense(player.position) else { return player.name }
        let parts = player.name.split(separator: " ")
        guard parts.count > 1, let initial = parts.first?.first else { return player.name }
        return "\(initial). " + parts.dropFirst().joined(separator: " ")
    }

    @ViewBuilder private func playerContext(_ player: MatchupPlayer) -> some View {
        gameCaption(player)
        if let stats = compactStatLine(player), !stats.isEmpty {
            Text(stats).font(.caption2).foregroundStyle(.primary)
                .multilineTextAlignment(side == .away ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        if showsGameDayStatus, let health = healthLabel(player) {
            Label(health, systemImage: "exclamationmark.circle")
                .font(.caption2).foregroundStyle(ScoringStyle.negative)
        }
    }

    private func score(_ player: MatchupPlayer) -> some View {
        VStack(alignment: side == .away ? .trailing : .leading, spacing: 2) {
            Text(ScoringGamePresentation.actualPoints(player)?.pointsText(precision: scorePrecision) ?? "—")
                .font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                .accessibilityIdentifier("matchup-points-\(teamID)-\(player.id)")
            if showsPregameProjection(player) {
                Text("Proj.").font(.caption2).foregroundStyle(.secondary)
                Text(player.projectedPoints.pointsText).font(.caption2).foregroundStyle(ScoringStyle.projection).monospacedDigit()
            }
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : scoreColumnWidth,
            alignment: side == .away ? .trailing : .leading)
    }

    private func gameCaption(_ player: MatchupPlayer) -> some View {
        let info = gameInfo(for: player)
        let stale = info.gameCheckedAt == nil ? scoringContext.freshness.qualifiesGameState : info.gameIsStale
        let context = [info.compactScoreLabel ?? info.opponent,
            info.timingLabel(locale: locale, timeZone: timeZone) ?? "Status unavailable"].compactMap { $0 }.joined(separator: " · ")
        return Text((stale && info.isLive ? "Last known: " : "") + context)
            .font(.caption2).foregroundStyle(info.isLive && !stale ? Color.blitzAction : Color.secondary)
            .multilineTextAlignment(side == .away ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func playerIdentityLink<Content: View>(_ player: MatchupPlayer, @ViewBuilder content: () -> Content) -> some View {
        if let scope = model.browseScope {
            NavigationLink(value: PlayerRoute(scope: scope, playerID: player.id, inspectedWeek: inspectedWeek,
                previewIdentity: PlayerIdentity(id: player.id, name: player.name, position: player.position, nflTeam: player.nflTeam),
                scoring: scoringRoute(for: player))) {
                content()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("matchup-player-\(player.id)-\(side)")
            .accessibilityHint("Opens player details")
        } else { content() }
    }

    private func gameInfo(for player: MatchupPlayer) -> MatchupGameInfo {
        MatchupGameInfo(player: player, availability: inspectedWeek.flatMap { model.playerTools.availability[$0] },
            scope: model.workspace?.storageScope, week: inspectedWeek,
            scoringGames: inspectedWeek.flatMap { model.scoringGames[$0] }, nflGame: nflGame(player))
    }

    private func nflGame(_ player: MatchupPlayer) -> NFLFeedGame? {
        guard model.usesNFLStats, let season = model.workspace?.season, let week = inspectedWeek else { return nil }
        return model.nflStats.feed(season: season, week: week)?.game(team: player.nflTeam)
    }
    private func displayedStatLine(_ player: MatchupPlayer) -> String? {
        if let game = nflGame(player), let summary = game.player(matching: player)?.summary {
            return (game.statsAreStale(for: player) ? "Last known: " : "") + summary
        }
        return player.statLine?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compactStatLine(_ player: MatchupPlayer) -> String? {
        guard let game = nflGame(player), let summary = game.player(matching: player)?.compactSummary else {
            return displayedStatLine(player)
        }
        return (game.statsAreStale(for: player) ? "Last known: " : "") + summary
    }

    private func showsPregameProjection(_ player: MatchupPlayer) -> Bool {
        if let game = nflGame(player) { return game.status == "NS" }
        let info = gameInfo(for: player)
        return player.gameState == .pregame && !info.isLive && info.status != "Final"
    }

    private func scoringRoute(for player: MatchupPlayer) -> PlayerScoringContext? {
        guard let week = inspectedWeek, PlayerScoringContext.isEligible(player, game: gameInfo(for: player)) else { return nil }
        return PlayerScoringContext(matchupID: scoringContext.matchupID, teamID: teamID, week: week,
            player: player, checkedAt: scoringContext.freshness.checkedAt, precision: scorePrecision)
    }

    private func accessibilityLabel(for player: MatchupPlayer) -> String {
        let points = ScoringGamePresentation.actualPoints(player).map {
            "\($0.pointsText(precision: scorePrecision)) points"
        } ?? "score unavailable"
        var label = "\(teamName), \(player.name), \(player.position), \(player.nflTeam), \(points), \(gameInfo(for: player).label(locale: locale, timeZone: timeZone))"
        if showsPregameProjection(player) { label += ", pregame projection \(player.projectedPoints.pointsText)" }
        if scoringContext.freshness.qualifiesGameState { label += ", saved game state" }
        if let change = model.scoringChanges.change(for: .init(matchupID: scoringContext.matchupID, teamID: teamID, playerID: player.id)), !scoringContext.freshness.qualifiesGameState { label += ", \(change.signedText) points since previous check" }
        if let statLine = displayedStatLine(player), !statLine.isEmpty { label += ", \(statLine)" }
        if showsGameDayStatus, let health = healthLabel(player) { label += ", \(health)" }
        return label
    }
}
