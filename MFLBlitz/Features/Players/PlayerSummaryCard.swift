import SwiftUI

/// Identity and performance, not actions. Dropping a player must never look
/// like changing the Starting/Bench status displayed in this card.
struct PlayerSummaryCard: View {
    let player: PlayerIdentity
    let seasonTotal: Double?
    let weeklyAverage: Double?
    let health: PlayerHealth?
    let scorePrecision: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(player.name).font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(player.metadata).font(.subheadline).foregroundStyle(.secondary)
                if let health {
                    Label(health.status, systemImage: "cross.case")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(health.needsAttention ? Color.red : Color.orange)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background((health.needsAttention ? Color.red : Color.orange).opacity(0.1), in: Capsule())
                        .accessibilityLabel("MFL injury report: \(health.status)")
                }
            }
            PlayerMetricPair(firstTitle: "Season points", firstValue: seasonTotal,
                             secondTitle: "Weekly average", secondValue: weeklyAverage,
                             scorePrecision: scorePrecision)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player-detail-\(player.id)")
    }
}

struct PlayerMetricPair: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let firstTitle: String
    let firstValue: Double?
    let secondTitle: String
    let secondValue: Double?
    let scorePrecision: Int

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 18))
        layout {
            metric(firstTitle, value: firstValue)
            metric(secondTitle, value: secondValue)
        }
    }

    private func metric(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.map { $0.pointsText(precision: scorePrecision) } ?? "—")
                .font(.title2.weight(.bold).monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { "\($0.pointsText(precision: scorePrecision)) points" } ?? "Unavailable")
    }
}

struct PlayerWeekSection: View {
    @Environment(AppModel.self) private var model
    let player: PlayerIdentity
    let week: Int
    let metrics: PlayerWeekMetrics?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                if let team = player.nflTeam, let data {
                    if data.byeWeeks[team] == week {
                        Label("Bye week", systemImage: "calendar").font(.headline)
                    } else if let game = data.games[team] {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.opponentLabel).font(.headline)
                            if let kickoff = game.kickoff {
                                Text(kickoff.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Game information unavailable").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                PlayerMetricPair(firstTitle: "Fantasy points", firstValue: metrics?.points,
                                 secondTitle: "Projection", secondValue: metrics?.projection,
                                 scorePrecision: model.scores.scorePrecision)
                if let statLine = metrics?.statLine {
                    Text(statLine).font(.subheadline).foregroundStyle(.secondary)
                }
                if let health = data?.injuries[player.id], let details = health.details {
                    Text("\(health.status) · \(details)").font(.caption).foregroundStyle(.secondary)
                }
                if let data {
                    ForEach(data.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                } else if let error = model.playerTools.availabilityErrors[week] {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry game info") { Task { await model.loadPlayerAvailability(week: week, refresh: true) } }
                } else if model.playerTools.isLoadingAvailability(week: week) {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Updating game info…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Game information unavailable").font(.caption).foregroundStyle(.secondary)
                    Button("Retry game info") { Task { await model.loadPlayerAvailability(week: week, refresh: true) } }
                }
            }
            .padding(.vertical, 6)
            .accessibilityIdentifier("player-week-\(week)")
        } header: {
            Text("Week \(week)").textCase(nil)
        } footer: {
            Text("MFL injury report · Updated daily")
        }
    }

    private var data: PlayerAvailabilitySnapshot? {
        guard let value = model.playerTools.availability[week], value.scope == model.workspace?.storageScope else { return nil }
        return value
    }
}
