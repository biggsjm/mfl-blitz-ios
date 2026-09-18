import SwiftUI
import MFLCore

struct PlayerScoringContext: Hashable, Sendable {
    let matchupID: String
    let teamID: String
    let week: Int
    let player: MatchupPlayer
    let checkedAt: Date?
    let precision: Int

    static func resolve(identity: PlayerIdentity, week: Int, scores: ScoresSnapshot?,
                        availability: PlayerAvailabilitySnapshot?, scope: String?, nflGame: NFLFeedGame?) -> Self? {
        let snapshot = scores.flatMap { $0.week == week ? $0 : nil }
        let matches = (snapshot?.matchups ?? []).flatMap { matchup in
            [matchup.away, matchup.home].flatMap { team in
                team.players.filter { $0.id == identity.id }.map { (matchup.id, team.id, $0) }
            }
        }
        // Doubleheaders may repeat the same player; conflicting records never
        // acquire a made-up official score from an arbitrary matchup.
        let consistent = Set(matches.map { $0.2 }).count == 1
        let found = consistent ? matches.first : nil
        let player = found?.2 ?? MatchupPlayer(id: identity.id, name: identity.name,
            position: identity.position ?? "", nflTeam: identity.nflTeam ?? "", livePoints: nil,
            lineupStatus: .unknown, gameSecondsRemaining: nil, statLine: nil)
        let info = MatchupGameInfo(player: player, availability: availability, scope: scope, week: week, nflGame: nflGame)
        guard isEligible(player, game: info) else { return nil }
        return Self(matchupID: found?.0 ?? "", teamID: found?.1 ?? "", week: week, player: player,
                    checkedAt: found == nil ? nil : snapshot?.checkedAt, precision: snapshot?.scorePrecision ?? 1)
    }

    static func isEligible(_ player: MatchupPlayer, game: MatchupGameInfo) -> Bool {
        game.isLive || ["Final", "Final / OT"].contains(game.status ?? "") ||
            player.gameState == .live || (player.gameState == .final && game.status != "Bye week" && game.kickoff == nil)
    }
}

