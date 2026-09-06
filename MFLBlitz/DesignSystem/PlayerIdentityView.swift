import SwiftUI

/// Presentation only. The caller supplies navigation or selection so adjacent
/// lineup, waiver and trade actions retain independent hit targets.
struct PlayerIdentityView: View {
    let player: PlayerIdentity
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(player.position ?? "—")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.blitzNavy)
                .frame(width: 44, height: 44)
                .background(Color.blitzGreen.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !player.metadata.isEmpty {
                    Text(player.metadata).font(.caption).foregroundStyle(.secondary)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: BlitzMetrics.minimumTapTarget)
        .accessibilityElement(children: .combine)
    }
}
