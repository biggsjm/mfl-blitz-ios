import Foundation

struct LineupReadiness {
    struct Issue: Identifiable {
        let playerID: String
        let name: String
        let reason: String
        let locked: Bool
        let urgent: Bool
        var id: String { playerID }
    }
    let issues: [Issue]
    let emptySlots: Int
    let availabilityUnknown: Bool
    let nextLock: Date?
    var attentionCount: Int { issues.filter(\.urgent).count + emptySlots }
    var title: String {
        if attentionCount > 0 { return "\(attentionCount) \(attentionCount == 1 ? "starter needs" : "starters need") attention" }
        if !issues.isEmpty { return "\(issues.count) \(issues.count == 1 ? "starter has" : "starters have") an injury designation" }
        return availabilityUnknown ? "Starter availability unconfirmed" : "No known starter issues"
    }

    init(lineup: LineupSnapshot, availability: PlayerAvailabilitySnapshot?, scope: String?, now: Date = Date()) {
        let data = availability.flatMap { $0.scope == scope && $0.week == lineup.week ? $0 : nil }
        let fresh = data?.injuryUpdatedAt.map { (0...48*3600).contains(now.timeIntervalSince($0)) } ?? false
        availabilityUnknown = !fresh || data?.issues.contains(where: { $0.localizedCaseInsensitiveContains("injury") }) == true
        emptySlots = max(0, lineup.requiredStarterCount - lineup.starters.count)
        nextLock = lineup.players.filter { !$0.isLocked }.compactMap { data?.games[$0.nflTeam]?.kickoff }.filter { $0 > now }.min()
        issues = lineup.starters.compactMap { player in
            if data?.byeWeeks[player.nflTeam] == lineup.week {
                return Issue(playerID: player.id, name: player.name, reason: "Bye week", locked: player.isLocked, urgent: true)
            }
            guard let health = data?.injuries[player.id] else { return nil }
            return Issue(playerID: player.id, name: player.name,
                reason: (fresh ? "" : "Last reported: ") + health.status,
                locked: player.isLocked, urgent: health.needsAttention)
        }
    }
}
