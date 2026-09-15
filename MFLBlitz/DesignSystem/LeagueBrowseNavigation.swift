import SwiftUI

private struct OpenTeamToolKey: EnvironmentKey {
    static let defaultValue: (@MainActor (TeamToolsRoute) -> Void)? = nil
}

private struct OpenPlayerRouteKey: EnvironmentKey {
    static let defaultValue: (@MainActor (PlayerRoute) -> Void)? = nil
}
private struct ScoreboardPollingKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var scoreboardIsPolling: Bool {
        get { self[ScoreboardPollingKey.self] }
        set { self[ScoreboardPollingKey.self] = newValue }
    }
    var openPlayerRoute: (@MainActor (PlayerRoute) -> Void)? {
        get { self[OpenPlayerRouteKey.self] }
        set { self[OpenPlayerRouteKey.self] = newValue }
    }
    var openTeamTool: (@MainActor (TeamToolsRoute) -> Void)? {
        get { self[OpenTeamToolKey.self] }
        set { self[OpenTeamToolKey.self] = newValue }
    }
}

/// Shortcut grids, player links and matchups share value-based navigation.
/// Each tab or modal owns its path; browsing never changes a
/// different stack behind a sheet.
struct LeagueBrowseStack<Content: View>: View {
    @State private var localPath = NavigationPath()
    private let externalPath: Binding<NavigationPath>?
    private let content: () -> Content

    init(path: Binding<NavigationPath>? = nil, @ViewBuilder content: @escaping () -> Content) {
        externalPath = path; self.content = content
    }

    private var path: Binding<NavigationPath> { externalPath ?? $localPath }

    var body: some View {
        NavigationStack(path: path) {
            content().leagueBrowseDestinations()
        }
        // Scope this to the stack, not just its root content. Pushed team
        // destinations and sheet-owned browse stacks need the same router.
        .environment(\.openTeamTool, { path.wrappedValue.append($0) })
        .environment(\.openPlayerRoute, { path.wrappedValue.append($0) })
    }
}

/// Ownership scope belongs to a signed-in franchise, not the team being browsed.
struct LeagueBrowseScope: Hashable, Sendable {
    let season: Int
    let leagueID: String
    let ownerID: String

    init(workspace: LeagueWorkspace) {
        season = workspace.season
        leagueID = workspace.leagueID
        ownerID = workspace.franchiseID
    }
}

struct TeamRoute: Hashable, Sendable {
    let scope: LeagueBrowseScope
    let franchiseID: String
    var initialSection: TeamDetailSection = .roster
}

struct PlayerRoute: Hashable, Sendable {
    let scope: LeagueBrowseScope
    let playerID: String
    var inspectedWeek: Int? = nil
    /// Display-only identity from the tapped row, never ownership or permission.
    var previewIdentity: PlayerIdentity? = nil
    var scoring: PlayerScoringContext? = nil

    func identityPreview(in activeScope: LeagueBrowseScope?) -> PlayerIdentity? {
        guard scope == activeScope, previewIdentity?.id == playerID else { return nil }
        return previewIdentity
    }
}

struct TeamToolsRoute: Hashable, Identifiable, Sendable {
    enum Destination: String, CaseIterable, Identifiable, Sendable {
        case schedule, addsDrops, trades, watchlist, injuredReserve, activity
        var id: Self { self }
        var title: String {
            switch self {
            case .schedule: "Schedule"
            case .addsDrops: "Adds / Drops"
            case .trades: "Trades"
            case .watchlist: "Watchlist"
            case .injuredReserve: "Injured Reserve"
            case .activity: "League Activity"
            }
        }
        var symbol: String {
            switch self {
            case .schedule: "calendar"
            case .addsDrops: "person.badge.plus"
            case .trades: "arrow.triangle.swap"
            case .watchlist: "star"
            case .injuredReserve: "cross.case"
            case .activity: "clock.arrow.circlepath"
            }
        }
        var accessibilityID: String {
            switch self {
            case .addsDrops: "my-team-adds-drops"
            case .injuredReserve: "my-team-injured-reserve"
            default: "my-team-\(rawValue)"
            }
        }
    }
    let scope: LeagueBrowseScope
    let destination: Destination
    var id: Self { self }
}

