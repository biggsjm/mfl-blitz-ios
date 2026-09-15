#if DEBUG
import SwiftUI

struct NFLTestMatchReviewView: View {
    @Environment(AppModel.self) private var model
    let player: NFLTestPlayer
    let game: NFLTestGame
    let address: String
    let isDemo: Bool
    @State private var profile: NFLTestProfileResponse?
    @State private var candidates: [PlayerIdentity] = []
    @State private var selected: PlayerIdentity?
    @State private var query = ""
    @State private var note = ""
    @State private var season = 0
    @State private var scope: String?
    @State private var origin = ""
    @State private var store: NFLTestMappingStore?
    @State private var saved: NFLTestPlayerMatch?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile?.profile.name ?? player.name).font(.headline)
                    Text("API-NFL ID \(player.providerID)").font(.caption).foregroundStyle(.secondary)
                    Text("\(String(game.season)) game · \(player.team)").font(.subheadline)
                    if let value = profile?.profile {
                        if value.name != player.name { Text("Box score: \(player.name)").font(.caption) }
                        Text([value.position, value.college, value.height, value.weight].compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("NFL provider") } footer: {
                Text("Provider bio, not a historical roster snapshot. Similar names aren’t proof of identity.")
            }
            if loading { Section { ProgressView("Loading identity details…") } }
            if let error { Section { Text(error).font(.footnote).foregroundStyle(.orange) } }
            if let profile, !loading {
                if let saved {
                    Section {
                        Label(isCurrent(saved) ? "Reviewed match" : "Needs another review", systemImage: isCurrent(saved) ? "checkmark.circle" : "exclamationmark.circle")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(saved.mflPlayer.name).font(.headline)
                            Text("MFL ID \(saved.mflPlayer.id) · \(saved.mflPlayer.metadata)").font(.subheadline)
                            Text(saved.note).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Remove match", role: .destructive) { remove(saved) }
                            .accessibilityIdentifier("nfl-test-remove-match")
                    } footer: { Text("Historical test only. No current-season stats or roster changes.") }
                } else {
                    Section {
                        TextField("Search MFL names", text: $query).autocorrectionDisabled()
                            .accessibilityIdentifier("nfl-test-match-search")
                        let matches = NFLTestMappingRules.candidates(profile: profile.profile, players: candidates, query: query)
                        ForEach(matches.prefix(20)) { candidate in
                            Button {
                                selected = candidate; note = ""
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(candidate.name).foregroundStyle(.primary)
                                        Text("\(candidate.metadata) · ID \(candidate.id)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selected?.id == candidate.id { Image(systemName: "checkmark.circle.fill") }
                                }
                            }.accessibilityIdentifier("nfl-test-candidate-\(candidate.id)")
                        }
                        if matches.isEmpty { Text("No position-compatible match. Try another name, or leave unresolved.").foregroundStyle(.secondary) }
                    } header: { Text("MFL · \(String(season)) player catalog") } footer: {
                        Text("These are catalog teams, not \(String(game.season)) game teams. Missing or conflicting identities stay unresolved.")
                    }
                    if let selected {
                        Section {
                            Text("\(profile.profile.name) ↔ \(selected.name)").font(.headline)
                            TextField("How did you verify this is the same person?", text: $note, axis: .vertical)
                                .lineLimit(2...5).accessibilityIdentifier("nfl-test-verification-note")
                            Button("Confirm match") { confirm(selected) }
                                .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 || note.count > 500 || profile.stale)
                                .accessibilityIdentifier("nfl-test-confirm-match")
                        } footer: {
                            Text("Confirm only after checking the identities. This saves a reviewed ID pair for the historical test; it doesn’t attach stats to live player cards.")
                        }
                    }
                }
                if profile.stale { Section { Text("Saved provider profile. Reopen this review when fresh data is available before confirming.").foregroundStyle(.orange) } }
            }
        }
        .navigationTitle("Match player").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            guard let workspace = model.workspace else { throw NFLTestMappingError.invalid }
            scope = workspace.storageScope; season = workspace.season
            origin = isDemo ? "synthetic-preview" : try NFLTestMappingRules.origin(address: address)
            store = try NFLTestMappingStore(defaults: isDemo ? nil : .standard)
            if isDemo {
                profile = NFLTestProfileResponse(provider: "API-NFL", testOnly: true, season: game.season,
                    gameID: game.id, fetchedAt: Date().timeIntervalSince1970, stale: false,
                    profile: NFLTestProfile(providerID: player.providerID, name: player.name,
                        position: "QB", college: "Example College", height: nil, weight: nil))
                candidates = [.init(id: "101", name: "Example Quarterback", position: "QB", nflTeam: "DAL"),
                              .init(id: "102", name: "Example Quarterback", position: "QB", nflTeam: "NYG")]
            } else {
                async let details = NFLStatsTestClient(address: address).profile(player: player, game: game)
                let catalog = try await model.loadPlayerSearchCatalog()
                let response = try await details
                try Task.checkCancellation()
                guard model.workspace?.storageScope == scope, catalog.scope == scope else { throw NFLTestMappingError.invalid }
                profile = response; candidates = Array(catalog.index.playersByID.values)
            }
            query = profile?.profile.name ?? player.name
            saved = store?.matches.first { $0.origin == origin && $0.profile.providerID == player.providerID }
        } catch is CancellationError { }
        catch { self.error = error is NFLTestError || error is NFLTestMappingError ? error.localizedDescription : "Couldn’t load the MFL player catalog. Go back and try again." }
    }

    private func isCurrent(_ record: NFLTestPlayerMatch) -> Bool {
        guard let profile else { return false }
        return NFLTestMappingRules.isCurrent(record, origin: origin, response: profile, game: game,
            player: player, candidate: candidates.first { $0.id == record.mflPlayer.id }, mflSeason: season)
    }

    private func confirm(_ candidate: PlayerIdentity) {
        do {
            guard let profile, let store, model.workspace?.storageScope == scope else { throw NFLTestMappingError.invalid }
            try store.confirm(origin: origin, response: profile, game: game, player: player,
                              candidate: candidate, mflSeason: season, note: note)
            saved = store.matches.first { $0.origin == origin && $0.profile.providerID == player.providerID }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ record: NFLTestPlayerMatch) {
        do {
            guard let store else { throw NFLTestMappingError.storage }
            try store.remove(id: record.id); saved = nil; selected = nil; note = ""; error = nil
        }
        catch { self.error = error.localizedDescription }
    }
}

struct NFLTestSavedMatchesView: View {
    @State private var records: [NFLTestPlayerMatch] = []
    @State private var error: String?
    var body: some View {
        List {
            Section {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.mflPlayer.name).font(.headline)
                        Text("API-NFL \(record.profile.providerID) ↔ MFL \(record.mflPlayer.id)").font(.subheadline)
                        Text("\(String(record.historicalSeason)) test · Reviewed \(record.reviewedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                        Text(record.note).font(.footnote).foregroundStyle(.secondary)
                        Button("Remove match", role: .destructive) {
                            do {
                                let store = try NFLTestMappingStore()
                                try store.remove(id: record.id); records = store.matches
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                if records.isEmpty { Text("No reviewed matches yet.").foregroundStyle(.secondary) }
            } footer: { Text("Human-reviewed historical test IDs only. These do not enable current-season NFL stats or change MFL data.") }
            if let error { Text(error).foregroundStyle(.orange) }
        }
        .navigationTitle("Reviewed matches").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            do { records = try NFLTestMappingStore().matches }
            catch { self.error = error.localizedDescription }
        }
    }
}
#endif
