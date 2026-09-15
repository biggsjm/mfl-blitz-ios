import Foundation

/// Preserve MFL's rule syntax. Unsupported formulas remain visible and never
/// get evaluated as executable expressions or silently replaced with PPR rules.
public struct MFLScoringRule: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let positions: [String]
    public let event: String
    public let label: String
    public let range: String
    public let points: String
    public let thresholdPoints: String?

    public init(id: Int, positions: [String], event: String, label: String, range: String, points: String, thresholdPoints: String? = nil) {
        self.id = id; self.positions = positions; self.event = event; self.label = label
        self.range = range; self.points = points; self.thresholdPoints = thresholdPoints
    }

    public static func decode(_ value: MFLJSONValue, descriptions: MFLJSONValue? = nil) throws -> [Self] {
        var labels: [String: String] = [:]
        let catalog = descriptions?.objectValue?["allRules"]?.objectValue?["rule"]?.arrayValue ?? []
        for row in catalog {
            if let code = row.objectValue?["abbreviation"]?.stringValue,
               let label = row.objectValue?["shortDescription"]?.stringValue { labels[code] = label }
        }
        guard let groups = value.objectValue?["rules"]?.objectValue?["positionRules"]?.arrayValue,
              !groups.isEmpty, groups.count <= 100 else { throw MFLCoreError.invalidResponse }
        var result: [Self] = []
        for group in groups {
            guard let raw = group.objectValue, let positions = raw["positions"]?.stringValue,
                  let rules = raw["rule"]?.arrayValue, rules.count <= 500 else { throw MFLCoreError.invalidResponse }
            let applicable = positions.split(separator: "|").map { String($0).uppercased() }
            guard !applicable.isEmpty else { throw MFLCoreError.invalidResponse }
            for rule in rules {
                guard let fields = rule.objectValue, let event = fields["event"]?.stringValue,
                      let range = fields["range"]?.stringValue, let points = fields["points"]?.stringValue,
                      !event.isEmpty, points.count <= 200, range.count <= 100 else { throw MFLCoreError.invalidResponse }
                result.append(Self(id: result.count, positions: applicable, event: event, label: labels[event] ?? event,
                    range: range, points: points, thresholdPoints: fields["thresholdPoints"]?.stringValue))
            }
        }
        guard !result.isEmpty, result.count <= 2000 else { throw MFLCoreError.invalidResponse }
        return result
    }

    public func applies(to position: String) -> Bool {
        func canonical(_ raw: String) -> String {
            let value=raw.uppercased()
            if ["DEF","DF","DST","D/ST"].contains(value) { return "DEF" }
            return value=="PK" ? "K" : value
        }
        return positions.contains { canonical($0)==canonical(position) }
    }

    /// A result of nil is explicitly unsupported, not zero. Per-event distance
    /// rules must be called with each distance, never a player's total yardage.
    public func calculate(value: Decimal) -> Decimal? {
        func finite(_ number: Decimal) -> Decimal? {
            let double=NSDecimalNumber(decimal:number).doubleValue
            return double.isFinite && abs(double)<=1_000_000_000 ? number : nil
        }
        guard finite(value) != nil else { return nil }
        guard let match = range.wholeMatch(of: /^(-?\d+(?:\.\d+)?)-(-?\d+(?:\.\d+)?)$/),
              let lower = Decimal(string: String(match.1)), let upper = Decimal(string: String(match.2)),
              lower <= upper else { return nil }
        guard value >= lower, value <= upper else { return 0 }
        // Threshold-base semantics vary by MFL rule type. Keep those visible
        // but unevaluated until the provider contract is verified.
        guard thresholdPoints == nil else { return nil }
        func decimal(_ text: String) -> Decimal? {
            guard text.wholeMatch(of: /^-?(?:\d+(?:\.\d*)?|\.\d+)$/) != nil else { return nil }
            return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        }
        if points.hasPrefix("*"), let multiplier = decimal(String(points.dropFirst())) {
            return finite(value * multiplier)
        }
        let parts = points.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 2, let numerator = decimal(String(parts[0])),
           let denominator = decimal(String(parts[1])), denominator > 0 {
            var quotient = value / denominator, whole = Decimal()
            NSDecimalRound(&whole, &quotient, 0, quotient < 0 ? .up : .down)
            return finite(whole * numerator)
        }
        return decimal(points).flatMap(finite)
    }
}
