import SwiftUI

private struct OpenTeamToolKey: EnvironmentKey {
    static let defaultValue: (@MainActor (TeamToolsRoute) -> Void)? = nil
}

extension EnvironmentValues {
    var openTeamTool: (@MainActor (TeamToolsRoute) -> Void)? {
        get { self[OpenTeamToolKey.self] }
        set { self[OpenTeamToolKey.self] = newValue }
    }
}

/// Button-based shortcut grids append to the same typed path as player and
/// matchup links. Each tab or modal owns its path; browsing never changes a
/// different stack behind a sheet.
struct LeagueBrowseStack<Content: View>: View {
    @State private var path = NavigationPath()
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack(path: $path) {
            content().leagueBrowseDestinations()
                .environment(\.openTeamTool, { path.append($0) })
        }
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

struct MatchupRoute: Hashable, Sendable {
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
                    PlayerDetailView(playerID: route.playerID, inspectedWeek: route.inspectedWeek)
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
