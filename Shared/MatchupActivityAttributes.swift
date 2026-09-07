import ActivityKit
import Foundation

/// Small, credential-free content shared by the app and its Live Activity.
struct MatchupActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var homeScore: String
        var awayScore: String
        var activePlayers: Int
        var updatedAt: Date
    }

    var scope: String
    var week: Int
    var matchupID: String
    var homeName: String
    var awayName: String
    var homeAbbreviation: String
    var awayAbbreviation: String

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
