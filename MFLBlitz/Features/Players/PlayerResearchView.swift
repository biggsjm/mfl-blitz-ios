import SwiftUI

/// Completed-week fantasy points plus the explicitly disclosed current-team
/// NFL schedule approximation. No historical affiliation or raw stats implied.
struct PlayerResearchSections: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingInfo = false
    let research: PlayerResearchModel
    let scorePrecision: Int
    let retry: () -> Void
    let loadMore: () -> Void

    var body: some View {
        Section {
            if let page = research.page {
                if !page.weeks.isEmpty && !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 12) {
                        Text("Week").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Points").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("NFL opp").frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                }
                if page.weeks.isEmpty {
                    Text("Games appear after the first completed week.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(page.weeks.sorted { $0.week > $1.week }) { item in
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
                    layout {
                        Text("Week \(item.week)").font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(dynamicTypeSize.isAccessibilitySize ? "\(pointsText(item)) pts" : pointsText(item))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                        Text(item.opponentLabel ?? "—")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Week \(item.week), \(spokenPoints(item)), NFL opponent: \(item.opponentLabel ?? "unavailable")")
                    .accessibilityIdentifier("player-game-week-\(item.week)")
                }
                if page.nextBeforeWeek != nil {
                    Button("Earlier weeks", action: loadMore)
                        .disabled(research.isLoading)
                        .accessibilityIdentifier("player-earlier-weeks")
                }
                ForEach(page.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            if research.isLoading {
                ProgressView("Updating game log…").frame(maxWidth: .infinity)
            }
            if let error = research.errorMessage {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                Button("Retry game log", action: retry).disabled(research.isLoading)
            }
        } header: {
            HStack {
                Text("Game log").accessibilityIdentifier("player-game-log-heading")
                Spacer()
                Button("About game log", systemImage: "info.circle") { showingInfo = true }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("player-game-log-info")
                    .popover(isPresented: $showingInfo) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("About this log").font(.headline)
                                Text("Points use your league’s scoring. NFL opponents follow \(research.page?.scheduleTeam.map { "\($0)’s" } ?? "the player’s current team’s") schedule; earlier teams may differ after a trade. MFL does not provide raw NFL statistics.")
                                    .font(.subheadline).foregroundStyle(Color.secondary)
                            }
                            .padding()
                        }
                        .foregroundStyle(Color.primary)
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(width: 300, height: dynamicTypeSize.isAccessibilitySize ? 350 : 190)
                        .presentationCompactAdaptation(.popover)
                    }
            }
            .textCase(nil)
        } footer: {
            Text("Completed weeks · — means not reported.")
        }
    }

    private func pointsText(_ item: PlayerHistoryWeek) -> String {
        if item.unavailable { return "Unavailable" }
        return item.points.map { $0.pointsText(precision: scorePrecision) } ?? "—"
    }

    private func spokenPoints(_ item: PlayerHistoryWeek) -> String {
        guard !item.unavailable, item.points != nil else { return "fantasy points unavailable" }
        return "\(pointsText(item)) fantasy points"
    }
}
