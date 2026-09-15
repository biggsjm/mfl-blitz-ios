#if DEBUG
import SwiftUI

// Explicit developer launch flag only. No MFL session restoration or league calls.
// Print only locally authored errors/codes or record counts, never raw diagnostics.
struct NFLStatsConnectionCheckView: View {
    @State private var outcome = "Checking the private NFL connection…"
    var body: some View {
        VStack(spacing: 16) {
            Text("NFL connection check").font(.title2.bold())
            Text(outcome).textSelection(.enabled)
            Text("Development check · No MFL data requested")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding()
        .task {
            guard outcome == "Checking the private NFL connection…" else { return }
            do {
                let saved = UserDefaults.standard.string(forKey: "nflStatsTest.serverURL") ?? ""
                let address = saved.isEmpty ? Bundle.main.object(forInfoDictionaryKey: "NFLStatsTestURL") as? String ?? "" : saved
                let games = try await NFLStatsTestClient(address: address).games(season: 2024)
                outcome = "Connected · \(games.games.count) historical games"
            } catch is CancellationError { outcome = "Check cancelled" }
            catch { outcome = error.localizedDescription }
            print("NFL_TEST_DIAGNOSTIC: \(outcome)")
        }
    }
}
#endif
