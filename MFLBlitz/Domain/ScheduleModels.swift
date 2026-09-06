import Foundation
import MFLCore

enum SeasonScheduleGameState: Equatable, Sendable {
    case scheduled
    case current
    case completed
    case unknown

    var label: String {
        switch self {
        case .scheduled: "Upcoming"
        case .current: "This week"
        case .completed: "Final"
        case .unknown: "Scheduled"
        }
    }
}

enum SeasonScheduleResult: String, Equatable, Sendable {
    case win = "W"
    case loss = "L"
    case tie = "T"
}

struct SeasonScheduleParticipant: Equatable, Sendable {
    let franchiseID: String
    let score: Decimal?
    let isHome: Bool?
    let rawResult: String?

    /// Only an explicit textual BYE is classified here. An absent opponent,
    /// unknown identifier, or "0000" is not assumed to mean a bye.
    var isExplicitBye: Bool { franchiseID.uppercased() == "BYE" }
}

struct SeasonScheduleMatchup: Identifiable, Equatable, Sendable {
    let id: String
    let sourceMatchupID: String?
    let week: Int
    let participants: [SeasonScheduleParticipant]
    let state: SeasonScheduleGameState

    var isExplicitBye: Bool { participants.contains(where: \.isExplicitBye) }
    var hasReportedScores: Bool {
        participants.count == 2 && !isExplicitBye && participants.allSatisfy { $0.score != nil }
    }
    var canOpenMatchup: Bool { participants.count == 2 && !isExplicitBye }

    func includes(franchiseID: String) -> Bool {
        participants.contains { $0.franchiseID == franchiseID }
    }

    func result(for franchiseID: String) -> SeasonScheduleResult? {
        guard state == .completed, hasReportedScores,
              let result = participants.first(where: { $0.franchiseID == franchiseID })?.rawResult
        else { return nil }
        return SeasonScheduleResult(rawValue: result.uppercased())
    }
}

struct SeasonScheduleWeek: Identifiable, Equatable, Sendable {
    let week: Int
    let matchups: [SeasonScheduleMatchup]
    let isPlayoff: Bool

    var id: Int { week }
}

struct SeasonScheduleSnapshot: Equatable, Sendable {
    let season: Int
    let leagueID: String
    let startWeek: Int
    let endWeek: Int
    let lastRegularSeasonWeek: Int?
    let currentWeek: Int?
    let completedWeek: Int?
    let weeks: [SeasonScheduleWeek]
    let fetchedAt: Date

    var firstUpcomingWeek: Int? {
        if let completedWeek, completedWeek >= endWeek { return nil }
        let next = max(startWeek, currentWeek ?? startWeek, (completedWeek ?? (startWeek - 1)) + 1)
        return next <= endWeek ? next : nil
    }

    var hasRemainingWeeks: Bool { firstUpcomingWeek != nil }
    var weekIsConfirmed: Bool { currentWeek != nil && completedWeek != nil }

    func filteredWeeks(franchiseID: String?) -> [SeasonScheduleWeek] {
        guard let franchiseID else { return weeks }
        return weeks.map { week in
            SeasonScheduleWeek(week: week.week,
                matchups: week.matchups.filter { $0.includes(franchiseID: franchiseID) },
                isPlayoff: week.isPlayoff)
        }
    }

    func matchup(id: String, week: Int) -> SeasonScheduleMatchup? {
        weeks.first(where: { $0.week == week })?.matchups.first(where: { $0.id == id })
    }

    /// Retains configured but unscheduled weeks. It does not invent opponents,
    /// results, or playoff qualification from an empty schedule entry.
    init(source: MFLSchedule, season: Int, leagueID: String,
         startWeek: Int? = nil, endWeek: Int? = nil, lastRegularSeasonWeek: Int? = nil,
         currentWeek: Int? = nil, completedWeek: Int? = nil, fetchedAt: Date = Date()) {
        let validWeeks = source.weeks.filter { (1...99).contains($0.week) }
        let configuredStart = startWeek.flatMap { (1...99).contains($0) ? $0 : nil }
        let configuredEnd = endWeek.flatMap { (1...99).contains($0) ? $0 : nil }
        let first = configuredStart ?? validWeeks.map(\.week).min() ?? 1
        let last = max(first, configuredEnd ?? validWeeks.map(\.week).max() ?? first)
        let regularEnd = lastRegularSeasonWeek.flatMap { (first...last).contains($0) ? $0 : nil }
        let confirmedCurrent = currentWeek.flatMap { (1...99).contains($0) ? $0 : nil }
        let confirmedCompleted = completedWeek.flatMap { (0...99).contains($0) ? $0 : nil }
        self.season = season
        self.leagueID = leagueID
        self.startWeek = first
        self.endWeek = last
        self.lastRegularSeasonWeek = regularEnd
        self.currentWeek = confirmedCurrent
        self.completedWeek = confirmedCompleted
        self.fetchedAt = fetchedAt

        guard !validWeeks.isEmpty || (configuredStart != nil && configuredEnd != nil) else {
            weeks = []
            return
        }
        let grouped = Dictionary(grouping: validWeeks, by: \.week)
        weeks = (first...last).map { week in
            let state: SeasonScheduleGameState
            if let confirmedCompleted, week <= confirmedCompleted {
                state = .completed
            } else if let confirmedCurrent, week == confirmedCurrent {
                state = .current
            } else if let confirmedCurrent, week > confirmedCurrent {
                state = .scheduled
            } else {
                state = .unknown
            }
            var occurrences: [String: Int] = [:]
            let matchups = (grouped[week] ?? []).flatMap(\.matchups).map { matchup in
                let participants = matchup.franchises.map {
                    SeasonScheduleParticipant(franchiseID: $0.franchiseID, score: $0.score,
                        isHome: $0.isHome, rawResult: $0.result)
                }
                let pair = participants.map {
                    "\($0.franchiseID.utf8.count):\($0.franchiseID):\($0.isHome.map { $0 ? "H" : "A" } ?? "U")"
                }.sorted().joined(separator: "|")
                let suppliedID = matchup.id.flatMap { $0.isEmpty ? nil : $0 }
                let identity = suppliedID.map { "source:\($0.utf8.count):\($0)|\(pair)" } ?? pair
                let occurrence = occurrences[identity, default: 0]
                occurrences[identity] = occurrence + 1
                return SeasonScheduleMatchup(
                    id: "\(season):\(leagueID):\(week):\(identity):\(occurrence)",
                    sourceMatchupID: suppliedID, week: week, participants: participants, state: state)
            }
            return SeasonScheduleWeek(week: week, matchups: matchups,
                isPlayoff: regularEnd.map { week > $0 } ?? false)
        }
    }
}
