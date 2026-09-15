import SwiftUI

struct NFLPlayerBoxScoreView: View {
    let player: NFLFeedPlayer
    let checkedAt: Double?
    let stale: Bool
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let checkedAt {
                Text("\(stale ? "Last known stats" : "NFL stats") · Checked \(ScoreFreshness.age(Date(timeIntervalSince1970: checkedAt), now: now))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(player.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.name).font(.subheadline.weight(.semibold))
                    ForEach(group.stats) { stat in
                        LabeledContent(stat.label, value: stat.value ?? "—")
                            .font(.subheadline).monospacedDigit()
                    }
                }
            }
        }
        .accessibilityIdentifier("player-game-stats")
    }
}
