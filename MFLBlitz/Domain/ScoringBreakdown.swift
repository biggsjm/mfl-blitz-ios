import Foundation
import MFLCore

struct ScoringBreakdown {
    struct Item: Identifiable {
        let rule: MFLScoringRule
        let stat: Decimal?
        let points: Decimal?
        var id: Int { rule.id }
    }
    let items: [Item]
    let official: Decimal?
    var total: Decimal { items.compactMap(\.points).reduce(0, +) }
    var difference: Decimal? { official.map { $0 - total } }
    var contributions: [Item] { items.filter { $0.points != nil && $0.points != 0 } }
    var remaining: [Item] { items.filter { $0.points == nil || $0.points == 0 } }

    func compactExplanation(precision: Int) -> String? {
        guard !items.isEmpty else { return nil }
        let labels = ["PY":"Pass yd", "PC":"Completions", "#P":"Pass TD", "IN":"INT thrown", "RY":"Rush yd",
                      "#R":"Rush TD", "CY":"Rec yd", "CC":"Receptions", "#C":"Rec TD", "FL":"Fumbles lost",
                      "P2":"Pass 2PT", "R2":"Rush 2PT", "C2":"Rec 2PT", "SK":"Sacks", "IC":"INT", "TPA":"Points allowed"]
        let parts = contributions.map { item in
            "\(labels[item.rule.event] ?? item.rule.label) \(NSDecimalNumber(decimal: item.points ?? 0).doubleValue.pointsText(precision: precision))"
        }
        let mismatch = difference.map { abs(NSDecimalNumber(decimal: $0).doubleValue) >= pow(10, -Double(precision)) / 2 } ?? false
        let arithmetic = parts.isEmpty ? "" : "Points: " + parts.joined(separator: " · ")
        if mismatch { return arithmetic + (arithmetic.isEmpty ? "" : ". ") + "Some points aren’t explained yet." }
        return arithmetic.isEmpty ? nil : arithmetic
    }

    init(rules: [MFLScoringRule], position: String, player: NFLFeedPlayer?, official: Double?) {
        self.official = official.flatMap { $0.isFinite ? Decimal(string: String($0)) : nil }
        let stats = player.map(Self.stats) ?? [:]
        items = rules.filter { $0.applies(to: position) }.map { rule in
            let stat = stats[rule.event]
            return Item(rule: rule, stat: stat, points: stat.flatMap(rule.calculate))
        }
    }

    /// Map only fields whose meaning agrees with MFL's allRules catalog.
    /// Missing groups/values stay unknown, and individual defense is never
    /// substituted for an aggregate fantasy D/ST slot.
    static func stats(_ player: NFLFeedPlayer) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        let mappings: [String: [String: String]] = [
            "team defense": ["sk":"SK","ic":"IC","fc":"FC","sf":"SF","#ir":"#IR","tpa":"TPA"],
            "passing": ["yards": "PY", "passing touch downs": "#P", "interceptions": "IN", "two pt": "P2"],
            "rushing": ["yards": "RY", "total rushes": "RA", "rushing touch downs": "#R", "two pt": "R2"],
            "receiving": ["yards": "CY", "total receptions": "CC", "receiving touch downs": "#C", "two pt": "C2"],
            "fumbles": ["lost": "FL"],
            "kick_returns": ["yards": "KY"], "punt_returns": ["yards": "UY", "td": "#UT"]]
        for group in player.groups {
            let values = Dictionary(grouping: group.stats, by: { $0.name.lowercased() })
                .compactMapValues { $0.count == 1 ? $0[0].value : nil }
            func number(_ name: String) -> Decimal? {
                guard let raw = values[name], raw.wholeMatch(of: /^-?(?:\d+(?:\.\d*)?|\.\d+)$/) != nil,
                      let value = Decimal(string: raw), abs(NSDecimalNumber(decimal: value).doubleValue) <= 100_000 else { return nil }
                return value
            }
            for (field, event) in mappings[group.name.lowercased()] ?? [:] { result[event] = number(field) }
            if group.name.lowercased() == "passing", let raw = values["comp att"],
               let match = raw.wholeMatch(of: /^(\d+)\/(\d+)$/),
               let completed = Decimal(string: String(match.1)), let attempted = Decimal(string: String(match.2)), completed <= attempted {
                result["PC"] = completed; result["PA"] = attempted
            }
            if group.name.lowercased() == "kicking", let raw = values["extra point"],
               let match = raw.wholeMatch(of: /^(\d+)\/(\d+)$/),
               let made = Decimal(string: String(match.1)), let attempts = Decimal(string: String(match.2)), made <= attempts {
                result["EP"] = made; result["EM"] = attempts - made
            }
            if group.name.lowercased() == "kick_returns" { result["#KT"] = number("td") ?? number("kick return td") }
        }
        return result
    }

    static let previewRules: [MFLScoringRule] = [
        .init(id: 0, positions: ["QB","RB","WR","TE"], event: "#P", label: "Passing touchdowns", range: "0-99", points: "*6"),
        .init(id: 1, positions: ["QB","RB","WR","TE"], event: "PY", label: "Passing yards", range: "0-999", points: "1/50"),
        .init(id: 2, positions: ["QB","RB","WR","TE"], event: "PC", label: "Completions", range: "0-99", points: "*.5"),
        .init(id: 3, positions: ["QB","RB","WR","TE"], event: "IN", label: "Interceptions thrown", range: "0-99", points: "*-2"),
        .init(id: 4, positions: ["QB","RB","WR","TE"], event: "RY", label: "Rushing yards", range: "0-999", points: "1/10"),
        .init(id: 5, positions: ["QB","RB","WR","TE"], event: "CY", label: "Receiving yards", range: "0-999", points: "1/15"),
        .init(id: 6, positions: ["QB","RB","WR","TE"], event: "CC", label: "Receptions", range: "0-99", points: "*1"),
        .init(id: 7, positions: ["QB","RB","WR","TE"], event: "#C", label: "Receiving touchdowns", range: "0-99", points: "*6")]
}
