import SwiftUI

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