/// The tapped response renders immediately. The scoreboard's existing poller
/// supplies updates; this screen does not introduce a player-specific poller.
struct PlayerScoringWeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.scoreboardIsPolling) private var scoreboardIsPolling
    let context: PlayerScoringContext
    var ownershipSummary: String? = nil
    var ownershipLoading = false
    var refreshOwnership: (@MainActor () async -> Void)? = nil
    @State private var refreshed: ScoresSnapshot?
    @State private var failed = false
    @State private var refreshing = false
    @State private var breakdownExpanded = false

    var body: some View {
      TimelineView(.periodic(from: .now, by: 30)) { timeline in
        let freshness = ScoreFreshness(snapshot: scores, failed: readFailed,
            offline: model.scores.week == context.week && model.scoresOffline,
            saved: model.isUsingCachedSession, preview: model.isDemo, now: timeline.date)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScoreFreshnessLabel(snapshot: scores, refreshing: refreshing || model.isLoadingScores,
                    failed: readFailed, offline: model.scores.week == context.week && model.scoresOffline,
                    saved: model.isUsingCachedSession, preview: model.isDemo,
                    statusPlayers: [player], statusScope: "\(player.name) · Week \(context.week)")
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        PlayerNameCaption(name: player.name, playerID: player.id, nflTeam: player.nflTeam,
                            position: player.position, nameFont: .title2.weight(.medium), metadataFont: .subheadline)
                        Text(ownershipSummary ?? (ownershipLoading ? "Checking ownership…" : "Ownership unavailable"))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("player-week-owner")
                        if ownershipSummary == nil, !ownershipLoading, let refreshOwnership {
                            Button("Retry ownership") { Task { await refreshOwnership() } }.font(.subheadline)
                        }
                    }
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Week \(context.week) points").font(.caption).foregroundStyle(.secondary)
                            ScoreValue(points: ScoringGamePresentation.actualPoints(player), projection: player.projectedPoints,
                                precision: context.precision, font: .largeTitle.weight(.medium), alignment: .leading,
                                pregame: true, showProjection: !isFinal)
                                .onTapGesture { breakdownExpanded.toggle() }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint("Show league points breakdown")
                        }
                        Spacer(minLength: 8)
                        GameStateLabel(text: "\(freshness.qualifiesGameState ? "Last known: " : "")\(player.gameState == .live ? "Live scoring" : "Fantasy points")",
                            live: player.gameState == .live && !freshness.qualifiesGameState)
                    }
                    .accessibilityIdentifier("player-week-points")
                    Divider()
                    if let gameScore = info.scoreLabel ?? info.opponent {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(gameScore).font(.title3.weight(.semibold)).monospacedDigit()
                            GameStateLabel(text: "\(info.gameIsStale ? "Last known: " : "")\(info.timingLabel(locale: locale, timeZone: timeZone) ?? "Status unavailable")",
                                live: info.isLive && !info.gameIsStale)
                            if let possession = info.possessionLabel { Text(possession).font(.caption).foregroundStyle(.secondary) }
                            if let checked = info.gameCheckedAt {
                                Text("NFL score checked \(ScoreFreshness.age(checked, now: timeline.date))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("player-nfl-game")
                        Divider()
                    }
                    ScoringBreakdownView(position: player.position, player: nflGame?.player(matching: player),
                        official: ScoringGamePresentation.actualPoints(player), precision: context.precision, expanded:$breakdownExpanded,
                        missingStatsMessage: statsUnavailableText)
                    Divider()
                    Text("Game stats").font(.headline.weight(.medium))
                    if let game = nflGame, let stats = game.player(matching: player), stats.hasUsableStats {
                        NFLPlayerBoxScoreView(player: stats, checkedAt: game.statsReceipt(for: player),
                            stale: game.statsAreStale(for: player, now: timeline.date), now: timeline.date)
                    } else if let stats = player.statLine?.trimmingCharacters(in: .whitespacesAndNewlines), !stats.isEmpty {
                        Text(stats).font(.body).textSelection(.enabled)
                            .accessibilityIdentifier("player-game-stats")
                    } else {
                        Text(statsUnavailableText)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("player-game-stats-unavailable")
                    }
                }
                .padding(18)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                Text("Fantasy points use your league’s scoring.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, BlitzMetrics.pagePadding).padding(.bottom, 24).readablePageWidth()
        }
        .pageBackground()
        .navigationTitle(player.name).navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("player-detail-\(player.id)")
        .refreshable {
            async let ownership: Void? = refreshOwnership?()
            async let nfl: Void = refreshNFL()
            async let games: Void = model.refreshScoringGames(week: context.week, force: true)
            if model.scores.week == context.week { await model.refreshScores() }
            else {
                refreshing = true
                defer { refreshing = false }
                do { refreshed = try await model.loadMatchupScores(week: context.week, refresh: true); failed = false }
                catch { if !Task.isCancelled, !MFLCoreError.isCancellation(error) { failed = true } }
            }
            _ = await (nfl, games, ownership)
        }
        .task(id: "nfl|\(scenePhase)|\(model.workspace?.season ?? 0)|\(context.week)") {
            guard scenePhase == .active, model.usesNFLStats, !model.isUsingCachedSession,
                  let season = model.workspace?.season else { return }
            await model.nflStats.poll(season: season, week: context.week, teams: [player.nflTeam], defenseTeams: NFLFeedGame.isDefense(player.position) ? [player.nflTeam] : [])
        }
        .task { await model.loadPlayerAvailability(week: context.week) }
        .playerJerseyMetadata(for: [player.id])
        .task(id: "\(scenePhase)|\(scoreboardIsPolling)") {
            guard scenePhase == .active else { return }
            await model.refreshScoringGames(week: context.week)
            // The Scores tab poller serves the selected week. A historical or
            // separately opened week owns one scoped read while this page is visible.
            guard !model.isDemo, !model.isUsingCachedSession,
                  model.scores.week != context.week || !scoreboardIsPolling else { return }
            repeat {
                refreshing = true
                do {
                    if model.scores.week == context.week { await model.refreshScores(silent: true) }
                    else { refreshed = try await model.loadMatchupScores(week: context.week, refresh: true) }
                    failed = false
                }
                catch { if !Task.isCancelled, !MFLCoreError.isCancellation(error) { failed = true } }
                refreshing = false
                do { try await Task.sleep(for: .seconds(ScoringRefreshCadence.interval(live: scores.isLive, currentWeek: context.week == model.currentWeek, failed: readFailed))) } catch { return }
                await model.refreshScoringGames(week: context.week)
            } while !Task.isCancelled
        }
      }
    }

    private var nflGame: NFLFeedGame? {
        guard model.usesNFLStats, let season = model.workspace?.season else { return nil }
        return model.nflStats.feed(season: season, week: context.week)?.game(team: player.nflTeam)
    }
    private var isFinal: Bool { nflGame?.isFinal ?? (player.gameState == .final) }
    private func refreshNFL() async {
        guard model.usesNFLStats, let season = model.workspace?.season else { return }
        await model.nflStats.refresh(season: season, week: context.week, force: true, teams: [player.nflTeam], defenseTeams: NFLFeedGame.isDefense(player.position) ? [player.nflTeam] : [])
    }
    private var statsUnavailableText: String {
        let status = model.nflDataStatus(players: [player], snapshot: scores, now: Date())
        if status.state == .delayed || status.state == .unavailable { return status.detail }
        guard model.usesNFLStats, model.nflStats.isConfigured, let season = model.workspace?.season else {
            return "A stat breakdown isn’t available for this game."
        }
        if model.nflStats.failed(season: season, week: context.week) { return "Game stats couldn’t refresh. Pull to try again." }
        if model.nflStats.feed(season: season, week: context.week)?.warming == true || model.nflStats.loading(season: season, week: context.week) {
            return "Loading game stats…"
        }
        return "Stats aren’t available for this player yet."
    }

    private var readFailed: Bool { failed || (model.scores.week == context.week && model.scoreRefreshError != nil) }

    private var scores: ScoresSnapshot {
        let candidates = [refreshed, model.scores.week == context.week ? model.scores : nil].compactMap { $0 }
        return candidates.filter { ($0.checkedAt ?? .distantPast) >= (context.checkedAt ?? .distantPast) }
            .max { ($0.checkedAt ?? .distantPast) < ($1.checkedAt ?? .distantPast) }
            ?? ScoresSnapshot(week: context.week, matchups: [], lastUpdated: context.checkedAt ?? .distantPast,
                isLive: context.player.gameState == .live, scorePrecision: context.precision, checkedAt: context.checkedAt)
    }
    private var player: MatchupPlayer {
        if let match = scores.matchups.first(where: { $0.id == context.matchupID }),
           let player = [match.away, match.home].first(where: { $0.id == context.teamID })?.players.first(where: { $0.id == context.player.id }) {
            return player
        }
        var player = context.player
        // A newer partial response must not relabel the tapped, older stats as fresh.
        if let checked = scores.checkedAt, checked > (context.checkedAt ?? .distantPast) {
            player.livePoints = nil; player.statLine = nil; player.gameSecondsRemaining = nil
        }
        return player
    }
    private var info: MatchupGameInfo {
        MatchupGameInfo(player: player, availability: model.playerTools.availability[context.week],
            scope: model.workspace?.storageScope, week: context.week, scoringGames: model.scoringGames[context.week], nflGame: nflGame)
    }
}
