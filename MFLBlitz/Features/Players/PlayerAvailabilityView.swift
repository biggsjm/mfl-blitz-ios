import SwiftUI

struct PlayerAvailabilityCaption: View {
    @Environment(AppModel.self) private var model
    let playerID: String
    let nflTeam: String
    let week: Int
    var fallbackInjury: InjuryStatus? = nil
    var isLocked = false

    var body: some View {
        if data != nil || fallbackInjury != nil || isLocked {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { game; statuses }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 3) { game; statuses }
            }
            .font(.caption)
            .accessibilityElement(children: .combine)
        }
    }

    private var data: PlayerAvailabilitySnapshot? {
        guard let data = model.playerTools.availability[week], data.scope == model.workspace?.storageScope else { return nil }
        return data
    }

    @ViewBuilder private var statuses: some View {
      if data?.injuries[playerID] != nil || fallbackInjury != nil || isLocked {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let injury = data?.injuries[playerID] {
                healthBadge(injury.shortLabel, description: injury.status,
                    color: injury.needsAttention ? .red : .orange)
            } else if let injury = fallbackInjury {
                healthBadge(injury.rawValue, description: injury.label,
                    color: injury == .questionable ? .orange : .red)
            }
            if fallbackInjury == .injuredReserve, let reported = data?.injuries[playerID],
               !["IR", "INJURED RESERVE"].contains(reported.status.uppercased()) {
                healthBadge("IR", description: "Injured reserve", color: .red)
            }
            if isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Locked")
            }
        }
      }
    }

    private func healthBadge(_ label: String, description: String, color: Color) -> some View {
        Text(label).font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Injury report: \(description)")
    }

    @ViewBuilder private var game: some View {
        if data?.byeWeeks[nflTeam] == week {
            Text("Bye week").foregroundStyle(.secondary)
        } else if let game = data?.games[nflTeam] {
            if let date = game.kickoff {
                Text("\(date.formatted(.dateTime.weekday(.abbreviated).hour().minute())) · \(game.opponentLabel)")
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