struct TeamToolDestination: View {
    @Environment(AppModel.self) private var model
    let route: TeamToolsRoute

    var body: some View {
        Group {
            if route.scope == model.browseScope {
                switch route.destination {
                case .addsDrops: AddsDropsView()
                case .trades: TradesView().environment(model.transactions)
                case .injuredReserve: InjuredReserveView()
                case .schedule: TeamScheduleView(franchiseID: route.scope.ownerID)
                case .watchlist: WatchListView()
                case .activity: TransactionActivityView().environment(model.transactions)
                }
            } else {
                ContentUnavailableView("League changed", systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Go back to open details for your current league."))
            }
        }
        .navigationTitle(route.destination.title)
        .navigationBarTitleDisplayMode(.inline)
        .id(route)
    }
}

struct ScheduleRoute: Hashable, Sendable {
    let scope: LeagueBrowseScope
}

struct StandingsRoute: Hashable, Sendable {
    let scope: LeagueBrowseScope
    let franchiseID: String
    let divisionID: String?
}

struct MatchupRoute: Hashable, Sendable {
    let scope: LeagueBrowseScope
    let week: Int
    let matchupID: String
}

/// Live scoreboard IDs are not season-schedule IDs. Keep this route typed too:
/// mixing destination-view links with a bound NavigationPath can reinsert the
/// matchup above the player destination when SwiftUI reconciles the stack.
struct LiveMatchupRoute: Hashable, Sendable {
    let scope: LeagueBrowseScope
    let week: Int
    let matchupID: String
}

private struct BrowsedScoringWeekKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    var browsedScoringWeek: Int? {
        get { self[BrowsedScoringWeekKey.self] }
        set { self[BrowsedScoringWeekKey.self] = newValue }
    }
}

private struct LeagueBrowseDestinations: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: LiveMatchupRoute.self) { route in
                if route.scope != model.browseScope { unavailableSession }
                else if route.week == model.scores.week {
                    MatchupDetailView(matchupID: route.matchupID).id(route)
                } else {
                    LiveMatchupDestination(route: route).id(route)
                }
            }
            .navigationDestination(for: StandingsRoute.self) { route in
                if route.scope == model.browseScope {
                    StandingsView(initialScope: route.divisionID == nil ? .overall : .division,
                                  focusedFranchiseID: route.franchiseID).id(route)
                } else { unavailableSession }
            }
            .navigationDestination(for: TeamToolsRoute.self) { route in
                TeamToolDestination(route: route)
            }
            .navigationDestination(for: TeamRoute.self) { route in
                if route.scope == model.browseScope {
                    TeamDetailView(franchiseID: route.franchiseID, initialSection: route.initialSection) { franchiseID in
                        TeamScheduleView(franchiseID: franchiseID)
                    }
                    .id(route)
                } else { unavailableSession }
            }
            .navigationDestination(for: PlayerRoute.self) { route in
                if route.scope == model.browseScope {
                    PlayerDetailView(playerID: route.playerID, inspectedWeek: route.inspectedWeek,
                        previewIdentity: route.identityPreview(in: model.browseScope), scoring: route.scoring)
                        .id(route)
                } else { unavailableSession }
            }
            .navigationDestination(for: ScheduleRoute.self) { route in
                if route.scope == model.browseScope { LeagueScheduleView().id(route) }
                else { unavailableSession }
            }
            .navigationDestination(for: MatchupRoute.self) { route in
                if route.scope == model.browseScope { ScheduleMatchupDetailView(route: route).id(route) }
                else { unavailableSession }
            }
    }

    private var unavailableSession: some View {
        ContentUnavailableView("League changed", systemImage: "person.crop.circle.badge.exclamationmark",
                               description: Text("Go back to open details for your current league."))
    }
}

extension View {
    /// Apply inside each NavigationStack exposing canonical team/player routes.
    func leagueBrowseDestinations() -> some View { modifier(LeagueBrowseDestinations()) }
}
