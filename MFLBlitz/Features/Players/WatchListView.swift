import SwiftUI

struct WatchListView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            if model.isDemo { DemoBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            WatchListStatusSection()
            if let watchList = model.playerTools.watchList, watchList.scope == model.workspace?.storageScope {
                if watchList.players.isEmpty {
                    ContentUnavailableView("Your shortlist starts here", systemImage: "star",
                        description: Text("Tap the star on any player’s page to keep them in your watchlist."))
                        .listRowBackground(Color.clear)
                } else if let scope = model.browseScope {
                    Section("Watching · \(watchList.players.count)") {
                        ForEach(watchList.players) { player in
                            NavigationLink(value: PlayerRoute(scope: scope, playerID: player.id, inspectedWeek: model.currentWeek)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    PlayerIdentityView(player: player)
                                    PlayerAvailabilityCaption(playerID: player.id, nflTeam: player.nflTeam ?? "", week: model.currentWeek)
                                }
                            }
                            .accessibilityIdentifier("watchlist-player-\(player.id)")
                        }
                    }
                }
            } else if model.playerTools.isLoadingWatchList {
                ProgressView("Loading watchlist…").frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .task(id: model.workspace?.storageScope) { await model.loadWatchList() }
        .task(id: model.currentWeek) { await model.loadPlayerAvailability(week: model.currentWeek) }
        .refreshable { await model.loadWatchList(refresh: true) }
        .accessibilityIdentifier("watchlist")
    }
}

struct WatchListStatusSection: View {
    @Environment(AppModel.self) private var model
    @State private var acknowledge = false
    var body: some View {
        if let pending = model.playerTools.unconfirmedWatch {
            Section {
                Label("Watchlist change needs checking", systemImage: "exclamationmark.triangle")
                Text(pending.isWatched ? "The player may already be on your watchlist." : "The player may already have been removed.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Check status") { Task { await model.loadWatchList(refresh: true) } }
                    .disabled(model.playerTools.isChangingWatchList || model.playerTools.isLoadingWatchList)
                if let workspace = model.workspace { Link("Open MFL", destination: workspace.leagueURL) }
                Button("I checked MFL") { acknowledge = true }
                    .disabled(model.playerTools.isChangingWatchList || model.playerTools.isLoadingWatchList)
            }
            .alert("Finished checking MFL?", isPresented: $acknowledge) {
                Button("Keep checking", role: .cancel) {}
                Button("Clear notice") { Task { await model.acknowledgeWatchList() } }
            } message: { Text("This clears the notice without sending another watchlist change.") }
        } else if let error = model.playerTools.watchError {
            Section {
                Label(error, systemImage: "wifi.exclamationmark").font(.subheadline)
                Button("Retry watchlist") { Task { await model.loadWatchList(refresh: true) } }
            }
        }
    }
}
