import SwiftUI

/// Owns its scroll container. TeamDetailView supplies the fixed team header and
/// Roster / Schedule control above this view.
struct TeamScheduleView: View {
    @Environment(AppModel.self) private var app
    let franchiseID: String
    @State private var section = 0
    @State private var visitedCalendar = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Schedule", selection: $section) {
                Text("Matchups").tag(0)
                Text("Calendar").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)
                .accessibilityIdentifier("schedule-section")
            ZStack {
                ScheduleTimeline(franchiseID: franchiseID)
                    .opacity(section == 0 ? 1 : 0).allowsHitTesting(section == 0).accessibilityHidden(section != 0)
                if visitedCalendar, let calendar = app.leagueCalendar {
                    LeagueCalendarView(calendar: calendar, showsControls: section == 1)
                        .opacity(section == 1 ? 1 : 0).allowsHitTesting(section == 1).accessibilityHidden(section != 1)
                }
            }
        }.pageBackground()
            .onChange(of: section) { if section == 1 { visitedCalendar = true } }
    }
}

struct ScheduleTimeline: View {
    @Environment(AppModel.self) private var app
    @Environment(SeasonScheduleModel.self) private var schedule
    @Environment(\.scenePhase) private var scenePhase
    let franchiseID: String?

    @State private var showsEarlierWeeks = false
    @State private var scrollWeek: Int?
    @State private var teamError: String?

