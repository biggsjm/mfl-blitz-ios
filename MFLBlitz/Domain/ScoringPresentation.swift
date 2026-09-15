import Foundation
import Observation

/// Feed freshness is independent of the game clock. No ticking seconds in copy.
struct ScoreFreshness: Equatable {
    static let staleAfter: TimeInterval = 210
    enum State { case loading, fresh, refreshing, delayed, offline, saved, preview }
    let state: State
    let checkedAt: Date?

    init(snapshot: ScoresSnapshot, refreshing: Bool = false, failed: Bool = false,
         offline: Bool = false, saved: Bool = false, preview: Bool = false, now: Date = Date()) {
        checkedAt = snapshot.checkedAt.flatMap { $0 <= now && $0 > .distantPast ? $0 : nil }
        if preview { state = .preview }
        else if offline { state = .offline }
        else if saved { state = .saved }
        else if failed { state = .delayed }
        else if let checkedAt, now.timeIntervalSince(checkedAt) >= Self.staleAfter { state = .delayed }
        else if refreshing { state = .refreshing }
        else if checkedAt == nil { state = snapshot.matchups.isEmpty ? .loading : .saved }
        else { state = .fresh }
    }

    var qualifiesGameState: Bool { [.delayed, .offline, .saved].contains(state) }
    var isWarning: Bool { state == .delayed || state == .offline }

    func label(now: Date) -> String {
        let age = checkedAt.map { Self.age($0, now: now) }
        switch state {
        case .preview: return "Preview scores"
        case .loading: return "Loading scores…"
        case .fresh: return "Checked \(age ?? "just now")"
        case .refreshing: return age.map { "Refreshing · Checked \($0)" } ?? "Refreshing scores…"
        case .delayed: return age.map { "Scores delayed · Checked \($0)" } ?? "Scores unavailable · Pull to retry"
        case .offline: return age.map { "Offline · Checked \($0)" } ?? "Offline · Saved scores"
        case .saved: return age.map { "Saved scores · Checked \($0)" } ?? "Saved scores · Check needed"
        }
    }

    static func age(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) hr ago" }
        return "\(Int(seconds / 86_400)) days ago"
    }
}

struct ScoringChange: Identifiable, Equatable {
    struct Key: Hashable { let matchupID: String; let teamID: String; var playerID: String? = nil }
    let id = UUID()
    let key: Key
    let name: String
    let previous: Double
    let current: Double
    let date: Date
    let precision: Int
    var difference: Double { current - previous }
    var signedText: String {
        "\(difference > 0 ? "+" : "−")\(abs(difference).pointsText(precision: precision))"
    }
}

/// Session-only, bounded, zero extra requests. A restored/recovered snapshot is
/// a baseline, never a queue of invented just-happened scoring events.
@MainActor @Observable
final class ScoringChangeTracker {
    private(set) var events: [ScoringChange] = []
    private var scope: String?
    private var week: Int?
    private var baseline: [ScoringChange.Key: (Double, String)] = [:]
    private var checkedAt: Date?

    func reset() { scope = nil; week = nil; invalidate() }
    func invalidate() { baseline = [:]; checkedAt = nil; events = [] }

    func observe(_ snapshot: ScoresSnapshot, scope: String, now: Date = Date()) {
        if self.scope != scope || week != snapshot.week {
            reset(); self.scope = scope; week = snapshot.week
        }
        guard let date = snapshot.checkedAt, (0..<ScoreFreshness.staleAfter).contains(now.timeIntervalSince(date)) else {
            invalidate(); return
        }
        // Duplicate cached reads and out-of-order completions are not updates.
        if let checkedAt, date <= checkedAt { return }
        let precision = min(3, max(0, snapshot.scorePrecision))
        let multiplier = pow(10.0, Double(precision))
        var values: [ScoringChange.Key: (Double, String)] = [:]
        func add(_ score: Double?, key: ScoringChange.Key, name: String) {
            guard let score, score.isFinite else { return }
            let rounded = (score * multiplier).rounded() / multiplier
            guard rounded.isFinite else { return }
            values[key] = (rounded, name)
        }
        for matchup in snapshot.matchups {
            for team in [matchup.away, matchup.home] {
                add(team.reportedScore, key: .init(matchupID: matchup.id, teamID: team.id), name: team.name)
                for player in team.players where player.gameState != .pregame {
                    add(player.livePoints, key: .init(matchupID: matchup.id, teamID: team.id, playerID: player.id), name: player.name)
                }
            }
        }
        if let checkedAt, date.timeIntervalSince(checkedAt) < ScoreFreshness.staleAfter {
            let changes = values.compactMap { key, value -> ScoringChange? in
                guard let previous = baseline[key]?.0, previous != value.0 else { return nil }
                return ScoringChange(key: key, name: value.1, previous: previous, current: value.0, date: date, precision: precision)
            }.sorted { ($0.key.matchupID, $0.key.teamID, $0.key.playerID ?? "") < ($1.key.matchupID, $1.key.teamID, $1.key.playerID ?? "") }
            events = Array((changes + events).filter { now.timeIntervalSince($0.date) < 300 }.prefix(20))
        } else { events = [] }
        baseline = values; checkedAt = date
    }

