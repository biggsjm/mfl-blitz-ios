import SwiftUI

struct AppTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Tab.scores

    enum Tab: Hashable {
        case scores
        case lineup
        case waivers
        case standings
        case board
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { ScoresView() }
                .tabItem { Label("Scores", systemImage: "sportscourt.fill") }
                .tag(Tab.scores)

            NavigationStack { LineupView() }
                .tabItem { Label("Lineup", systemImage: "person.3.sequence.fill") }
                .tag(Tab.lineup)

            NavigationStack { WaiversView() }
                .tabItem { Label("Waivers", systemImage: "arrow.triangle.swap") }
                .tag(Tab.waivers)
                .badge(model.waivers.claims.count)

            NavigationStack { StandingsView() }
                .tabItem { Label("Standings", systemImage: "list.number") }
                .tag(Tab.standings)

            NavigationStack { BoardView() }
                .tabItem { Label("Board", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.board)
                .badge(model.boardThreads.filter(\.isUnread).count)
        }
    }
}
