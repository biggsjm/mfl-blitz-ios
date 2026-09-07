import ActivityKit
import WidgetKit
import SwiftUI

@main
struct BlitzActivityBundle: WidgetBundle {
    var body: some Widget { MatchupLiveActivity() }
}

struct MatchupLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchupActivityAttributes.self) { context in
            VStack(spacing: 12) {
                HStack {
                    Label("Week \(context.attributes.week)", systemImage: "sportscourt")
                    Spacer()
                    status(context)
                }.font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top) {
                    team(context.attributes.awayName, score: context.state.awayScore, alignment: .leading)
                    Text("vs").font(.caption).foregroundStyle(.secondary).padding(.top, 7)
                    team(context.attributes.homeName, score: context.state.homeScore, alignment: .trailing)
                }
                HStack {
                    Text("Updated \(context.state.updatedAt, style: .time)")
                    Spacer()
                    Text(context.isStale ? "Open Blitz to update" : "MFL Blitz")
                }.font(.caption2).foregroundStyle(.secondary)
            }
            .padding(16)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(context.attributes.destination)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    team(context.attributes.awayName, score: context.state.awayScore, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    team(context.attributes.homeName, score: context.state.homeScore, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Week \(context.attributes.week)")
                        Spacer()
                        status(context)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: context.isStale ? "clock" : "sportscourt")
                        .foregroundStyle(context.isStale ? Color.secondary : Color.green)
                    Text(context.state.awayScore).monospacedDigit()
                }.accessibilityLabel("\(context.attributes.awayName), \(context.state.awayScore) points\(context.isStale ? ", update needed" : "")")
            } compactTrailing: {
                Text(context.state.homeScore).monospacedDigit()
                    .accessibilityLabel("\(context.attributes.homeName), \(context.state.homeScore) points")
            } minimal: {
                Image(systemName: context.isStale ? "clock" : "sportscourt")
                    .accessibilityLabel(context.isStale ? "Matchup needs an update" : "Your fantasy matchup")
            }
            .widgetURL(context.attributes.destination)
            .keylineTint(.green)
        }
    }

    private func team(_ name: String, score: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(score).font(.title2.bold()).monospacedDigit()
            Text(name).font(.caption).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func status(_ context: ActivityViewContext<MatchupActivityAttributes>) -> some View {
        Text(context.isStale ? "Update needed" : "\(context.state.activePlayers) playing")
    }
}
