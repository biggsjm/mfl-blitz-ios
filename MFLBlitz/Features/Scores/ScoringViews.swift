import SwiftUI

struct ScoringDisplayContext {
    var matchupID = ""
    var freshness = ScoreFreshness(snapshot: ScoresSnapshot(week: 1, matchups: [], lastUpdated: .distantPast, isLive: false))
}

private struct ScoringContextKey: EnvironmentKey {
    static let defaultValue = ScoringDisplayContext()
}
extension EnvironmentValues {
    var scoringContext: ScoringDisplayContext {
        get { self[ScoringContextKey.self] }
        set { self[ScoringContextKey.self] = newValue }
    }
}

struct ScoreFreshnessLabel: View {
    let snapshot: ScoresSnapshot
    var refreshing = false
    var failed = false
    var offline = false
    var saved = false
    var preview = false
    @State private var showInfo = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let freshness = ScoreFreshness(snapshot: snapshot, refreshing: refreshing, failed: failed,
                offline: offline, saved: saved, preview: preview, now: context.date)
            Button { showInfo = true } label: {
                HStack(spacing: 6) {
                    if refreshing { ProgressView().controlSize(.mini) }
                    else if freshness.isWarning { Image(systemName: offline ? "wifi.slash" : "clock.badge.exclamationmark") }
                    Text(freshness.label(now: context.date))
                    Image(systemName: "info.circle").accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(freshness.isWarning ? ScoringStyle.negative : Color.secondary)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("score-freshness")
            .popover(isPresented: $showInfo) {
                Text("Checked means the app received a scoring response from MFL. MFL may lag behind the game. Live est. adds points already scored to each starter’s pregame projection for their remaining game time. It assumes an even scoring rate and does not account for injuries or game situation. Missing or stale data leaves the estimate unavailable. NFL game scores have a separate check time. ~Q is an approximate regulation quarter and clock calculated from MFL’s remaining game time; quarter breaks, halftime, and overtime are not identified. Player projections remain pregame estimates; changes compare points with the previous check.")
                    .font(.subheadline).padding().frame(idealWidth: 280)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct GameStateLabel: View {
    let text: String
    var live = false
    var onDark = false
    var body: some View {
        HStack(spacing: 5) {
            if live { Circle().fill(onDark ? Color.blitzGreen : ScoringStyle.positive).frame(width: 5, height: 5).accessibilityHidden(true) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(live ? (onDark ? Color.blitzGreen : ScoringStyle.positive) : (onDark ? ScoringStyle.heroSecondary : Color.secondary))
    }
}

struct ScoreValue: View {
    let points: Double?
    let projection: Double?
    let precision: Int
    var font: Font = .title2.weight(.medium)
    var alignment: HorizontalAlignment = .trailing
    var onDark = false
    var pregame = false
    var liveEstimate = false
    var showProjection = true
    var change: ScoringChange? = nil
    // Compact rows provide a symmetric gutter for the badge outside the
    // score/projection block, so that block can align with the team identity.
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var badgeHeight = 13
    @State private var now = Date()

    private var overlaysBadge: Bool { compact && !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(points.flatMap { $0.isFinite ? $0.pointsText(precision: precision) : nil } ?? "—")
                .font(font).monospacedDigit().fixedSize()
                .foregroundStyle(onDark ? Color.white : Color.primary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .accessibilityLabel(points.map { "\($0.pointsText(precision: precision)) points" } ?? "Points not reported")
            if showProjection {
                ProjectionCaption(text: projection.flatMap { $0.isFinite ? $0.pointsText : nil } ?? "—", pregame: pregame,
                    onDark: onDark, liveEstimate: liveEstimate)
            }
            if !overlaysBadge { changeBadge }
        }
        .padding(.vertical, 2)
        .overlay(alignment: alignment == .leading ? .bottomLeading : .bottomTrailing) {
            if overlaysBadge { changeBadge.offset(y: badgeHeight + 2) }
        }
        .background {
            if let change, !reduceMotion, now.timeIntervalSince(change.date) < 2 {
                RoundedRectangle(cornerRadius: 6)
                    .fill((change.difference > 0 ? ScoringStyle.positive : ScoringStyle.negative).opacity(0.12))
                    .padding(-4)
            }
        }
        .task(id: change?.id) {
            now = Date()
            guard let change else { return }
            for age: TimeInterval in [2, 60] {
                let wait = change.date.addingTimeInterval(age).timeIntervalSinceNow
                if wait > 0 {
                    do { try await Task.sleep(for: .seconds(wait)) } catch { return }
                }
                now = Date()
            }
        }
    }

    private var changeBadge: some View {
        ZStack(alignment: alignment == .leading ? .leading : .trailing) {
            Text("↑ +0.0").hidden().accessibilityHidden(true)
            if let change, now.timeIntervalSince(change.date) < 60 {
                Label(change.signedText, systemImage: change.difference > 0 ? "arrow.up" : "arrow.down")
                    .foregroundStyle(change.difference > 0 ? (onDark ? Color.blitzGreen : ScoringStyle.positive) : ScoringStyle.negative)
                    .accessibilityLabel("\(change.signedText) points since the previous check")
            }
        }
        .font(.caption2.weight(.medium)).monospacedDigit().frame(height: badgeHeight)
    }
}

struct RecentScoringChanges: View {
    @Environment(AppModel.self) private var model
    var matchupID: String? = nil
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let changes = model.scoringChanges.recent(matchupID: matchupID, now: context.date)
            if !changes.isEmpty {
                DisclosureGroup("Recent scoring changes · \(changes.count)") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(changes) { change in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(change.name).font(.subheadline.weight(.medium))
                                Text("\(change.previous.pointsText(precision: change.precision)) → \(change.current.pointsText(precision: change.precision)) points · \(ScoreFreshness.age(change.date, now: context.date))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.top, 10)
                }
                .font(.subheadline).tint(.primary).padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("recent-scoring-changes")
            }
        }
    }
}

/// Same hierarchy on the league page and inside the two-team comparison.
struct ScoringMatchupHero: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let matchup: Matchup
    let snapshot: ScoresSnapshot
    var failed = false
    var saved = false
    var featured = false
    var teamLinks = false

    private var liveReceipt: ScoringLiveReceipt? {
        ScoringLiveReceipt(matchup: matchup, snapshot: snapshot,
            state: model.matchupActivity.latestScoreState(matchup: matchup, scope: model.workspace?.storageScope, week: snapshot.week))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let receipt = liveReceipt
            let displayed = receipt?.matchup ?? matchup
            let freshness = ScoreFreshness(snapshot: receipt?.snapshot ?? snapshot, failed: failed, saved: saved, preview: model.isDemo, now: context.date)
            let awayProjection = projection(matchup.away, receipt: receipt, freshness: freshness)
            let homeProjection = projection(matchup.home, receipt: receipt, freshness: freshness)
            let showsProjection = awayProjection.isVisible || homeProjection.isVisible
            let projectionHeading = awayProjection.isLiveEstimate || homeProjection.isLiveEstimate ? "Live est." : "Proj."
            let awayProgress = progress(matchup.away, receipt: receipt, freshness: freshness, now: context.date)
            let homeProgress = progress(matchup.home, receipt: receipt, freshness: freshness, now: context.date)
            VStack(alignment: .leading, spacing: 0) {
                if dynamicTypeSize >= .xxLarge {
                    accessibleRow(displayed.away, projection: awayProjection, progress: awayProgress, freshness: freshness, now: context.date)
                    rule
                    accessibleRow(displayed.home, projection: homeProjection, progress: homeProgress, freshness: freshness, now: context.date)
                } else {
                    // One grid keeps both numeric columns aligned, including
                    // long team names and scores with different digit counts.
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                        GridRow {
                            Text(featured ? "Your matchup" : "Team")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Points").gridColumnAlignment(.trailing)
                            if showsProjection { Text(projectionHeading).gridColumnAlignment(.trailing) }
                        }
                        .font(.caption2).foregroundStyle(ScoringStyle.heroSecondary)
                        .padding(.bottom, 2)
                        compactRow(displayed.away, projection: awayProjection, showsProjection: showsProjection,
                            progress: awayProgress, freshness: freshness, now: context.date)
                        rule.gridCellUnsizedAxes(.horizontal)
                        compactRow(displayed.home, projection: homeProjection, showsProjection: showsProjection,
                            progress: homeProgress, freshness: freshness, now: context.date)
                    }
                }
                rule
                footer(displayed, freshness: freshness, away: awayProgress, home: homeProgress, now: context.date)
                    .frame(maxWidth: .infinity).padding(.top, 10)
            }
            .padding(16)
            .foregroundStyle(.white)
            .background(Color(red: 0.035, green: 0.094, blue: 0.17), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var rule: some View {
        Rectangle().fill(.white.opacity(0.13)).frame(height: 0.5).accessibilityHidden(true)
    }

    private func projection(_ team: MatchupTeam, receipt: ScoringLiveReceipt?, freshness: ScoreFreshness) -> ScoringGamePresentation.Projection {
        receipt?.projection(home: team.id == matchup.home.id, stale: freshness.qualifiesGameState)
            ?? ScoringGamePresentation.projection(for: team, in: matchup, stale: freshness.qualifiesGameState)
    }

    private func compactRow(_ team: MatchupTeam, projection: ScoringGamePresentation.Projection, showsProjection: Bool,
                            progress: MatchupModeTeam?, freshness: ScoreFreshness, now: Date) -> some View {
        GridRow {
            identity(team, progress: progress)
            points(team, freshness: freshness, now: now)
            if showsProjection { projectionValue(projection).font(.subheadline) }
        }
        .padding(.vertical, 12)
    }

    private func accessibleRow(_ team: MatchupTeam, projection: ScoringGamePresentation.Projection,
                               progress: MatchupModeTeam?, freshness: ScoreFreshness, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            identity(team, progress: progress)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    labeledPoints(team, freshness: freshness, now: now)
                    if projection.isVisible { labeledProjection(projection) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    labeledPoints(team, freshness: freshness, now: now)
                    if projection.isVisible { labeledProjection(projection) }
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func points(_ team: MatchupTeam, freshness: ScoreFreshness, now: Date) -> some View {
        ScoreValue(points: team.reportedScore, projection: nil, precision: snapshot.scorePrecision,
            font: .title2.weight(.semibold), onDark: true, showProjection: false,
            change: freshness.qualifiesGameState ? nil : model.scoringChanges.change(for: .init(matchupID: matchup.id, teamID: team.id), now: now), compact: dynamicTypeSize < .xxLarge)
        .accessibilityIdentifier("hero-metrics-\(team.id)")
    }

    private func labeledPoints(_ team: MatchupTeam, freshness: ScoreFreshness, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Points").font(.caption).foregroundStyle(ScoringStyle.heroSecondary)
            points(team, freshness: freshness, now: now)
        }
    }

    private func labeledProjection(_ projection: ScoringGamePresentation.Projection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(projection.isLiveEstimate ? "Live est." : "Proj.").font(.caption).foregroundStyle(ScoringStyle.heroSecondary)
            projectionValue(projection).font(.title3)
        }
    }

    private func projectionValue(_ projection: ScoringGamePresentation.Projection) -> some View {
        let text = projection.points.flatMap { $0.isFinite ? $0.pointsText : nil } ?? "—"
        return Text(text).monospacedDigit().fixedSize()
            .foregroundStyle(ScoringStyle.heroProjection)
            .accessibilityLabel("\(projection.isLiveEstimate ? "Estimated final score" : "Pregame projection"), \(text == "—" ? "unavailable" : text + " points")")
    }

    private func progress(_ team: MatchupTeam, receipt: ScoringLiveReceipt?, freshness: ScoreFreshness, now: Date) -> MatchupModeTeam? {
        guard !freshness.qualifiesGameState, receipt == nil, matchup.status != .final else { return nil }
        let grouped = MatchupModeTeam(team: team, week: snapshot.week, scope: model.workspace?.storageScope,
            feed: model.workspace.flatMap { model.usesNFLStats ? model.nflStats.feed(season: $0.season, week: snapshot.week) : nil },
            availability: model.playerTools.availability[snapshot.week], scoringGames: model.scoringGames[snapshot.week], now: now)
        guard !grouped.entries.isEmpty, !grouped.hasUnclassifiedPlayers, grouped.entries(in: .unavailable).isEmpty else { return nil }
        return grouped
    }

    private func remainingText(_ progress: MatchupModeTeam?) -> String? {
        guard let progress else { return nil }
        let playing = progress.entries(in: .inProgress).count
        let upcoming = progress.entries(in: .upcoming).count
        if playing > 0 { return upcoming > 0 ? "\(playing) playing · \(upcoming) to play" : "\(playing) playing" }
        return upcoming > 0 ? "\(upcoming) to play" : nil
    }

    @ViewBuilder private func footer(_ displayed: Matchup, freshness: ScoreFreshness,
                                     away: MatchupModeTeam?, home: MatchupModeTeam?, now: Date) -> some View {
        if let away, let home,
           away.entries(in: .inProgress).isEmpty, home.entries(in: .inProgress).isEmpty,
           let next = [away.nextKickoff, home.nextKickoff].compactMap({ $0 }).min(), next > now {
            let started = away.entries.contains { $0.section == .completed } || home.entries.contains { $0.section == .completed }
            Text("\(started ? "Next" : "Starts") \(next, format: .dateTime.weekday(.abbreviated).hour().minute())")
                .font(.caption).foregroundStyle(ScoringStyle.heroSecondary)
                .accessibilityIdentifier("matchup-next-kickoff")
        } else {
            GameStateLabel(text: ScoringGamePresentation.label(for: displayed, stale: freshness.qualifiesGameState),
                live: displayed.status.isLive && !freshness.qualifiesGameState, onDark: true)
        }
    }

    private func ownerName(_ team: MatchupTeam) -> String? {
        TeamPlayerMapper.text(model.teams.first { $0.id == team.id }?.ownerName
            ?? model.standings.first { $0.id == team.id }?.ownerName)
    }

    private func recordText(_ team: MatchupTeam) -> String? {
        model.standings.first { $0.id == team.id }?.recordText
    }

    private func owner(_ team: MatchupTeam) -> some View {
        Text(ownerName(team) ?? "").font(.caption).foregroundStyle(ScoringStyle.heroSecondary)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("matchup-owner-\(team.id)")
    }

    private func record(_ team: MatchupTeam) -> some View {
        Text(recordText(team) ?? "").font(.caption).monospacedDigit().foregroundStyle(ScoringStyle.heroSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(recordText(team).map { "Current record, \($0)" } ?? "")
            .accessibilityIdentifier("matchup-record-\(team.id)")
    }

    @ViewBuilder private func identity(_ team: MatchupTeam, progress: MatchupModeTeam?) -> some View {
        if teamLinks, let scope = model.browseScope {
            NavigationLink(value: TeamRoute(scope: scope, franchiseID: team.id)) { identityContent(team, progress: progress) }
                .buttonStyle(.plain).accessibilityIdentifier("matchup-team-\(team.id)")
        } else { identityContent(team, progress: progress) }
    }
    private func identityContent(_ team: MatchupTeam, progress: MatchupModeTeam?) -> some View {
        HStack(spacing: 9) {
            TeamMark(abbreviation: team.abbreviation, seed: team.accentSeed, size: 32, artworkURLs: team.artworkURLs)
            VStack(alignment: .leading, spacing: 3) {
                Text(team.name).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                if ownerName(team) != nil { owner(team) }
                // Keep the record readable when playing/to-play counts wrap.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if recordText(team) != nil { record(team).fixedSize() }
                    if let remaining = remainingText(progress) {
                        if recordText(team) != nil { Text("·").accessibilityHidden(true) }
                        Text(remaining).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.caption).foregroundStyle(ScoringStyle.heroSecondary)
            }
            .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }
}