    private var snapshot: SeasonScheduleSnapshot? {
        guard let value = schedule.snapshot, let workspace = app.workspace,
              value.season == workspace.season, value.leagueID == workspace.leagueID else { return nil }
        return value
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if app.isDemo {
                    Label("Preview schedule · Sample matchups", systemImage: "sparkles")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if let snapshot {
                    controls(for: snapshot)
                    freshness(for: snapshot)
                    if !snapshot.weekIsConfirmed {
                        Label("MFL’s current week couldn’t be confirmed. The full schedule is shown.",
                              systemImage: "calendar.badge.exclamationmark")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if let message = schedule.errorMessage { errorLabel(message) }
                    if let teamError { errorLabel(teamError) }

                    if snapshot.weeks.allSatisfy({ $0.matchups.isEmpty }) {
                        ContentUnavailableView("No matchups published", systemImage: "calendar",
                            description: Text("MFL hasn’t returned head-to-head matchups for this season."))
                    } else {
                        let earlier = earlierWeeks(in: snapshot)
                        if !earlier.isEmpty {
                            DisclosureGroup(isExpanded: $showsEarlierWeeks) {
                                VStack(spacing: 16) {
                                    ForEach(earlier) { weekSection($0) }
                                }
                                .padding(.top, 12)
                            } label: {
                                Text("Earlier weeks").frame(minHeight: 44)
                            }
                            .font(.subheadline)
                            .tint(.secondary)
                            .accessibilityIdentifier("schedule-earlier-weeks")
                        }
                        ForEach(remainingWeeks(in: snapshot)) { week in
                            weekSection(week).id(week.week)
                        }
                        if hasUnsetPlayoffs(in: snapshot) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Playoffs").font(.headline)
                                Text(snapshot.hasRemainingWeeks
                                    ? "Playoff matchups have not been set."
                                    : "No playoff matchups are available.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            .accessibilityIdentifier("schedule-playoffs-unset")
                        }
                    }
                } else if schedule.isLoading {
                    ProgressView("Loading season schedule…")
                        .frame(maxWidth: .infinity).padding(.vertical, 44)
                } else {
                    ContentUnavailableView {
                        Label("Schedule unavailable", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text(schedule.errorMessage ?? "The season schedule hasn’t been loaded yet.")
                    } actions: {
                        Button { Task { await schedule.refresh() } } label: {
                            Text("Try again").frame(minHeight: 44)
                        }
                            .disabled(schedule.retryAfter.map { $0 > Date() } ?? false)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(BlitzMetrics.pagePadding)
            .padding(.bottom, 12)
            .readablePageWidth()
        }
        .scrollPosition(id: $scrollWeek, anchor: .top)
        .pageBackground()
        .accessibilityIdentifier(franchiseID.map { "team-schedule-\($0)" } ?? "league-season-schedule")
        .task(id: "\(app.workspace?.storageScope ?? "none")-\(scenePhase)") {
            guard scenePhase == .active else { return }
            async let timeline: Void = schedule.loadIfNeeded()
            if app.teams.isEmpty { await loadTeamMetadata() }
            await timeline
        }
        .refreshable {
            // Refresh identity metadata first so the repository's settings read
            // can reuse that result rather than launching duplicate forced reads.
            await loadTeamMetadata(force: true)
            await schedule.refresh()
        }
        .onChange(of: franchiseID) { _, _ in
            showsEarlierWeeks = false
            scrollWeek = nil
        }
    }

    @ViewBuilder
    private func controls(for snapshot: SeasonScheduleSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(snapshot.hasRemainingWeeks && snapshot.weekIsConfirmed ? "Rest of season" : "Season schedule")
                    .font(.headline)
                Spacer()
                scheduleNavigation
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.hasRemainingWeeks && snapshot.weekIsConfirmed ? "Rest of season" : "Season schedule")
                    .font(.headline)
                scheduleNavigation
            }
        }
    }

    @ViewBuilder
    private var scheduleNavigation: some View {
        if let scope = app.browseScope {
            if franchiseID != nil {
                NavigationLink(value: ScheduleRoute(scope: scope)) {
                    Label("League schedule", systemImage: "calendar")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .accessibilityIdentifier("open-league-schedule")
            } else {
                Menu {
                    ForEach(orderedTeams) { team in
                        NavigationLink(value: TeamRoute(scope: scope, franchiseID: team.id, initialSection: .schedule)) {
                            Text(team.id == app.workspace?.franchiseID ? "My Team · \(team.name)" : team.name)
                        }
                    }
                } label: {
                    Label("All teams", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .disabled(orderedTeams.isEmpty)
                .accessibilityIdentifier("schedule-team-picker")
            }
        }
    }

    private func freshness(for snapshot: SeasonScheduleSnapshot) -> some View {
        HStack(spacing: 6) {
            if schedule.isLoading { ProgressView().controlSize(.small) }
            if schedule.isLoading {
                Text("Updating schedule…")
            } else {
                TimelineView(.periodic(from: snapshot.fetchedAt, by: 60)) { context in
                    Text(ScheduleFreshness.label(updatedAt: snapshot.fetchedAt, now: context.date))
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "wifi.exclamationmark")
            .font(.footnote).foregroundStyle(.orange)
    }

    private func weekSection(_ week: SeasonScheduleWeek) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(week.week)").font(.headline)
                if week.isPlayoff { Text("Playoffs").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if week.week == snapshot?.currentWeek {
                    Text("This week").font(.caption).foregroundStyle(.secondary)
                }
            }
            if week.matchups.isEmpty {
                Text(franchiseID == nil ? "No matchups scheduled" : "No opponent scheduled")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("schedule-week-\(week.week)-empty")
            } else {
                ForEach(week.matchups) { matchup in
                    matchupRow(matchup)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-week-\(week.week)")
    }

    @ViewBuilder
    private func matchupRow(_ matchup: SeasonScheduleMatchup) -> some View {
        if let scope = app.browseScope, matchup.canOpenMatchup {
            NavigationLink(value: MatchupRoute(scope: scope, week: matchup.week, matchupID: matchup.id)) {
                rowContents(matchup, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this week’s matchup")
            .accessibilityIdentifier("schedule-matchup-\(matchup.id)")
        } else {
            rowContents(matchup, showsChevron: false)
                .accessibilityIdentifier("schedule-matchup-\(matchup.id)")
        }
    }

    private func rowContents(_ matchup: SeasonScheduleMatchup, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            if let franchiseID {
                teamMatchupContents(matchup, franchiseID: franchiseID)
            } else {
                leagueMatchupContents(matchup)
            }
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: BlitzMetrics.compactCornerRadius))
        .overlay {
            if franchiseID == nil, let owner = app.workspace?.franchiseID, matchup.includes(franchiseID: owner) {
                RoundedRectangle(cornerRadius: BlitzMetrics.compactCornerRadius)
                    .strokeBorder(Color.blitzGreen.opacity(0.6), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func teamMatchupContents(_ matchup: SeasonScheduleMatchup, franchiseID: String) -> some View {
        let opponents = matchup.participants.filter { $0.franchiseID != franchiseID }
        return HStack(spacing: 10) {
            if let opponent = opponents.first, !opponent.isExplicitBye, let team = team(opponent.franchiseID) {
                TeamMark(abbreviation: team.abbreviation, seed: team.accentSeed, size: 38, artworkURLs: team.artworkURLs)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(opponents.isEmpty ? "Opponent not set" : opponents.map { name($0) }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if let opponent = opponents.first, !opponent.isExplicitBye,
                   let standing = app.standings.first(where: { $0.id == opponent.franchiseID }) {
                    Text("Current record · \(standing.wins)–\(standing.losses)\(standing.ties > 0 ? "–\(standing.ties)" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(matchup.isExplicitBye ? "Bye week" : matchup.state.label)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if matchup.state == .completed, matchup.hasReportedScores,
               let own = matchup.participants.first(where: { $0.franchiseID == franchiseID })?.score,
               let other = opponents.first?.score {
                VStack(alignment: .trailing, spacing: 3) {
                    if let result = matchup.result(for: franchiseID) { Text(result.rawValue).font(.caption.bold()) }
                    Text("\(points(own))–\(points(other))").font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func leagueMatchupContents(_ matchup: SeasonScheduleMatchup) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(matchup.participants.enumerated()), id: \.offset) { _, participant in
                HStack(spacing: 8) {
                    if let team = team(participant.franchiseID) {
                        TeamMark(abbreviation: team.abbreviation, seed: team.accentSeed, size: 28, artworkURLs: team.artworkURLs)
                    }
                    Text(name(participant)).font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if matchup.state == .completed, let score = participant.score {
                        Text(points(score)).font(.subheadline.monospacedDigit())
                    }
                }
            }
            HStack(spacing: 5) {
                if let owner = app.workspace?.franchiseID, matchup.includes(franchiseID: owner) {
                    Text("Your matchup ·")
                }
                Text(matchup.isExplicitBye ? "Bye week" : matchup.state.label)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func points(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.pointsText(precision: app.scores.scorePrecision)
    }

    private func name(_ participant: SeasonScheduleParticipant) -> String {
        participant.isExplicitBye ? "Bye" : team(participant.franchiseID)?.name ?? "Team \(participant.franchiseID)"
    }

    private func team(_ id: String) -> TeamSummary? {
        if let team = app.teams.first(where: { $0.id == id }) { return team }
        guard let standing = app.standings.first(where: { $0.id == id }) else { return nil }
        return TeamSummary(id: standing.id, name: standing.name, abbreviation: standing.abbreviation,
                           ownerName: standing.ownerName, artworkURLs: standing.artworkURLs, accentSeed: standing.accentSeed)
    }

    private var orderedTeams: [TeamSummary] {
        let teams = app.teams.isEmpty ? app.standings.compactMap { team($0.id) } : app.teams
        let owner = app.workspace?.franchiseID
        return teams.sorted {
            if ($0.id == owner) != ($1.id == owner) { return $0.id == owner }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func earlierWeeks(in snapshot: SeasonScheduleSnapshot) -> [SeasonScheduleWeek] {
        guard snapshot.weekIsConfirmed, let first = snapshot.firstUpcomingWeek else { return [] }
        return snapshot.filteredWeeks(franchiseID: franchiseID).filter { $0.week < first }
    }

    private func remainingWeeks(in snapshot: SeasonScheduleSnapshot) -> [SeasonScheduleWeek] {
        let first = snapshot.weekIsConfirmed ? snapshot.firstUpcomingWeek : nil
        let omitEmptyPlayoffs = hasUnsetPlayoffs(in: snapshot)
        return snapshot.filteredWeeks(franchiseID: franchiseID).filter { week in
            (first.map { week.week >= $0 } ?? true) && !(omitEmptyPlayoffs && week.isPlayoff)
        }
    }

    private func hasUnsetPlayoffs(in snapshot: SeasonScheduleSnapshot) -> Bool {
        let playoffs = snapshot.weeks.filter(\.isPlayoff)
        return !playoffs.isEmpty && playoffs.allSatisfy { $0.matchups.isEmpty }
    }

    private func loadTeamMetadata(force: Bool = false) async {
        do {
            _ = try await app.loadTeams(refresh: force)
            teamError = nil
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            teamError = "Some team details couldn’t be refreshed."
        }
    }
}
