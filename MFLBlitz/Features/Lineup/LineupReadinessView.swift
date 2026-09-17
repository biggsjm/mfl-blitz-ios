import SwiftUI

struct LineupReadinessView: View {
    @Environment(AppModel.self) private var model
    let replace: (String) -> Void
    let reviewBench: () -> Void
    @State private var expanded = true
    var body: some View {
        let readiness = LineupReadiness(lineup: model.lineup, availability: model.playerTools.availability[model.lineup.week],
            scope: model.workspace?.storageScope)
        DisclosureGroup(isExpanded: $expanded) {
            if readiness.emptySlots > 0 {
                Button("Choose \(readiness.emptySlots) more \(readiness.emptySlots == 1 ? "starter" : "starters")", action: reviewBench)
                    .disabled(!model.canChangeLineupDraft)
            }
            ForEach(readiness.issues) { issue in
                VStack(alignment: .leading, spacing: 5) {
                    let player = model.lineup.players.first { $0.id == issue.playerID }
                    PlayerNameCaption(name: issue.name, playerID: issue.playerID, nflTeam: player?.nflTeam,
                        jerseyNumber: player?.jerseyNumber, nameFont: .subheadline.weight(.medium))
                    Text(issue.reason + (issue.locked ? " · Locked" : "")).font(.caption).foregroundStyle(.secondary)
                    if !issue.locked {
                        Button("Replace \(issue.name)") { replace(issue.playerID) }
                            .font(.subheadline).disabled(!model.canChangeLineupDraft)
                    }
                }.padding(.vertical, 4)
            }
            if readiness.availabilityUnknown {
                Text("Availability needs a fresh report. Missing reports don’t mean a player is healthy.").font(.caption).foregroundStyle(.secondary)
                Button("Refresh availability") { Task { await model.loadPlayerAvailability(week: model.lineup.week, refresh: true) } }
            }
            if model.hasLineupChanges { Text("Your lineup has unsaved changes.").font(.caption) }
            if let next = readiness.nextLock {
                Text("Next lock: \(next.formatted(.dateTime.weekday(.abbreviated).hour().minute()))").font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            Label(readiness.title, systemImage: readiness.attentionCount > 0 ? "exclamationmark.circle" : "person.crop.circle.badge.checkmark")
                .font(.subheadline.weight(.medium)).foregroundStyle(readiness.attentionCount > 0 ? ScoringStyle.negative : Color.primary)
        }
        .accessibilityIdentifier("lineup-readiness")
        NavigationLink {
            LineupAlertSettings()
        } label: {
            Label(model.lineupAlerts.coverageTitle(week: model.lineup.week), systemImage: "bell")
                .font(.subheadline)
        }.accessibilityIdentifier("lineup-alert-coverage")
    }
}
