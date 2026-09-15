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
            let freshness = ScoreFreshness(snapshot: liveReceipt?.snapshot ?? snapshot, failed: failed, saved: saved, preview: model.isDemo, now: context.date)
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        heading
                        Spacer(minLength: 8)
                        state(freshness)
                    }
                    VStack(alignment: .leading, spacing: 4) { heading; state(freshness) }
                }
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        identity(matchup.away, trailing: false)
                        metrics(matchup.away, trailing: false, freshness: freshness, now: context.date)
                        identity(matchup.home, trailing: false)
                        metrics(matchup.home, trailing: false, freshness: freshness, now: context.date)
                    }
                } else {
                    // Shared rows keep score baselines equal even when only
                    // one team name or owner needs a second line.
                    VStack(spacing: 10) {
                        alignedIdentities
                        HStack(alignment: .top, spacing: 20) {
                            metrics(matchup.away, trailing: false, freshness: freshness, now: context.date)
                            metrics(matchup.home, trailing: true, freshness: freshness, now: context.date)
                        }
                    }
                }
            }
            .padding(16)
            .foregroundStyle(.white)
            .background(Color(red: 0.035, green: 0.094, blue: 0.17), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var heading: some View {
        Text(featured ? "YOUR MATCHUP" : (model.isDemo ? "PREVIEW MATCHUP" : "MATCHUP"))
            .font(.caption.weight(.medium)).foregroundStyle(Color.blitzGreen)
    }
    private func state(_ freshness: ScoreFreshness) -> some View {
        GameStateLabel(text: ScoringGamePresentation.label(for: liveReceipt?.matchup ?? matchup, stale: freshness.qualifiesGameState),
            live: (liveReceipt?.matchup ?? matchup).status.isLive && !freshness.qualifiesGameState, onDark: true)
    }

    private func metrics(_ team: MatchupTeam, trailing: Bool, freshness: ScoreFreshness, now: Date) -> some View {
        let receipt = liveReceipt
        let displayedTeam = receipt.map { team.id == matchup.home.id ? $0.matchup.home : $0.matchup.away } ?? team
        let projection = receipt?.projection(home: team.id == matchup.home.id, stale: freshness.qualifiesGameState)
            ?? ScoringGamePresentation.projection(for: team, in: matchup, stale: freshness.qualifiesGameState)
        return VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            Text("Points").font(.caption2).foregroundStyle(ScoringStyle.heroSecondary)
            ScoreValue(points: displayedTeam.reportedScore, projection: projection.points, precision: snapshot.scorePrecision,
                font: .largeTitle.weight(.medium), alignment: trailing ? .trailing : .leading, onDark: true, pregame: true,
                liveEstimate: projection.isLiveEstimate, showProjection: projection.isVisible,
                change: freshness.qualifiesGameState ? nil : model.scoringChanges.change(for: .init(matchupID: matchup.id, teamID: team.id), now: now), compact: true)
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 0 : 16)
            if !freshness.qualifiesGameState, receipt == nil {
                remaining(team, now: now)
            }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .accessibilityIdentifier("hero-metrics-\(team.id)")
    }

    @ViewBuilder private func remaining(_ team: MatchupTeam, now: Date) -> some View {
        let grouped = MatchupModeTeam(team: team, week: snapshot.week, scope: model.workspace?.storageScope,
            feed: model.workspace.flatMap { model.usesNFLStats ? model.nflStats.feed(season: $0.season, week: snapshot.week) : nil },
            availability: model.playerTools.availability[snapshot.week], scoringGames: model.scoringGames[snapshot.week], now: now)
        if !grouped.entries.isEmpty, !grouped.hasUnclassifiedPlayers, grouped.entries(in: .unavailable).isEmpty,
           grouped.entries.contains(where: { $0.section != .completed }) {
            Text("\(grouped.entries(in: .inProgress).count) playing · \(grouped.entries(in: .upcoming).count) to play")
                .font(.caption).foregroundStyle(ScoringStyle.heroSecondary)
            if grouped.entries(in: .inProgress).isEmpty, let next = grouped.nextKickoff {
                Text(next, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.caption).foregroundStyle(ScoringStyle.heroSecondary)
            }
        }
    }

    private var alignedIdentities: some View {
        VStack(spacing: 3) {
            HStack(alignment: .top, spacing: 20) {
                identity(matchup.away, trailing: false, nameOnly: true)
                identity(matchup.home, trailing: true, nameOnly: true)
            }
            if ownerName(matchup.away) != nil || ownerName(matchup.home) != nil {
                HStack(alignment: .top, spacing: 20) {
                    owner(matchup.away).padding(.leading, 35).frame(maxWidth: .infinity, alignment: .leading)
                    owner(matchup.home).padding(.trailing, 35).frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
            }
            if recordText(matchup.away) != nil || recordText(matchup.home) != nil {
                HStack(alignment: .top, spacing: 20) {
                    record(matchup.away).padding(.leading, 35).frame(maxWidth: .infinity, alignment: .leading)
                    record(matchup.home).padding(.trailing, 35).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
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

    @ViewBuilder private func identity(_ team: MatchupTeam, trailing: Bool, nameOnly: Bool = false) -> some View {
        if teamLinks, let scope = model.browseScope {
            NavigationLink(value: TeamRoute(scope: scope, franchiseID: team.id)) { identityContent(team, trailing: trailing, nameOnly: nameOnly) }
                .buttonStyle(.plain).accessibilityIdentifier("matchup-team-\(team.id)")
        } else { identityContent(team, trailing: trailing, nameOnly: nameOnly) }
    }
    private func identityContent(_ team: MatchupTeam, trailing: Bool, nameOnly: Bool) -> some View {
        HStack(alignment: .top, spacing: 7) {
            if !trailing { mark(team) }
            VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
                Text(team.name).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                if !nameOnly {
                    if ownerName(team) != nil { owner(team) }
                    if recordText(team) != nil { record(team) }
                }
            }
            .multilineTextAlignment(trailing ? .trailing : .leading)
            if trailing { mark(team) }
        }
        .frame(maxWidth: .infinity, minHeight: nameOnly ? 28 : 44, alignment: trailing ? .topTrailing : .topLeading)
    }
    private func mark(_ team: MatchupTeam) -> some View {
        TeamMark(abbreviation: team.abbreviation, seed: team.accentSeed, size: 28, artworkURLs: team.artworkURLs)
    }
}
