import SwiftUI

/// Shared with the app target so the actual extension layout can be rendered in tests.
struct MatchupActivityScoreboard: View {
    let attributes: MatchupActivityAttributes
    let state: MatchupActivityAttributes.ContentState
    var isStale = false

    var body: some View {
        let awayImage = Self.image(state.awayArtwork)
        let homeImage = Self.image(state.homeArtwork)
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                MatchupActivityTeamMark(image: awayImage, abbreviation: attributes.awayDisplayAbbreviation, size: 24)
                Text("MFL Blitz - Week \(attributes.week)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity)
                MatchupActivityTeamMark(image: homeImage, abbreviation: attributes.homeDisplayAbbreviation, size: 24)
            }
            HStack(alignment: .center, spacing: 8) {
                team(home: false)
                MatchupActivityStatus(activePlayers: state.activePlayers, isStale: isStale, phase: state.phase, nextKickoff:state.nextKickoff, showAggregate: !state.hasTeamRemaining)
                    .frame(width: 52)
                team(home: true)
            }
            MatchupActivityLatestChange(state: state, isStale: isStale)
        }
        .padding(.horizontal, 14).padding(.vertical, 1)
        .foregroundStyle(.white)
        .background {
            let away = Self.color(state.awayArtwork, fallback: Color(red: 0.04, green: 0.30, blue: 0.70))
            let home = Self.color(state.homeArtwork, fallback: Color(red: 0.02, green: 0.43, blue: 0.46))
            LinearGradient(stops: [.init(color: away, location: 0), .init(color: away, location: 0.20),
                                   .init(color: home, location: 0.80), .init(color: home, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .accessibilityElement(children: .contain)
    }

    private func team(home: Bool) -> some View {
        let name = home ? attributes.homeName : attributes.awayName
        let score = home ? state.homeScore : state.awayScore
        let projection = state.projectionLabel(home: home, isStale: isStale)
        let remaining = state.remainingLabel(home: home, isStale: isStale)
        return VStack(spacing: 2) {
            Text(score).font(.system(size: 40, weight: .semibold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            if let projection { Text(projection).font(.system(size: 10)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(.white.opacity(0.95)) }
            if let remaining { Text(remaining).font(.system(size:10)).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.95)) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.teamAccessibilityLabel(name: name, home: home, isStale: isStale))
    }

    static func image(_ artwork: MatchupActivityAttributes.Artwork?) -> UIImage? {
        guard let data = artwork?.imageData else { return nil }
        return UIImage(data: data)
    }

    static func color(_ artwork: MatchupActivityAttributes.Artwork?, fallback: Color) -> Color {
        guard let artwork else { return fallback }
        return Color(red: artwork.red, green: artwork.green, blue: artwork.blue)
    }
}

struct MatchupActivityTeamMark: View {
    var image: UIImage?
    let abbreviation: String
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else {
                Text(abbreviation).font(.system(size: 10, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.65)
                    .padding(3).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.14))
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityHidden(true)
    }
}

struct MatchupActivityStatus: View {
    let activePlayers: Int
    var isStale = false
    var phase: String? = nil
    var nextKickoff: Date? = nil
    var showAggregate = true
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: isStale ? "clock" : "circle.fill").font(.system(size: isStale ? 10 : 5))
                    .foregroundStyle(isStale ? Color.white.opacity(0.95) : Color(red: 0.70, green: 0.96, blue: 0.37))
                    .accessibilityHidden(true)
                Text(isStale ? "Delayed" : phase == "final" ? "Final" : phase == "waiting" ? (nextKickoff == nil ? "Between" : "Next") : "Live").font(.system(size: 12, weight: .semibold))
            }
            if !isStale,phase == "waiting",let nextKickoff {
                Text(nextKickoff,style:.time).font(.system(size:10)).foregroundStyle(.white.opacity(0.95))
            } else if isStale || phase == "final" || phase == "waiting" || showAggregate {
                Text(isStale ? "Open Blitz" : phase == "final" ? "MFL score" : phase == "waiting" ? "games" : "\(activePlayers) playing")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.95))
            }
        }.foregroundStyle(.white).fixedSize()
    }
}

struct MatchupActivityLatestChange: View {
    let state: MatchupActivityAttributes.ContentState
    var isStale = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5).padding(.bottom, 3)
            if state.continuationNeeded == true, state.phase != "final" {
                Text("Open Blitz to continue following this matchup").font(.system(size:11,weight:.medium)).lineLimit(1).minimumScaleFactor(0.8)
            } else if isStale {
                Text("Open Blitz to update scores").font(.system(size: 12, weight: .medium))
            } else if let change = state.latestChange {
                Text(change.text).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityLabel("Latest observed score change: \(change.text). Since the prior MFL check, not a play-by-play event.")
            }
            HStack(spacing: 4) {
                if !isStale,let context = state.statContext {
                    Text("Game totals: \(context)").lineLimit(2)
                } else if !isStale, let change = state.latestChange {
                    Text("Last change \(change.checkedAt, style: .time)")
                } else { Text(isStale ? "Scores delayed" : "MyFantasyLeague scoring") }
                Spacer(minLength: 6)
                Text("Checked \(state.updatedAt, style: .time)")
            }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.95)).lineLimit(1)
        }.foregroundStyle(.white)
    }
}
