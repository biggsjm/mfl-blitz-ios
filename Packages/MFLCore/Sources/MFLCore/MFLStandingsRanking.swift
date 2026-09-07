import Foundation

public struct MFLStandingPlace: Equatable, Sendable {
    public let position: Int
    public let isTied: Bool
    public init(position: Int, isTied: Bool = false) {
        self.position = position
        self.isTied = isTied
    }
}

/// API array position is not rank. Compare the configured criteria explicitly.
/// MFL documents H2H as pairwise, not a mini-league percentage. A cycle or
/// missing criterion makes that context unranked instead of inventing a winner.
public struct MFLStandingsRanking: Equatable, Sendable {
    public enum Issue: String, Equatable, Sendable {
        case awaitingResults, unavailable, unsupported, headToHeadUnavailable, ambiguous
    }
    public let places: [String: MFLStandingPlace]
    public let issue: Issue?

    public static func resolve(
        _ rows: [MFLStanding], criteria: String?, hasResults: Bool,
        schedule: MFLSchedule? = nil, startWeek: Int = 1,
        completedWeek: Int? = nil
    ) -> Self {
        guard hasResults else { return Self(places: [:], issue: .awaitingResults) }
        guard !rows.isEmpty, Set(rows.map(\.id)).count == rows.count else {
            return Self(places: [:], issue: .unavailable)
        }
        let rules = (criteria ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        guard !rules.isEmpty else { return Self(places: [:], issue: .unsupported) }
        // Do not silently ignore a custom/manual or unsupported sort criterion.
        guard rules.allSatisfy({ ["PCT", "H2H", "PTS", "DIVPCT"].contains($0) }) else {
            return Self(places: [:], issue: .unsupported)
        }
        let headToHeadIsConsistent = completedRecordsMatch(
            rows, schedule: schedule,
            startWeek: startWeek, completedWeek: completedWeek)
        var comparisons: [[Int]] = Array(repeating: Array(repeating: 0, count: rows.count), count: rows.count)
        var betterCounts = Array(repeating: 0, count: rows.count)
        for left in rows.indices {
            for right in rows.indices where right > left {
                var comparison = 0
                for rule in rules {
                    let values: (Decimal, Decimal)?
                    switch rule {
                    case "PCT": values = pair(percentage(rows[left]), percentage(rows[right]))
                    case "PTS": values = pair(rows[left].pointsFor, rows[right].pointsFor)
                    case "DIVPCT": values = pair(divisionPercentage(rows[left]), divisionPercentage(rows[right]))
                    case "H2H":
                        values =
                            headToHeadIsConsistent
                            ? headToHead(
                                rows[left].id, rows[right].id, schedule: schedule,
                                startWeek: startWeek, completedWeek: completedWeek) : nil
                    default: values = nil
                    }
                    guard let (a, b) = values, !a.isNaN, !b.isNaN else {
                        return Self(places: [:], issue: rule == "H2H" ? .headToHeadUnavailable : .unavailable)
                    }
                    if a != b {
                        comparison = a > b ? -1 : 1
                        break
                    }
                }
                comparisons[left][right] = comparison
                comparisons[right][left] = -comparison
                if comparison < 0 { betterCounts[right] += 1 }
                if comparison > 0 { betterCounts[left] += 1 }
            }
        }
        // A valid total preorder must agree with every pair. This catches H2H
        // cycles and non-transitive ties without passing an invalid comparator
        // to Swift's sorting algorithm.
        for left in rows.indices {
            for right in rows.indices {
                let expected =
                    betterCounts[left] == betterCounts[right] ? 0 : betterCounts[left] < betterCounts[right] ? -1 : 1
                guard comparisons[left][right] == expected else { return Self(places: [:], issue: .ambiguous) }
            }
        }
        var places: [String: MFLStandingPlace] = [:]
        for index in rows.indices {
            places[rows[index].id] = MFLStandingPlace(
                position: betterCounts[index] + 1,
                isTied: betterCounts.filter { $0 == betterCounts[index] }.count > 1)
        }
        return Self(places: places, issue: nil)
    }

    public static func hasReportedResults(
        _ rows: [MFLStanding], headToHead: Bool?,
        completedWeek: Int?, startWeek: Int
    ) -> Bool {
        if rows.contains(where: { ($0.wins ?? 0) > 0 || ($0.losses ?? 0) > 0 || ($0.ties ?? 0) > 0 }) { return true }
        // A zero record does not imply preseason for a points-only league.
        if headToHead == false {
            return rows.contains { ($0.pointsFor ?? 0) != 0 } || (completedWeek ?? 0) >= startWeek
        }
        return false
    }

    private static func pair(_ a: Decimal?, _ b: Decimal?) -> (Decimal, Decimal)? {
        guard let a, let b else { return nil }
        return (a, b)
    }

    private static func percentage(_ row: MFLStanding) -> Decimal? {
        guard let wins = row.wins, let losses = row.losses, let ties = row.ties,
            wins >= 0, losses >= 0, ties >= 0
        else { return nil }
        let games = Decimal(wins) + Decimal(losses) + Decimal(ties)
        return games > 0 ? (Decimal(wins) + Decimal(ties) / 2) / games : 0
    }

    private static func divisionPercentage(_ row: MFLStanding) -> Decimal? {
        guard let record = row.stringValue(for: "divwlt") else {
            guard let value = row.decimalValue(for: "divpct"), !value.isNaN, value >= 0, value <= 1 else { return nil }
            return value
        }
        let parts = record.components(separatedBy: "-")
        guard parts.count == 3 else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == 3, values.allSatisfy({ $0 >= 0 }) else { return nil }
        let games = values.reduce(Decimal.zero) { $0 + Decimal($1) }
        return games > 0 ? (Decimal(values[0]) + Decimal(values[2]) / 2) / games : 0
    }

    /// Do not combine preliminary/adjusted records with a different schedule
    /// horizon. Extra median wins or manual adjustments need MFL's report when
    /// they prevent an exact H2H reconciliation; simple earlier criteria can
    /// still resolve without needing H2H.
    private static func completedRecordsMatch(
        _ rows: [MFLStanding], schedule: MFLSchedule?,
        startWeek: Int, completedWeek: Int?
    ) -> Bool {
        guard let schedule, let completedWeek, startWeek > 0, completedWeek >= startWeek,
            completedWeek <= 22
        else { return false }
        let weeks = schedule.weeks.filter { (startWeek...completedWeek).contains($0.week) }
        guard Set(weeks.map(\.week)) == Set(startWeek...completedWeek),
            weeks.count == Set(weeks.map(\.week)).count
        else { return false }
        for row in rows {
            var wins = 0
            var losses = 0
            var ties = 0
            for week in weeks {
                let games = week.matchups.filter { $0.franchises.contains { $0.franchiseID == row.id } }
                guard !games.isEmpty else { return false }
                var seenOpponents: Set<String> = []
                for game in games {
                    // Explicit byes contribute no head-to-head game.
                    let participants = game.franchises.filter { $0.franchiseID != "0000" }
                    if participants.count == 1 { continue }
                    guard participants.count == 2, Set(participants.map(\.franchiseID)).count == 2,
                        let own = participants.first(where: { $0.franchiseID == row.id }),
                        let opponent = participants.first(where: { $0.franchiseID != row.id }),
                        seenOpponents.insert(opponent.franchiseID).inserted,
                        own.score != nil, opponent.score != nil
                    else { return false }
                    switch (own.result?.uppercased(), opponent.result?.uppercased()) {
                    case ("W", "L"): wins += 1
                    case ("L", "W"): losses += 1
                    case ("T", "T"): ties += 1
                    default: return false
                    }
                }
            }
            guard row.wins == wins, row.losses == losses, row.ties == ties else { return false }
        }
        return true
    }

    private static func headToHead(
        _ a: String, _ b: String, schedule: MFLSchedule?,
        startWeek: Int, completedWeek: Int?
    ) -> (Decimal, Decimal)? {
        guard let schedule, let completedWeek, completedWeek >= startWeek else { return nil }
        let weeks = schedule.weeks.filter { (startWeek...completedWeek).contains($0.week) }
        guard Set(weeks.map(\.week)) == Set(startWeek...completedWeek),
            weeks.count == Set(weeks.map(\.week)).count
        else { return nil }
        var aWins = Decimal.zero
        var bWins = Decimal.zero
        for week in weeks {
            for game in week.matchups {
                guard game.franchises.contains(where: { $0.franchiseID == a }),
                    game.franchises.contains(where: { $0.franchiseID == b })
                else { continue }
                guard game.franchises.count == 2,
                    let left = game.franchises.first(where: { $0.franchiseID == a }),
                    let right = game.franchises.first(where: { $0.franchiseID == b })
                else { return nil }
                switch (left.result?.uppercased(), right.result?.uppercased()) {
                case ("W", "L"): aWins += 1
                case ("L", "W"): bWins += 1
                case ("T", "T"):
                    // Future/unscored MFL games can also say T. Only a completed
                    // week with both real scores proves a played tie.
                    guard left.score != nil, right.score != nil else { return nil }
                    aWins += Decimal(string: "0.5")!
                    bWins += Decimal(string: "0.5")!
                default: return nil
                }
            }
        }
        return (aWins, bWins)
    }
}
