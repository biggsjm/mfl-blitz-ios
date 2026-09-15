import ActivityKit
import Foundation

/// Small, credential-free content shared by the app and its Live Activity.
struct MatchupActivityAttributes: ActivityAttributes {
    struct ScoreChange: Codable, Hashable, Sendable {
        var text: String
        /// Observation time, not an NFL play timestamp.
        var checkedAt: Date
        var playerID: String? = nil
    }

    struct Artwork: Codable, Hashable, Sendable {
        var imageData: Data?
        var red: Double
        var green: Double
        var blue: Double

        init(imageData: Data?, red: Double, green: Double, blue: Double) {
            self.imageData = imageData; self.red = red; self.green = green; self.blue = blue
        }

        private enum CodingKeys: String, CodingKey { case imageData, thumbnail, red, green, blue }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            red = try values.decode(Double.self, forKey: .red)
            green = try values.decode(Double.self, forKey: .green)
            blue = try values.decode(Double.self, forKey: .blue)
            if let thumbnail = try values.decodeIfPresent(String.self, forKey: .thumbnail) {
                imageData = Data(base64Encoded: thumbnail.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"))
            } else { imageData = try values.decodeIfPresent(Data.self, forKey: .imageData) }
        }

        func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(red, forKey: .red)
            try values.encode(green, forKey: .green)
            try values.encode(blue, forKey: .blue)
            // JSON escaping of '/' can double a JPEG's Base64 size and discard
            // both logos at the payload guard. This alphabet keeps the size fixed.
            let thumbnail = imageData?.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            try values.encodeIfPresent(thumbnail, forKey: .thumbnail)
        }
    }

    struct ContentState: Codable, Hashable, Sendable {
        var homeScore: String
        var awayScore: String
        var activePlayers: Int
        var updatedAt: Date
        var homeProjection: String? = nil
        var awayProjection: String? = nil
        var homePoints: Double? = nil
        var awayPoints: Double? = nil
        /// Labeled as since the previous check, never as a play-by-play event.
        var homeChange: String? = nil
        var awayChange: String? = nil
        var homeRecord: String? = nil
        var awayRecord: String? = nil
        var latestChange: ScoreChange? = nil
        var homeArtwork: Artwork? = nil
        var awayArtwork: Artwork? = nil
        /// Server-confirmed lifecycle; omitted by older foreground-only builds.
        var phase: String? = nil
        var homePlaying: Int? = nil
        var awayPlaying: Int? = nil
        var homeYetToPlay: Int? = nil
        var awayYetToPlay: Int? = nil
        var nextKickoff: Date? = nil
        var statContext: String? = nil
        var continuationNeeded: Bool? = nil

        func remainingLabel(home: Bool, isStale: Bool) -> String? {
            guard phase != "final", !isStale else { return nil }
            let playing = home ? homePlaying : awayPlaying
            let waiting = home ? homeYetToPlay : awayYetToPlay
            guard let playing, let waiting else { return nil }
            return "\(playing) playing · \(waiting) yet to play"
        }

        var hasTeamRemaining: Bool {
            homePlaying != nil && awayPlaying != nil && homeYetToPlay != nil && awayYetToPlay != nil
        }

        func teamAccessibilityLabel(name: String, home: Bool, isStale: Bool) -> String {
            let score = home ? homeScore : awayScore
            return "\(name), \(score) points" +
                (projectionLabel(home: home, isStale: isStale).map { ", \($0)" } ?? "") +
                (remainingLabel(home: home, isStale: isStale).map { ", \($0)" } ?? "") +
                (isStale ? ", scores delayed" : phase == "final" ? ", final" : "")
        }

        /// An app relaunch or failed logo download must not erase delivered art.
        /// Call only after matching the activity's league, week and teams.
        func preservingArtwork(from previous: Self?) -> Self {
            var value = self
            func merge(_ incoming: Artwork?, _ saved: Artwork?) -> Artwork? {
                guard var incoming else { return saved }
                if incoming.imageData == nil, let saved,
                   incoming.red == saved.red, incoming.green == saved.green, incoming.blue == saved.blue {
                    incoming.imageData = saved.imageData
                }
                return incoming
            }
            value.homeArtwork = merge(homeArtwork, previous?.homeArtwork)
            value.awayArtwork = merge(awayArtwork, previous?.awayArtwork)
            return value
        }

        /// APNs can advance scores while local artwork is being prepared.
        /// Keep the freshest score receipt without dropping either side's art.
        func reconciling(with observed: Self?) -> Self {
            guard let observed else { return self }
            return observed.updatedAt > updatedAt
                ? observed.preservingArtwork(from: self)
                : preservingArtwork(from: observed)
        }

        func projectionLabel(home: Bool, isStale: Bool) -> String? {
            guard phase != "final" else { return nil }
            let projection = isStale ? nil : (home ? homeProjection : awayProjection)
            return "Live est. \(projection ?? "—")"
        }

        /// ActivityKit's combined static/dynamic payload is limited to 4 KB.
        /// Normal thumbnails fit; unusual long UTF-8 names retain colors/initials.
        func fittingActivityBudget(attributes: MatchupActivityAttributes) -> Self {
            var value = self
            let encoder = JSONEncoder()
            let fixedBytes = (try? encoder.encode(attributes).count) ?? 4_096
            if fixedBytes + ((try? encoder.encode(value).count) ?? 4_096) > 3_900 {
                value.homeArtwork?.imageData = nil
                value.awayArtwork?.imageData = nil
            }
            return value
        }
    }

    var scope: String
    var week: Int
    var matchupID: String
    var homeName: String
    var awayName: String
    var homeAbbreviation: String
    var awayAbbreviation: String
    var backgroundPush: Bool? = nil
    var homeID: String? = nil
    var awayID: String? = nil

    var homeDisplayAbbreviation: String { Self.displayAbbreviation(homeAbbreviation, name: homeName) }
    var awayDisplayAbbreviation: String { Self.displayAbbreviation(awayAbbreviation, name: awayName) }

    static func displayAbbreviation(_ abbreviation: String, name: String) -> String {
        let supplied = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        if supplied.contains(where: \.isLetter) { return String(supplied.prefix(5)) }
        let initials = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap(\.first)
        return initials.isEmpty ? "TEAM" : String(initials.prefix(4)).uppercased()
    }

    var destination: URL? {
        var parts = URLComponents()
        parts.scheme = "mflblitz"
        parts.host = "matchup"
        parts.queryItems = [URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "week", value: String(week)),
            URLQueryItem(name: "id", value: matchupID)]
        return parts.url
    }
}
