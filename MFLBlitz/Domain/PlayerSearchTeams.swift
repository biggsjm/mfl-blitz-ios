import Foundation
import MFLCore

/// Search vocabulary only; never rewrites a player's source NFL affiliation.
enum PlayerSearchTeams {
    struct Team: Sendable {
        let codes: [String]
        let name: String
        var searchTerms: String { codes.joined(separator: " ") + " " + name }
    }

    static let all: [Team] = [
        .init(codes: ["ARI", "ARZ", "AZ"], name: "Arizona Cardinals"),
        .init(codes: ["ATL"], name: "Atlanta Falcons"),
        .init(codes: ["BAL"], name: "Baltimore Ravens"),
        .init(codes: ["BUF"], name: "Buffalo Bills"),
        .init(codes: ["CAR"], name: "Carolina Panthers"),
        .init(codes: ["CHI"], name: "Chicago Bears"),
        .init(codes: ["CIN"], name: "Cincinnati Bengals"),
        .init(codes: ["CLE"], name: "Cleveland Browns"),
        .init(codes: ["DAL"], name: "Dallas Cowboys"),
        .init(codes: ["DEN"], name: "Denver Broncos"),
        .init(codes: ["DET"], name: "Detroit Lions"),
        .init(codes: ["GBP", "GB"], name: "Green Bay Packers"),
        .init(codes: ["HOU"], name: "Houston Texans"),
        .init(codes: ["IND"], name: "Indianapolis Colts"),
        .init(codes: ["JAC", "JAX"], name: "Jacksonville Jaguars"),
        .init(codes: ["KCC", "KC"], name: "Kansas City Chiefs"),
        .init(codes: ["LVR", "LV"], name: "Las Vegas Raiders"),
        .init(codes: ["LAC"], name: "Los Angeles Chargers"),
        .init(codes: ["LAR"], name: "Los Angeles Rams"),
        .init(codes: ["MIA"], name: "Miami Dolphins"),
        .init(codes: ["MIN"], name: "Minnesota Vikings"),
        .init(codes: ["NEP", "NE"], name: "New England Patriots Pats"),
        .init(codes: ["NOS", "NO"], name: "New Orleans Saints"),
        .init(codes: ["NYG"], name: "New York Giants"),
        .init(codes: ["NYJ"], name: "New York Jets"),
        .init(codes: ["PHI"], name: "Philadelphia Eagles"),
        .init(codes: ["PIT"], name: "Pittsburgh Steelers"),
        .init(codes: ["SEA"], name: "Seattle Seahawks"),
        .init(codes: ["SFO", "SF"], name: "San Francisco 49ers Niners"),
        .init(codes: ["TBB", "TB"], name: "Tampa Bay Buccaneers Bucs"),
        .init(codes: ["TEN"], name: "Tennessee Titans"),
        .init(codes: ["WAS", "WSH"], name: "Washington Commanders")
    ]
    private static let byCode: [String: Team] = Dictionary(uniqueKeysWithValues:
        all.flatMap { team in team.codes.map { ($0.lowercased(), team) } })

    static func team(for code: String?) -> Team? {
        code.flatMap { byCode[$0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] }
    }

    static func canonicalCode(_ code: String?) -> String? { team(for: code)?.codes.first }
}

enum PlayerSearchPositions {
    static func canonical(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "K", "PK": "PK"
        case "D/ST", "DST", "DEF": "DEF"
        default: value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
    }

    /// Explicit rules are respected, including 0-N flex limits and team units.
    /// Unknown/compound rules keep the broader index instead of guessing which
    /// legitimate players should be hidden.
    static func eligible(in league: MFLLeague) -> Set<String>? {
        guard !league.starterRequirements.isEmpty else { return nil }
        var positions: Set<String> = []
        for rule in league.starterRequirements {
            let position = canonical(rule.position)
            guard known.contains(position) else { return nil }
            guard let minimum = rule.minimum,
                  let maximum = rule.maximum, maximum >= minimum else { return nil }
            if maximum > 0 { positions.formUnion(expanded(position)) }
        }
        return positions.isEmpty ? nil : positions
    }

    static func expanded(_ position: String) -> Set<String> {
        switch canonical(position) {
        case "DL": ["DL", "DE", "DT"]
        case "DB": ["DB", "CB", "S"]
        default: [canonical(position)]
        }
    }

    static func isTeamUnit(_ position: String?) -> Bool {
        guard let position else { return false }
        let code = canonical(position)
        return code.hasPrefix("TM") || ["DEF", "ST", "OFF", "COACH"].contains(code)
    }

    static let known: Set<String> = ["QB", "RB", "FB", "WR", "TE", "PK", "PN", "P", "DEF", "ST", "OFF", "COACH",
        "DL", "DE", "DT", "LB", "DB", "CB", "S", "TMWR", "TMRB", "TMQB", "TMTE", "TMPK", "TMPN", "TMDL", "TMLB", "TMDB"]
}
