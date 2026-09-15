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
            MatchupActivityScoreboard(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(MatchupActivityScoreboard.color(context.state.awayArtwork,
                    fallback: Color(red: 0.04, green: 0.30, blue: 0.70)))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.destination)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 8) {
                        Text("MFL Blitz - Week \(context.attributes.week)")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        MatchupActivityStatus(activePlayers: context.state.activePlayers, isStale: context.isStale, phase: context.state.phase,nextKickoff:context.state.nextKickoff, showAggregate: !context.state.hasTeamRemaining)
                    }
                }
                DynamicIslandExpandedRegion(.leading) { islandTeam(context, home: false) }
                DynamicIslandExpandedRegion(.trailing) { islandTeam(context, home: true) }
                DynamicIslandExpandedRegion(.bottom) {
                    MatchupActivityLatestChange(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    if context.isStale { Image(systemName: "clock").foregroundStyle(.secondary) }
                    else {
                        MatchupActivityTeamMark(image: MatchupActivityScoreboard.image(context.state.awayArtwork),
                            abbreviation: context.attributes.awayDisplayAbbreviation, size: 18)
                    }
                    Text(context.state.awayScore).monospacedDigit()
                }
                .accessibilityLabel("\(context.attributes.awayName), \(context.state.awayScore) points\(context.isStale ? ", update needed" : "")")
            } compactTrailing: {
                Text(context.state.homeScore).monospacedDigit()
                    .accessibilityLabel("\(context.attributes.homeName), \(context.state.homeScore) points")
            } minimal: {
                Image(systemName: context.isStale ? "clock" : "sportscourt")
                    .accessibilityLabel(context.isStale ? "Matchup needs an update" : "Your fantasy matchup")
            }
            .widgetURL(context.attributes.destination)
            .keylineTint(MatchupActivityScoreboard.color(context.state.awayArtwork, fallback: .cyan))
        }
    }

    private func islandTeam(_ context: ActivityViewContext<MatchupActivityAttributes>, home: Bool) -> some View {
        let name = home ? context.attributes.homeName : context.attributes.awayName
        let abbreviation = home ? context.attributes.homeDisplayAbbreviation : context.attributes.awayDisplayAbbreviation
        let score = home ? context.state.homeScore : context.state.awayScore
        let projection = context.state.projectionLabel(home: home, isStale: context.isStale)
        let artwork = home ? context.state.homeArtwork : context.state.awayArtwork
        return VStack(alignment: home ? .trailing : .leading, spacing: 3) {
            MatchupActivityTeamMark(image: MatchupActivityScoreboard.image(artwork), abbreviation: abbreviation, size: 24)
            Text(score).font(.system(size: 30, weight: .semibold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(abbreviation).font(.caption2.weight(.medium))
            if let projection { Text(projection).font(.caption2).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(.white.opacity(0.85)) }
            if let remaining=context.state.remainingLabel(home:home,isStale:context.isStale) {
                Text(remaining).font(.system(size:11)).lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.state.teamAccessibilityLabel(name: name, home: home, isStale: context.isStale))
    }
}
