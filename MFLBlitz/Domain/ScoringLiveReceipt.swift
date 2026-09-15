import Foundation

/// Header-only reconciliation. Never advances the receipt on older player stats.
struct ScoringLiveReceipt {
    let matchup: Matchup
    let snapshot: ScoresSnapshot
    let state: MatchupActivityAttributes.ContentState

    init?(matchup: Matchup, snapshot: ScoresSnapshot, state: MatchupActivityAttributes.ContentState?, now: Date = Date()) {
        guard let state, state.updatedAt > (snapshot.checkedAt ?? .distantPast), state.updatedAt <= now,
              let home = Self.number(state.homeScore), let away = Self.number(state.awayScore) else { return nil }
        var updated = matchup
        updated.home.score = home; updated.home.hasReportedScore = true
        updated.away.score = away; updated.away.hasReportedScore = true
        if state.phase == "final" { updated.status = .final }
        else if state.activePlayers > 0 { updated.status = .live("Live") }
        else { updated.status = .live("Between games") }
        self.matchup = updated
        var header = snapshot
        header.checkedAt = state.updatedAt; header.lastUpdated = state.updatedAt
        header.matchups = [updated]
        self.snapshot = header
        self.state = state
    }

    func projection(home: Bool, stale: Bool) -> ScoringGamePresentation.Projection {
        .init(points: stale ? nil : Self.number(home ? state.homeProjection : state.awayProjection),
            isLiveEstimate: true, isVisible: state.phase != "final")
    }

    /// A cold launch may have no saved lineup. Render the matching activity's
    /// identities now, with no fabricated player receipt or zero-filled players.
    static func preview(attributes: MatchupActivityAttributes, state: MatchupActivityAttributes.ContentState,
                        scope: String, week: Int, matchupID: String, now: Date = Date()) -> ScoresSnapshot? {
        guard attributes.scope == scope, attributes.week == week, attributes.matchupID == matchupID,
              let homeID = attributes.homeID, let awayID = attributes.awayID, homeID != awayID,
              let home = number(state.homeScore), let away = number(state.awayScore), state.updatedAt <= now else { return nil }
        let matchup = Matchup(id: matchupID,
            away: MatchupTeam(id: awayID, name: attributes.awayName, abbreviation: attributes.awayAbbreviation,
                score: away, projectedScore: nil, playersRemaining: 0, accentSeed: 0),
            home: MatchupTeam(id: homeID, name: attributes.homeName, abbreviation: attributes.homeAbbreviation,
                score: home, projectedScore: nil, playersRemaining: 0, accentSeed: 1),
            isUserMatchup: true, status: state.phase == "final" ? .final : .live("Live"))
        let precision = [state.homeScore, state.awayScore].map { text in
            text.split(separator: ".").dropFirst().first?.count ?? 0
        }.max() ?? 1
        return ScoresSnapshot(week: week, matchups: [matchup], lastUpdated: .distantPast,
            isLive: state.phase != "final", scorePrecision: min(precision, 3), checkedAt: nil)
    }

    private static func number(_ text: String?) -> Double? {
        guard let text, let value = Double(text), value.isFinite else { return nil }
        return value
    }
}
