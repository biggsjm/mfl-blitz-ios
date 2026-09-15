import SwiftUI

/// Focus on starters whose NFL games are in progress, using the same cached
/// snapshots as Lineups. Full rosters remain available in the other segment.
struct MatchupModeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let matchup: Matchup
    let week: Int
    let precision: Int
    let showLineups: () -> Void

    private func grouped(_ team: MatchupTeam) -> MatchupModeTeam {
        MatchupModeTeam(team: team, week: week, scope: model.workspace?.storageScope,
            feed: model.workspace.flatMap { model.usesNFLStats ? model.nflStats.feed(season: $0.season, week: week) : nil },
            availability: model.playerTools.availability[week], scoringGames: model.scoringGames[week])
    }

    var body: some View {
        let away = grouped(matchup.away), home = grouped(matchup.home)
        let live = away.entries(in: .inProgress) + home.entries(in: .inProgress)
        let unavailable = away.entries(in: .unavailable) + home.entries(in: .unavailable)
        VStack(spacing: 12) {
            if live.isEmpty {
                ContentUnavailableView(
                    unavailable.isEmpty ? "No starters playing" : "Game status unavailable",
                    systemImage: "figure.american.football",
                    description: Text(unavailable.isEmpty ? "Your full matchup is in Lineups." : "Check Lineups for the latest available scores."))
                if unavailable.isEmpty, let next = [away.nextKickoff, home.nextKickoff].compactMap({ $0 }).min() {
                    Text("Next kickoff \(next.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Show lineups", action: showLineups).buttonStyle(.bordered)
            } else {
                VStack(spacing: 14) {
                    if typeSize.isAccessibilitySize {
                        column(away, team: matchup.away, trailing: false)
                        column(home, team: matchup.home, trailing: true)
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            teamHeading(matchup.away, trailing: false)
                            teamHeading(matchup.home, trailing: true)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            column(away, team: matchup.away, trailing: false)
                            column(home, team: matchup.home, trailing: true)
                        }
                    }
                }
                if !unavailable.isEmpty {
                    Text("Some game statuses are unavailable. Check Lineups for all starters.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func teamHeading(_ team: MatchupTeam, trailing: Bool) -> some View {
        Text(team.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .multilineTextAlignment(trailing ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    private func column(_ group: MatchupModeTeam, team: MatchupTeam, trailing: Bool) -> some View {
        let isTrailing = trailing && !typeSize.isAccessibilitySize
        return VStack(alignment: isTrailing ? .trailing : .leading, spacing: 6) {
            if typeSize.isAccessibilitySize { teamHeading(team, trailing: false) }
            if group.entries(in: .inProgress).isEmpty {
                Text("No starters playing").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(group.entries(in: .inProgress)) { entry in
                MatchupPlayerCell(player: entry.player, teamName: team.name, teamID: team.id,
                    side: isTrailing ? .home : .away, scorePrecision: precision, showsGameDayStatus: true)
                .id("live-player-\(team.id)-\(entry.id)")
            }
        }.frame(maxWidth: .infinity, alignment: isTrailing ? .topTrailing : .topLeading)
    }
}
