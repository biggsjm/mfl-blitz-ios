import SwiftUI
import UIKit

struct AppTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = initialTab
    @State private var teamTabImage: UIImage?
    @State private var deepLink: LeagueDeepLink?

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
            LeagueBrowseStack { ScoresView() }
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

            NavigationStack { BoardView() }
                .tabItem { Label("Board", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.board)
                .badge(model.boardThreads.filter(\.isUnread).count)
        }
        .id(model.browseScope)
        .environment(model.seasonSchedule)
        .onChange(of: LeagueDeepLinkRouter.shared.pending) {
            guard let route = LeagueDeepLinkRouter.shared.pending, !model.isUsingCachedSession else { return }
            LeagueDeepLinkRouter.shared.pending = nil
            guard route.scope == model.workspace?.storageScope else {
                model.notice = .error("This link belongs to a different league or season. Open its league to view it."); return
            }
            deepLink = route
        }
        .task(id: model.isUsingCachedSession) {
            if let route = LeagueDeepLinkRouter.shared.pending, !model.isUsingCachedSession {
                LeagueDeepLinkRouter.shared.pending = nil
                if route.scope == model.workspace?.storageScope { deepLink = route }
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
        .task(id: artworkKey) {
            let key = artworkKey
            teamTabImage = TeamTabArtwork.image(abbreviation: key.abbreviation)
            guard let image = await TeamArtworkLoader.shared.image(for: key.urls),
                  !Task.isCancelled, key == artworkKey else { return }
            teamTabImage = TeamTabArtwork.image(abbreviation: key.abbreviation, artwork: image)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refreshForForeground()
        }
        .task(id: "\(selection)|\(model.isLoadingScores)|\(model.isLoadingLineup)|\(model.isUsingCachedSession)|\(scenePhase)") {
            guard scenePhase == .active, selection == .myTeam, !model.isUsingCachedSession,
                  !model.isLoadingScores, !model.isLoadingLineup else { return }
            await model.transactions.refresh(ifNeeded: true)
        }
        .task(id: "\(scenePhase)-\(selection)-\(model.scopedScoreInspection?.uuidString ?? "scoreboard")") {
            guard scenePhase == .active, !model.isDemo else { return }
            // One foreground-only poller serves the scoreboard and its drill-down.
            // Keep polling finals for MFL corrections; no background timer.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(90 + Double.random(in: 0...10))) } catch { return }
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
