import SwiftUI
import UIKit

struct AppTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = initialTab
    @State private var teamTabImage: UIImage?
    @State private var deepLink: LeagueDeepLink?
    @State private var scoresPath = NavigationPath()

    private static var initialTab: Tab {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-transaction-activity") { return .myTeam }
        if ProcessInfo.processInfo.arguments.contains("--show-standings") { return .standings }
        #endif
        return .scores
    }

    enum Tab: Hashable {
        case scores
        case lineup
        case myTeam
        case standings
        case board
    }

    var body: some View {
        TabView(selection: $selection) {
            LeagueBrowseStack(path: $scoresPath) { ScoresView() }
                .tabItem { Label("Scores", systemImage: "sportscourt.fill") }
                .tag(Tab.scores)

            LeagueBrowseStack { LineupView() }
                .tabItem { Label("Lineup", image: "LineupPlay") }
                .tag(Tab.lineup)

            LeagueBrowseStack { MyTeamRootView() }
                .tabItem {
                    Label {
                        Text("My Team")
                    } icon: {
                        if let teamTabImage {
                            Image(uiImage: teamTabImage).renderingMode(.original)
                        } else {
                            Image(systemName: "shield.lefthalf.filled")
                        }
                    }
                }
                .tag(Tab.myTeam)
                .badge(model.transactions.needsAttentionCount)

            LeagueBrowseStack { StandingsView() }
                .tabItem { Label("Standings", systemImage: "list.number") }
                .tag(Tab.standings)

            LeagueBrowseStack { BoardView() }
                .tabItem { Label("Board", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.board)
                .badge(model.boardThreads.filter(\.isUnread).count)
        }
        .id(model.browseScope)
        .onChange(of: model.browseScope) { scoresPath = NavigationPath(); deepLink = nil }
        .environment(model.seasonSchedule)
        .onChange(of: LeagueDeepLinkRouter.shared.pending) {
            guard let route = LeagueDeepLinkRouter.shared.pending, !model.isUsingCachedSession else { return }
            LeagueDeepLinkRouter.shared.pending = nil
            guard route.scope == model.workspace?.storageScope else {
                model.notice = .error("This link belongs to a different league or season. Open its league to view it."); return
            }
            openDeepLink(route)
        }
        .task(id: model.isUsingCachedSession) {
            if let route = LeagueDeepLinkRouter.shared.pending, !model.isUsingCachedSession {
                LeagueDeepLinkRouter.shared.pending = nil
                if route.scope == model.workspace?.storageScope { openDeepLink(route) }
            }
        }
        .sheet(item: $deepLink) { route in
            LeagueDeepLinkDestination(route: route)
        }
        .onChange(of: model.scores) {
            guard scenePhase == .active else { return }
            Task { await model.updateMatchupActivity() }
        }
        .task(id: "\(scenePhase)|\(model.isUsingCachedSession)|\(model.isLoadingScores)|\(model.isLoadingLineup)") {
            guard scenePhase == .active, !model.isUsingCachedSession, !model.isLoadingScores, !model.isLoadingLineup else { return }
            await model.updateMatchupActivity()
            await model.leagueCalendar?.refreshForForeground()
        }
        .task(id: "\(model.workspace?.storageScope ?? "none")|\(model.isUsingCachedSession)") {
            // Identity metadata is cacheable and must not hold up account entry.
            guard !model.isUsingCachedSession else { return }
            _ = try? await model.loadTeams()
        }
        .environment(\.scoreboardIsPolling, selection == .scores && model.scopedScoreInspection == nil)
        .task(id: "alerts|\(scenePhase)|\(model.workspace?.storageScope ?? "")|\(model.lineup.week)|\(model.isLoadingLineup)|\(LineupPushToken.shared.token ?? "")|\(LineupPushToken.shared.failed)") {
            guard scenePhase == .active else { return }
            await model.lineupAlerts.reconcile(model:model)
        }
        .task(id: artworkKey) {
            let key = artworkKey
            teamTabImage = TeamTabArtwork.image(abbreviation: key.abbreviation)
            guard let image = await TeamArtworkLoader.shared.image(for: key.urls),
                  !Task.isCancelled, key == artworkKey else { return }
            teamTabImage = TeamTabArtwork.image(abbreviation: key.abbreviation, artwork: image)
        }
        .task(id: "foreground|\(scenePhase)|\(selection)") {
            guard scenePhase == .active else { return }
            let section: AppModel.ForegroundSection = switch selection {
            case .scores: .scores; case .lineup: .lineup; case .myTeam: .myTeam
            case .standings: .standings; case .board: .board
            }
            await model.refreshForForeground(section: section)
        }
        .task(id: "\(selection)|\(model.isLoadingScores)|\(model.isLoadingLineup)|\(model.isUsingCachedSession)|\(scenePhase)") {
            guard scenePhase == .active, selection == .myTeam, !model.isUsingCachedSession,
                  !model.isLoadingScores, !model.isLoadingLineup else { return }
            await model.transactions.refreshInbox()
        }
        .task(id: "\(scenePhase)-\(selection)-\(model.selectedWeek)-\(model.scopedScoreInspection?.uuidString ?? "scoreboard")") {
            guard scenePhase == .active, !model.isDemo else { return }
            // One foreground-only poller serves the scoreboard and its drill-down.
            // Keep polling finals for MFL corrections; no background timer.
            if selection == .scores, model.scopedScoreInspection == nil { await model.refreshScoresOnEntry() }
            while !Task.isCancelled {
                let interval = ScoringRefreshCadence.interval(live: model.scores.isLive,
                    currentWeek: model.selectedWeek == model.currentWeek, failed: model.scoreRefreshError != nil)
                do { try await Task.sleep(for: .seconds(interval + Double.random(in: 0...3))) } catch { return }
                guard !Task.isCancelled else { return }
                if selection == .scores, model.scopedScoreInspection == nil {
                    await model.refreshScores(silent: true)
                }
                if model.matchupActivity.enabled,
                   selection != .scores || model.selectedWeek != model.currentWeek || model.scopedScoreInspection != nil {
                    await model.refreshMatchupActivity()
                }
            }
        }
    }

    private func openDeepLink(_ route: LeagueDeepLink) {
        switch route.destination {
        case .matchup(let week, let id):
            guard let scope = model.browseScope else { return }
            deepLink = nil
            selection = .scores
            scoresPath = NavigationPath([LiveMatchupRoute(scope: scope, week: week, matchupID: id)])
        case .lineup(let week):
            deepLink=nil;selection = .lineup
            Task { await model.changeWeek(to:week);await model.refreshLineup() }
        case .calendar:
            deepLink = route
        }
    }

    private var artworkKey: ArtworkKey {
        let team = model.teams.first { $0.id == model.workspace?.franchiseID }
        let standing = model.standings.first { $0.id == model.workspace?.franchiseID }
        return ArtworkKey(scope: model.browseScope,
                          abbreviation: team?.abbreviation ?? standing?.abbreviation ?? "MY",
                          urls: model.isDemo ? [] : (team?.artworkURLs ?? standing?.artworkURLs ?? []))
    }

    private struct ArtworkKey: Hashable {
        let scope: LeagueBrowseScope?
        let abbreviation: String
        let urls: [URL]
    }
}

