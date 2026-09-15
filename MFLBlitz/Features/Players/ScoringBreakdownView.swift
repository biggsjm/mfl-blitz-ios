import SwiftUI
import MFLCore

struct ScoringBreakdownView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let position: String
    let player: NFLFeedPlayer?
    let official: Double?
    let precision: Int
    @Binding var expanded: Bool
    @State private var rules: [MFLScoringRule] = []
    @State private var failed = false
    @State private var loadedScope: String?

    var body: some View {
        DisclosureGroup("Points breakdown", isExpanded:$expanded) {
            if loadedScope != model.workspace?.storageScope || rules.isEmpty {
                Text(failed ? "Scoring rules couldn’t load. Reopen this player to retry." : "Loading league scoring rules…")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                let breakdown = ScoringBreakdown(rules: rules, position: position, player: player, official: official)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(breakdown.contributions) { item in
                        let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:6)) : AnyLayout(HStackLayout(alignment:.firstTextBaseline,spacing:12))
                        row {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.rule.label).font(.subheadline)
                                Text(explanation(item)).font(.caption).foregroundStyle(.secondary)
                            }
                            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                            Text(typeSize.isAccessibilitySize ? "\(format(item.points)) points" : format(item.points)).monospacedDigit().font(.subheadline.weight(.medium))
                        }.accessibilityElement(children: .combine)
                    }
                    if breakdown.contributions.isEmpty { Text("No scoring contributions available yet.").foregroundStyle(.secondary) }
                    Divider()
                    total("Shown stats total",value:breakdown.total)
                    total("MFL points",value:breakdown.official).fontWeight(.medium)
                    if let difference = breakdown.difference, abs(NSDecimalNumber(decimal: difference).doubleValue) >= pow(10, -Double(precision)) / 2 {
                        total("Not yet explained",value:difference)
                        Text("May include missing stats, league adjustments, or updates still arriving.").font(.caption).foregroundStyle(.secondary)
                    }
                    if !breakdown.remaining.isEmpty {
                        DisclosureGroup("Other scoring rules") {
                            ForEach(breakdown.remaining) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.rule.label).font(.subheadline)
                                    Text(item.points == nil ? "\(item.rule.points) points · Range \(item.rule.range) · Calculation unavailable" : "\(explanation(item)) · 0 points")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }.padding(.top, 8)
            }
        }
        .accessibilityIdentifier("player-points-breakdown")
        .task(id: model.workspace?.storageScope) {
            let scope = model.workspace?.storageScope
            do {
                let value = try await model.loadScoringRules()
                guard !Task.isCancelled, scope == model.workspace?.storageScope else { return }
                rules = value; loadedScope = scope; failed = false
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
    @ViewBuilder private func total(_ title: String, value: Decimal?) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.subheadline)
                Text("\(format(value)) points").font(.subheadline.weight(.medium)).monospacedDigit()
            }.accessibilityElement(children:.combine)
        } else { LabeledContent(title,value:format(value)) }
    }
    private func format(_ value: Decimal?) -> String {
        value.map { NSDecimalNumber(decimal: $0).doubleValue.pointsText(precision: precision) } ?? "—"
    }
    private func explanation(_ item: ScoringBreakdown.Item) -> String {
        let stat = item.stat.map { NSDecimalNumber(decimal: $0).stringValue } ?? "—"
        if item.rule.points.hasPrefix("*") { return "\(stat) × \(item.rule.points.dropFirst())" }
        let parts = item.rule.points.split(separator: "/")
        if parts.count == 2 { return "\(stat) · \(parts[0]) pt per \(parts[1]) (whole groups)" }
        return "\(stat) · Range \(item.rule.range) → \(item.rule.points) pts"
    }
}
