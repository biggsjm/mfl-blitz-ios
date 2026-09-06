import SwiftUI
import Charts

struct PlayerResearchSections: View {
    let research: PlayerResearchModel
    let retry: () -> Void
    let loadMore: () -> Void
    var body: some View {
        if let page = research.page {
            Section("Season · Your league’s scoring") {
                HStack {
                    metric("Total points", page.total)
                    Spacer()
                    metric("Weekly average", page.average)
                }
                if page.completedWeek == 0 {
                    Text("Game history appears after the first week is completed.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(page.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            if !page.weeks.isEmpty {
                Section {
                    if page.weeks.contains(where: { $0.points != nil }) {
                        Chart(page.weeks.sorted { $0.week < $1.week }) { item in
                            if let points = item.points {
                                BarMark(x: .value("Week", String(item.week)), y: .value("Fantasy points", points))
                                    .foregroundStyle(Color.blitzGreen)
                                    .accessibilityLabel("Week \(item.week)")
                                    .accessibilityValue("\(points.pointsText) fantasy points")
                            }
                        }
                        .frame(height: 130)
                        .accessibilityIdentifier("player-recent-form")
                    }
                    ForEach(page.weeks) { item in
                        LabeledContent("Week \(item.week)", value: item.unavailable ? "Unavailable" : item.points.pointsText)
                    }
                    if page.nextBeforeWeek != nil {
                        Button("Load earlier weeks", action: loadMore).disabled(research.isLoading)
                    }
                } header: { Text("Recent form") } footer: {
                    Text("Fantasy points, not raw NFL statistics. A dash means MFL supplied no score.")
                }
            }
            if let points = page.opponentPointsAllowed, let opponent = page.opponentName {
                Section("Matchup · \(opponent)") {
                    LabeledContent("Fantasy points allowed", value: points.pointsText)
                    Text("Season total at this position, using your league’s scoring. Teams may have played different numbers of games.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if research.isLoading {
            Section { ProgressView("Loading player history…").frame(maxWidth: .infinity) }
        }
        if let error = research.errorMessage {
            Section {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                Button("Retry research", action: retry).disabled(research.isLoading)
            }
        }
    }

    private func metric(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value.pointsText).font(.title2.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
