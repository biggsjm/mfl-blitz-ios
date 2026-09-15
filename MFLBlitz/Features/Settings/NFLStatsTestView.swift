#if DEBUG
import SwiftUI

struct NFLStatsTestView: View {
    let isDemo: Bool
    @AppStorage("nflStatsTest.serverURL") private var savedAddress = ""
    @State private var address = ""
    @State private var season = 2024
    @State private var result: NFLTestGames?
    @State private var loadedAddress = ""
    @State private var loading = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                Label(isDemo ? "Synthetic preview" : "Historical test · 2022–2024", systemImage: "flask")
                Text("NFL stats only. Current-season stats aren’t included in this free plan. Your MFL scores stay unchanged.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !isDemo {
                Section {
                    NavigationLink("Reviewed player matches") { NFLTestSavedMatchesView() }
                }
                Section {
                    TextField("https://server.tailnet.ts.net:8443", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityLabel("Private NFL test server")
                        .disabled(loading)
                    Picker("Season", selection: $season) {
                        ForEach([2024, 2023, 2022], id: \.self) { Text(String($0)).tag($0) }
                    }.disabled(loading)
                    if !savedAddress.isEmpty {
                        Button("Forget server", role: .destructive) {
                            savedAddress = ""; address = ""; result = nil; error = nil
                        }.disabled(loading)
                    }
                } header: { Text("Private connection") } footer: {
                    Text("Connect Tailscale first. Enter the server address—not an API key. Only the selected NFL season and game are requested.")
                }
            }
            Section {
                Button(action: load) {
                    if loading { HStack { ProgressView(); Text("Loading historical games…") } }
                    else { Label("Load games", systemImage: "arrow.down.circle") }
                }
                .accessibilityIdentifier("nfl-test-load-games")
                .disabled(loading || (!isDemo && (try? NFLStatsTestClient.serverURL(address)) == nil))
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
            }
            if let result {
                let games = result.games.filter { $0.isFinal && $0.stage == "Regular Season" }
                Section {
                    ForEach(games) { game in
                        NavigationLink {
                            NFLTestGameView(game: game, address: loadedAddress, isDemo: isDemo)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(game.away) at \(game.home)").font(.headline)
                                Text("\(String(game.season)) · \(game.week)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("nfl-test-game-\(game.id)")
                    }
                    if games.isEmpty { Text("No completed regular-season games were returned.").foregroundStyle(.secondary) }
                } header: { Text("\(String(result.season)) games") } footer: {
                    NFLTestAttribution(fetchedAt: result.fetchedAt, stale: result.stale, isDemo: isDemo)
                }
            }
        }
        .navigationTitle("NFL stats test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if address.isEmpty {
                address = savedAddress.isEmpty ? Bundle.main.object(forInfoDictionaryKey: "NFLStatsTestURL") as? String ?? "" : savedAddress
            }
        }
        .onChange(of: season) { result = nil; error = nil }
        .onChange(of: address) { result = nil; error = nil }
        .onDisappear { request?.cancel(); loading = false }
    }

    private func load() {
        guard !loading else { return }
        loading = true; error = nil
        let selected = season, server = address
        request = Task { @MainActor in
            defer { loading = false }
            do {
                let value = try await isDemo ? NFLTestPreview.games : NFLStatsTestClient(address: server).games(season: selected)
                try Task.checkCancellation()
                result = value; loadedAddress = server
                if !isDemo { savedAddress = server }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct NFLTestGameView: View {
    let game: NFLTestGame
    let address: String
    let isDemo: Bool
    @State private var result: NFLTestBoxScore?
    @State private var error: String?
    @State private var loading = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                Text("\(game.away) at \(game.home)").font(.headline)
                Text("\(String(game.season)) · \(game.week) · Final").foregroundStyle(.secondary)
                if let away = game.awayScore, let home = game.homeScore {
                    Text("\(away.formatted()) – \(home.formatted())").font(.title2.monospacedDigit())
                }
            } footer: { Text("Historical NFL box score—not fantasy points.") }
            if let result {
                Section {
                    ForEach(result.players) { player in
                        NavigationLink {
                            NFLTestPlayerView(player: player, game: game, fetchedAt: result.fetchedAt,
                                              stale: result.stale, isDemo: isDemo, address: address)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(player.name)
                                Text(player.team).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("nfl-test-player-\(player.id)")
                    }
                    if result.players.isEmpty { Text("No player statistics were reported for this game.") }
                } header: { Text("Players") } footer: {
                    NFLTestAttribution(fetchedAt: result.fetchedAt, stale: result.stale, isDemo: isDemo)
                }
            }
            if let error { Section { Text(error).foregroundStyle(.orange).font(.footnote) } }
            Section {
                Button(action: load) {
                    if loading { HStack { ProgressView(); Text("Loading player stats…") } }
                    else { Label(result == nil ? "Load player stats" : "Check for updates", systemImage: "arrow.down.circle") }
                }.disabled(loading).accessibilityIdentifier("nfl-test-load-players")
            }
        }
        .navigationTitle("\(String(game.season)) · \(game.week)")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { task?.cancel(); loading = false }
    }

    private func load() {
        guard !loading else { return }
        loading = true; error = nil
        task = Task { @MainActor in
            defer { loading = false }
            do {
                let value = try await isDemo ? NFLTestPreview.box : NFLStatsTestClient(address: address).players(game: game)
                try Task.checkCancellation()
                result = value
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct NFLTestPlayerView: View {
    let player: NFLTestPlayer
    let game: NFLTestGame
    let fetchedAt: Double
    let stale: Bool
    let isDemo: Bool
    let address: String

    var body: some View {
        List {
            Section {
                Text(player.name).font(.title2.bold())
                Text(player.team).foregroundStyle(.secondary)
                Text("\(String(game.season)) · \(game.week) · Final").font(.subheadline)
            } footer: { Text("Historical NFL stats · MFL fantasy points are unchanged.") }
            ForEach(player.groups) { group in
                Section(group.name) {
                    ForEach(group.stats) { stat in
                        LabeledContent(stat.displayName) { Text(stat.displayValue).monospacedDigit() }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(stat.displayName), \(stat.displayValue)")
                            .accessibilityIdentifier("nfl-test-stat-\(group.name)-\(stat.name)")
                    }
                }
            }
            Section {
                NavigationLink {
                    NFLTestMatchReviewView(player: player, game: game, address: address, isDemo: isDemo)
                } label: {
                    Label("Review MFL player match", systemImage: "person.crop.rectangle.badge.checkmark")
                }.accessibilityIdentifier("nfl-test-review-match")
            }
            Section {
                NFLTestAttribution(fetchedAt: fetchedAt, stale: stale, isDemo: isDemo)
                Text("— means not reported.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Player stats")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NFLTestAttribution: View {
    let fetchedAt: Double
    let stale: Bool
    let isDemo: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isDemo ? "Synthetic preview · No network requests" : "Source: API-NFL / API-Sports")
            if !isDemo {
                Text("Retrieved \(Date(timeIntervalSince1970: fetchedAt).formatted(date: .abbreviated, time: .shortened))")
                Text(stale ? "Saved data · Provider refresh unavailable" : "Cached on Hephaestus for up to 24 hours")
                Text("Retrieval time is not the provider’s last correction time.")
            }
        }.font(.footnote).foregroundStyle(.secondary)
    }
}
#endif
