import SwiftUI

/// Presentation only. The caller supplies navigation or selection so adjacent
/// lineup, waiver and trade actions retain independent hit targets.
struct PlayerIdentityView: View {
    let player: PlayerIdentity
    var subtitle: String? = nil
    var inlineTeam = true
    var availabilityWeek: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(player.position ?? "—")
                .font(.caption.weight(.heavy))
                .lineLimit(1).minimumScaleFactor(0.3)
                .foregroundStyle(Color.blitzNavy)
                .padding(4)
                .frame(width: 44, height: 44)
                .background(Color.blitzGreen.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(!inlineTeam)
            VStack(alignment: .leading, spacing: 4) {
                if inlineTeam {
                    PlayerNameCaption(name: player.name, playerID: player.id,
                        nflTeam: player.nflTeam, jerseyNumber: player.jerseyNumber)
                } else {
                    Text(player.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !inlineTeam, !player.metadata.isEmpty {
                    Text(player.metadata).font(.caption).foregroundStyle(.secondary)
                }
                if let availabilityWeek {
                    PlayerAvailabilityCaption(playerID: player.id, nflTeam: player.nflTeam ?? "", week: availabilityWeek)
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

struct PlayerNameCaption: View {
    @Environment(AppModel.self) private var model
    let name: String
    var context: String? = nil
    var playerID: String? = nil
    var nflTeam: String? = nil
    var jerseyNumber: String? = nil
    var position: String? = nil
    var nameFont: Font = .body.weight(.semibold)
    var metadataFont: Font = .caption

    var body: some View {
        Text(title).fixedSize(horizontal: false, vertical: true)
    }

    private var title: AttributedString {
        var result = AttributedString(name)
        result.font = nameFont
        result.foregroundColor = .primary
        let jersey: String? = if let playerID {
            model.playerTools.jerseyNumber(playerID: playerID, nflTeam: nflTeam, fallback: jerseyNumber)
        } else { PlayerJersey.validNumber(jerseyNumber) }
        // Keep the team and its number together when the name needs to wrap.
        let team = [nflTeam, jersey.map { "#\($0)" }].compactMap { $0 }.joined(separator: "\u{00A0}")
        let context = context ?? [position, team.isEmpty ? nil : team].compactMap { $0 }.joined(separator: " · ")
        if !context.isEmpty {
            var metadata = AttributedString("  \(context)")
            metadata.font = metadataFont
            metadata.foregroundColor = .secondary
            result.append(metadata)
        }
        return result
    }
}

private struct PlayerJerseyMetadataModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    let playerIDs: [String]

    func body(content: Content) -> some View {
        // Bound broad directories to their first 100 results. Narrowing a
        // filter loads that subset; scrolling never starts row requests.
        let ids = Array(Set(playerIDs.prefix(100))).sorted()
        content.task(id: "\(model.workspace?.storageScope ?? "")|\(model.isUsingCachedSession)|\(ids.joined(separator: ","))") {
            guard !ids.isEmpty, !model.isUsingCachedSession else { return }
            // Let navigation/search settle before requesting optional metadata.
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await model.loadPlayerJerseys(playerIDs: ids)
        }
    }
}

extension View {
    func playerJerseyMetadata(for playerIDs: [String]) -> some View {
        modifier(PlayerJerseyMetadataModifier(playerIDs: playerIDs))
    }
}
