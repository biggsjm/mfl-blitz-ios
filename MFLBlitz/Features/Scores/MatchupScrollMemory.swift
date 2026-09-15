import SwiftUI

struct MatchupScrollMemory: ViewModifier {
    let mode: String
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *) { content.modifier(ModernMatchupScrollMemory(mode: mode)) }
        else { content }
    }
}

@available(iOS 18, *)
private struct ModernMatchupScrollMemory: ViewModifier {
    let mode: String
    @State private var position = ScrollPosition(edge: .top)
    @State private var offsets: [String: CGPoint] = [:]
    @State private var current = CGPoint.zero
    @State private var restoring = false
    func body(content: Content) -> some View {
        content.scrollPosition($position)
            .onScrollGeometryChange(for: CGPoint.self) { geometry in
                CGPoint(x: 0, y: max(0, geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, point in
                if !restoring { current = point; offsets[mode] = point }
            }
            .onChange(of: mode) { old, new in
                offsets[old] = current
                restoring = true
                let target = offsets[new] ?? .zero
                Task { @MainActor in
                    await Task.yield()
                    position.scrollTo(point: target)
                    current = target
                    await Task.yield()
                    restoring = false
                }
            }
    }
}

struct CompactMatchupScore: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let matchup: Matchup
    let precision: Int
    let stale: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            side(matchup.away)
            Text(stale ? "Delayed" : matchup.status.isLive ? "Live" : matchup.status.label)
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            side(matchup.home)
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("pinned-matchup-score")
    }
    private func side(_ team: MatchupTeam) -> some View {
        VStack(spacing: 2) {
            Text(team.abbreviation).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5)
            Text(team.reportedScore?.pointsText(precision: precision) ?? "—").font(.headline).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
        }.frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(team.name), \(team.reportedScore.map { "\($0.pointsText(precision: precision)) points" } ?? "points unavailable")\(stale ? ", delayed" : "")")
    }
}
