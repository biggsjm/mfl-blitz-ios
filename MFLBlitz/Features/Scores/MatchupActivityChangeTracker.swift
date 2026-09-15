import Foundation

/// A private current-week baseline, independent of whichever week the app browses.
/// These are observed point changes; the MFL feed does not identify the last play.
struct MatchupActivityChangeTracker {
    private var key: String?
    private var previous: Matchup?
    private var previousDate: Date?
    private var precision: Int?
    private(set) var latest: MatchupActivityAttributes.ScoreChange?

    mutating func reset() { self = Self() }

    mutating func observe(_ matchup: Matchup, scope: String, week: Int, checkedAt: Date,
                         precision: Int, now: Date) {
        let key = "\(scope)|\(week)|\(matchup.id)|\(matchup.away.id)|\(matchup.home.id)"
        let precision = min(3, max(0, precision))
        if self.key != key || self.precision != precision { reset() }
        guard (0..<ScoreFreshness.staleAfter).contains(now.timeIntervalSince(checkedAt)) else {
            reset(); return
        }
        if let previousDate, checkedAt <= previousDate { return }
        if let previous, let previousDate, checkedAt.timeIntervalSince(previousDate) < ScoreFreshness.staleAfter {
            let changes = [(previous.away, matchup.away), (previous.home, matchup.home)].compactMap {
                change(from: $0.0, to: $0.1, precision: precision)
            }
            if !changes.isEmpty {
                // When both sides changed in one poll, there is no supported ordering.
                let text = changes.count == 1 ? changes[0].detail : changes.map(\.teamSummary).joined(separator: " · ")
                latest = .init(text: text, checkedAt: checkedAt,playerID:changes.count == 1 ? changes[0].playerID : nil)
            }
        } else { latest = nil }
        self.key = key; self.precision = precision
        previous = matchup; previousDate = checkedAt
    }

    private func change(from old: MatchupTeam, to team: MatchupTeam, precision: Int) -> (detail: String, teamSummary: String, playerID: String?)? {
        guard let before = old.reportedScore, let after = team.reportedScore else { return nil }
        let scale = pow(10.0, Double(precision))
        func ticks(_ value: Double) -> Double { (value * scale).rounded() }
        let delta = ticks(after) - ticks(before)
        guard delta.isFinite, delta != 0 else { return nil }
        let amount = "\(delta > 0 ? "+" : "−")\((abs(delta) / scale).pointsText(precision: precision)) pts"
        let abbreviation = MatchupActivityAttributes.displayAbbreviation(team.abbreviation, name: team.name)
        let summary = "\(abbreviation) \(amount)"
        let oldIDs = Set(old.starters.map(\.id)), newIDs = Set(team.starters.map(\.id))
        guard !newIDs.isEmpty, oldIDs == newIDs,
              oldIDs.count == old.starters.count, newIDs.count == team.starters.count,
              old.unclassifiedPlayers.isEmpty, team.unclassifiedPlayers.isEmpty,
              (old.starters + team.starters).allSatisfy({ $0.lineupStatus == .starter && $0.livePoints?.isFinite == true })
        else { return (summary, summary,nil) }
        let changed = team.starters.compactMap { player -> (String, Double, String)? in
            guard let prior = old.starters.first(where: { $0.id == player.id })?.livePoints,
                  let current = player.livePoints else { return nil }
            let difference = ticks(current) - ticks(prior)
            return difference == 0 ? nil : (String(player.name.prefix(48)), difference,player.id)
        }
        // Name a starter only when the complete starter delta explains the official total.
        guard !changed.isEmpty, changed.reduce(0, { $0 + $1.1 }) == delta else { return (summary, summary,nil) }
        let subject = changed.count == 1 ? changed[0].0 : "\(changed.count) starters"
        return ("\(subject) \(amount) · \(abbreviation)", summary,changed.count == 1 ? changed[0].2 : nil)
    }
}
