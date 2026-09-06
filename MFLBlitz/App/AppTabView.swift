import SwiftUI

struct AppTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
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
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refreshForForeground()
        }
        .task(id: "\(scenePhase)-\(selection)") {
            guard scenePhase == .active, selection == .scores, !model.isDemo else { return }
            // One foreground-only poller serves the scoreboard and its drill-down.
            // Keep polling finals for MFL corrections; no background timer.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(90 + Double.random(in: 0...10))) } catch { return }
                guard !Task.isCancelled else { return }
                await model.refreshScores(silent: true)
            }
        }
    }
}
