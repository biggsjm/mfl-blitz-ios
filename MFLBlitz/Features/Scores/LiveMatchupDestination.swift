import SwiftUI
import MFLCore

/// A Lock Screen link owns its snapshot; opening it must not change the lineup
/// week, selected scoreboard week or another stack's in-progress navigation.
struct LiveMatchupDestination: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    let route: LiveMatchupRoute
    @State private var snapshot: ScoresSnapshot?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        Group {
            if let snapshot {
                MatchupDetailView(matchupID: route.matchupID, snapshot: snapshot, refreshError: error,
                    isRefreshingSnapshot: loading, refreshAction: { await refresh(force: true) })
            } else if loading { ProgressView("Loading matchup…") }
            else {
                ContentUnavailableView { Label("Matchup unavailable", systemImage: "sportscourt") }
                    description: { Text(error ?? "Open Scores to choose a matchup.") }
                    actions: { Button("Try again") { Task { await refresh(force: true) } } }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refresh(force: false)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(95)) } catch { return }
                await refresh(force: true)
            }
        }
    }
    private func refresh(force: Bool) async {
        guard route.scope == app.browseScope, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let fresh = try await app.loadMatchupScores(week: route.week, refresh: force)
            guard !Task.isCancelled, route.scope == app.browseScope else { return }
            snapshot = fresh; error = nil
            await app.updateMatchupActivity(using: fresh)
        } catch {
            guard !MFLCoreError.isCancellation(error), !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