private struct LeagueDeepLinkDestination: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let route: LeagueDeepLink
    var body: some View {
        LeagueBrowseStack {
            Group {
                if route.scope == model.workspace?.storageScope, let scope = model.browseScope, !model.isUsingCachedSession {
                    switch route.destination {
                    case .lineup: LineupView()
                    case .calendar(let id):
                        if let calendar = model.leagueCalendar { LeagueCalendarEventView(calendar: calendar, eventID: id) }
                    case .matchup(let week, let id):
                        LiveMatchupDestination(route: LiveMatchupRoute(scope: scope, week: week, matchupID: id))
                    }
                } else { ContentUnavailableView("Reconnect your league", systemImage: "person.crop.circle") }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

private struct MyTeamRootView: View {
    @Environment(AppModel.self) private var model
    @State private var showingInitialActivity = false
    @State private var handledInitialDestination = false
    @State private var showingSettings = false

    var body: some View {
        Group {
            if let ownerID = model.workspace?.franchiseID {
                TeamDetailView(franchiseID: ownerID) { TeamScheduleView(franchiseID: $0) }
            } else {
                ContentUnavailableView("Connect your team", systemImage: "shield.lefthalf.filled")
            }
        }
        .navigationDestination(isPresented: $showingInitialActivity) {
            TransactionActivityView().environment(model.transactions)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
                    .accessibilityIdentifier("my-team-settings")
            }
        }
        .playerSearch()
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .task {
            guard !handledInitialDestination else { return }
            handledInitialDestination = true
            #if DEBUG
            showingInitialActivity = ProcessInfo.processInfo.arguments.contains("--show-transaction-activity")
            #endif
        }
    }
}
