import Foundation

enum LineupSlotAllocation {
    /// MFL stores starters, not named FLEX slots. Use the same deterministic
    /// assignment in scoring and lineup editing, independent of feed ordering.
    nonisolated static func flexPlayerIDs(_ starters: [(id: String, position: String)],
        requirements: [LineupPositionRequirement], starterCount: Int) -> Set<String> {
        guard !requirements.isEmpty,
              Set(requirements.map(\.position)).count == requirements.count,
              Set(starters.map(\.id)).count == starters.count,
              requirements.allSatisfy({ !$0.position.isEmpty && $0.minimum >= 0 && $0.maximum >= $0.minimum }),
              starters.allSatisfy({ player in requirements.contains { $0.position == player.position } }),
              requirements.map(\.minimum).reduce(0, +) <= starterCount,
              requirements.map(\.maximum).reduce(0, +) >= starterCount else { return [] }
        let requiredIDs = Set(requirements.flatMap { rule in
            starters.filter { $0.position == rule.position }.sorted { $0.id < $1.id }.prefix(rule.minimum).map(\.id)
        })
        let flexiblePositions = Set(requirements.filter { $0.maximum > $0.minimum }.map(\.position))
        return Set(starters.filter { !requiredIDs.contains($0.id) && flexiblePositions.contains($0.position) }.map(\.id))
    }
}