    func recent(matchupID: String? = nil, now: Date = Date()) -> [ScoringChange] {
        events.filter { (0..<300).contains(now.timeIntervalSince($0.date)) && (matchupID == nil || $0.key.matchupID == matchupID) }
    }

    func change(for key: ScoringChange.Key, now: Date = Date()) -> ScoringChange? {
        events.first { $0.key == key && (0..<60).contains(now.timeIntervalSince($0.date)) }
    }
}

enum ScoringGamePresentation {
    struct Projection: Equatable {
        var points: Double?
        var isLiveEstimate: Bool
        var isVisible = true
    }

    /// A simple remaining-time estimate, not a provider's live forecast. Keep
    /// official team points (including corrections), and add only the unplayed
    /// fraction of each starter's pregame projection. Never extrapolate pace.
    static func projection(for team: MatchupTeam, in matchup: Matchup, stale: Bool) -> Projection {
        if matchup.status == .final { return Projection(points: nil, isLiveEstimate: false, isVisible: false) }
        let started = matchup.status.isLive || (matchup.away.starters + matchup.home.starters)
            .contains { $0.gameState == .live || $0.gameState == .final }
        guard started else { return Projection(points: team.projectedScore, isLiveEstimate: false) }
        let unavailable = Projection(points: nil, isLiveEstimate: true)
        guard !stale, matchup.status != .saved, let actual = team.reportedScore,
              !team.starters.isEmpty, team.unclassifiedPlayers.isEmpty,
              Set(team.players.map(\.id)).count == team.players.count,
              team.starters.allSatisfy({ $0.lineupStatus == .starter }),
              team.starters.filter({ ($0.gameSecondsRemaining ?? -1) > 0 }).count == team.playersRemaining
        else { return unavailable }
        var remaining = 0.0
        for player in team.starters {
            guard let seconds = player.gameSecondsRemaining, (0...3600).contains(seconds) else { return unavailable }
            if seconds == 0 { continue }
            guard let projected = player.projectedPoints, projected.isFinite else { return unavailable }
            remaining += projected * Double(seconds) / 3600
        }
        let estimate = actual + remaining
        return estimate.isFinite ? Projection(points: estimate, isLiveEstimate: true) : unavailable
    }

    static func label(for matchup: Matchup, stale: Bool) -> String {
        let players = matchup.away.starters + matchup.home.starters
        let label: String
        if matchup.status == .saved { return "Saved scores" }
        if matchup.status.isLive { label = "Live" }
        else if matchup.status == .final { label = "Final" }
        else if players.contains(where: { $0.gameState == .final }), players.contains(where: { $0.gameState == .pregame }) {
            label = "Between games"
        } else if players.contains(where: { $0.gameState == .pregame }) {
            label = "Upcoming"
        } else if case .pregame(.some) = matchup.status {
            label = "Upcoming"
        } else { label = "Status unavailable" }
        return stale ? "Last known: \(label)" : label
    }

    static func actualPoints(_ player: MatchupPlayer) -> Double? {
        guard player.gameState != .pregame, let points = player.livePoints, points.isFinite else { return nil }
        return points
    }

    /// A bench subtotal is display-only, never a replacement for MFL's team
    /// score. An incomplete or ambiguous bench must not look like a full zero.
    static func benchPoints(for team: MatchupTeam) -> Double? {
        guard !team.bench.isEmpty, team.unclassifiedPlayers.isEmpty,
              Set(team.bench.map(\.id)).count == team.bench.count,
              team.bench.allSatisfy({ $0.lineupStatus == .bench && $0.livePoints?.isFinite == true })
        else { return nil }
        let total = team.bench.compactMap(\.livePoints).reduce(0, +)
        return total.isFinite ? total : nil
    }

    static func margin(_ matchup: Matchup, franchiseID: String, precision: Int) -> String? {
        guard let away = matchup.away.reportedScore, let home = matchup.home.reportedScore,
              matchup.away.id == franchiseID || matchup.home.id == franchiseID else { return nil }
        let value = matchup.away.id == franchiseID ? away - home : home - away
        let rounded = Double(value.pointsText(precision: precision)) ?? value
        if rounded == 0 { return matchup.status == .final ? "Tied" : "Scores tied" }
        let verb = matchup.status == .final ? (value > 0 ? "Won by" : "Lost by") : (value > 0 ? "Leading by" : "Trailing by")
        return "\(verb) \(abs(value).pointsText(precision: precision)) points"
    }
}

/// Fast during play, quieter between games and after errors. The NFL provider
/// budget is enforced separately by the shared server, never by phone timers.
enum ScoringRefreshCadence {
    static func interval(live: Bool, currentWeek: Bool, failed: Bool) -> Double {
        if failed { return 180 }
        return live ? 60 : currentWeek ? 120 : 300
    }
}
