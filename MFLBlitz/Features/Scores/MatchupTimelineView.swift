import SwiftUI

struct MatchupTimelineView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showInfo = false
    @State private var showRecordingDetails = false
    let matchup: Matchup
    let week: Int
    let precision: Int
    var body: some View {
        let events = timelineEvents
        let recording = events.filter { $0.kind == "gap" || $0.kind == "tracking" }
        let changes = MatchupTimelineUpdate.grouped(events)
        ScrollView {
            LazyVStack(alignment:.leading,spacing:16) {
                if let issue=model.matchupTimeline.issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                if recording.contains(where: { $0.kind == "gap" }) {
                    Label("Some updates weren’t recorded", systemImage: "clock.badge.exclamationmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if changes.isEmpty {
                    ContentUnavailableView("No score changes yet",systemImage:"clock.arrow.circlepath",
                        description:Text("New changes will appear here."))
                }
                ForEach(Array(changes.enumerated()), id: \.element.id) { index, update in
                    if index == 0 || !Calendar.current.isDate(changes[index - 1].date, inSameDayAs: update.date) {
                        Text(update.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    updateRow(update)
                    Divider()
                }
                if !recording.isEmpty {
                    DisclosureGroup("Recording details", isExpanded: $showRecordingDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(recording) { event in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.kind == "gap" ? "Gap in updates" : "Tracking started")
                                    Text(event.fromAt.map { "\(Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened)) – \(event.date.formatted(date: .abbreviated, time: .shortened))" }
                                         ?? event.date.formatted(date: .abbreviated, time: .shortened))
                                        .foregroundStyle(.secondary)
                                }.font(.caption).accessibilityElement(children: .combine)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("timeline-recording-details")
                }
            }.padding().readablePageWidth()
        }
        .navigationTitle("Matchup timeline").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("About this timeline", systemImage: "info.circle") { showInfo = true }
                    .popover(isPresented: $showInfo) {
                        Text("Saved point changes may include several plays. Recording details show gaps in coverage. History is kept for 21 days.")
                            .font(.subheadline).padding().frame(idealWidth: 280)
                            .presentationCompactAdaptation(.popover)
                    }
            }
        }
        .pageBackground()
        .accessibilityIdentifier("matchup-timeline")
        .refreshable { await refresh() }
        .task(id:scenePhase) {
            guard scenePhase == .active else { return }
            repeat {
                await refresh()
                do { try await Task.sleep(for:.seconds(60)) } catch { return }
            } while !Task.isCancelled
        }
    }
    @ViewBuilder private func updateRow(_ update: MatchupTimelineUpdate) -> some View {
        if let team = update.teamChange {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(update.players) { player in eventRow(player) }
                    if update.players.isEmpty { Text("Player changes weren’t available for this update.").font(.caption).foregroundStyle(.secondary) }
                    else if let delta = update.delta {
                        let explained = update.players.reduce(0.0) { $0 + (($1.current ?? 0) - ($1.previous ?? 0)) }
                        if abs(delta - explained) >= pow(10, -Double(precision)) / 2 {
                            Text("Other points: \((delta - explained).pointsText(precision: precision))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text([matchup.away, matchup.home].first { $0.id == update.teamID }?.name ?? team.name).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        if let delta = update.delta { Text("\(delta > 0 ? "+" : "")\(delta.pointsText(precision: precision)) pts").monospacedDigit() }
                    }
                    Text("\(team.previous?.pointsText(precision: precision) ?? "—") → \(team.current?.pointsText(precision: precision) ?? "—") · \(update.date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }.foregroundStyle(.primary)
            }.accessibilityIdentifier("timeline-score-update")
        } else {
            ForEach(update.players + update.other) { event in eventRow(event) }
        }
    }
    private var timelineEvents: [MatchupTimelineEvent] {
        #if DEBUG
        if model.isDemo && ProcessInfo.processInfo.arguments.contains("--timeline-scores-preview") {
            let at = Date().timeIntervalSince1970
            return [
                .init(id: "preview-team", at: at, kind: "team", name: matchup.away.name,
                    teamID: matchup.away.id, previous: 20, current: 27, source: "preview"),
                .init(id: "preview-player-1", at: at, kind: "player", name: "Brenton Strange",
                    teamID: matchup.away.id, playerID: "one", previous: 3, current: 11, source: "preview"),
                .init(id: "preview-player-2", at: at, kind: "player", name: "Dak Prescott",
                    teamID: matchup.away.id, playerID: "two", previous: 17, current: 16, source: "preview")
            ]
        }
        // Reproduce a history containing only recording gaps without touching
        // the saved archive, account, notification consent or scoring feeds.
        if model.isDemo && ProcessInfo.processInfo.arguments.contains("--timeline-gaps-preview") {
            return (0..<5).map { index in
                let tracking = index == 4
                return MatchupTimelineEvent(id: "preview-\(index)", at: Date().timeIntervalSince1970 - Double(index * 600),
                    kind: tracking ? "tracking" : "gap",
                    name: tracking ? "Recording started from the first saved score" : "Updates were unavailable between saved checks",
                    source: "preview")
            }
        }
        #endif
        return model.matchupTimeline.events(scope: model.workspace?.storageScope, week: week, matchup: matchup)
    }
    private func eventRow(_ event: MatchupTimelineEvent) -> some View {
        VStack(alignment:.leading,spacing:5) {
            let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:5)) : AnyLayout(HStackLayout(alignment:.firstTextBaseline,spacing:8))
            layout {
                Text(event.name).font(.subheadline.weight(event.kind=="team" ? .semibold : .regular))
                if !typeSize.isAccessibilitySize { Spacer(minLength:8) }
                if let a=event.previous,let b=event.current {
                    Text("\(b-a>0 ? "+" : "")\((b-a).pointsText(precision:precision))")
                        .monospacedDigit().fontWeight(.medium)
                }
            }
            if let a=event.previous,let b=event.current {
                Text("\(a.pointsText(precision:precision)) → \(b.pointsText(precision:precision)) points")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(event.date.formatted(date:.omitted,time:.shortened)).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children:.combine)
    }
    private func refresh() async {
        guard let workspace=model.workspace else { return }
        await model.matchupTimeline.refresh(workspace:workspace,week:week,matchup:matchup,
            address:model.matchupActivity.backgroundSync.address,preview:model.isDemo)
    }
}
