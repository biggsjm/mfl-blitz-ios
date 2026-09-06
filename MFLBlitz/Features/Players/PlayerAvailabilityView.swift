import SwiftUI

struct PlayerAvailabilityCaption: View {
    @Environment(AppModel.self) private var model
    let playerID: String
    let nflTeam: String
    let week: Int

    var body: some View {
        if let data = model.playerTools.availability[week], data.scope == model.workspace?.storageScope {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { health(data); game(data) }
                VStack(alignment: .leading, spacing: 3) { health(data); game(data) }
            }
            .font(.caption)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func health(_ data: PlayerAvailabilitySnapshot) -> some View {
        if let injury = data.injuries[playerID] {
            Text(injury.shortLabel).font(.caption2.bold())
                .foregroundStyle(injury.needsAttention ? Color.red : Color.orange)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background((injury.needsAttention ? Color.red : Color.orange).opacity(0.12), in: Capsule())
                .accessibilityLabel("Injury report: \(injury.status)")
        }
    }

    @ViewBuilder private func game(_ data: PlayerAvailabilitySnapshot) -> some View {
        if data.byeWeeks[nflTeam] == week {
            Text("Bye week").foregroundStyle(.secondary)
        } else if let game = data.games[nflTeam] {
            if let date = game.kickoff {
                Text("\(game.opponentLabel) · \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else { Text(game.opponentLabel).foregroundStyle(.secondary) }
        }
    }
}

struct PlayerAvailabilitySection: View {
    @Environment(AppModel.self) private var model
    let player: PlayerIdentity
    let week: Int

    var body: some View {
        Section {
            if let data = model.playerTools.availability[week], data.scope == model.workspace?.storageScope {
                if let injury = data.injuries[player.id] {
                    Label(injury.status, systemImage: "cross.case")
                        .foregroundStyle(injury.needsAttention ? Color.red : Color.primary)
                    if let details = injury.details { Text(details).foregroundStyle(.secondary) }
                } else if !data.issues.contains("Injury report unavailable.") {
                    Text("No entry in this injury report").foregroundStyle(.secondary)
                }
                if let team = player.nflTeam {
                    if data.byeWeeks[team] == week { Label("Bye week", systemImage: "calendar") }
                    else if let game = data.games[team] {
                        LabeledContent("Opponent", value: game.opponentLabel)
                        if let kickoff = game.kickoff {
                            LabeledContent("Kickoff", value: kickoff.formatted(date: .abbreviated, time: .shortened))
                        }
                    } else { Text("Game information unavailable").foregroundStyle(.secondary) }
                    if let bye = data.byeWeeks[team], bye != week { LabeledContent("Bye", value: "Week \(bye)") }
                }
                ForEach(data.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                if let updated = data.injuryUpdatedAt {
                    Text("Injury report updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let error = model.playerTools.availabilityErrors[week] {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                Button("Retry availability") { Task { await model.loadPlayerAvailability(week: week, refresh: true) } }
            } else { ProgressView("Loading availability…") }
        } header: { Text("Availability · Week \(week)") } footer: {
            Text("MFL’s injury report updates daily; it isn’t a live status feed.")
        }
    }
}
