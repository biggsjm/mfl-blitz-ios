import Foundation
import MFLCore

enum RosterActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case add, drop, reserve, activate
    var id: Self { self }
    var title: String {
        switch self {
        case .add: "Add player"
        case .drop: "Drop player"
        case .reserve: "Move to IR"
        case .activate: "Activate player"
        }
    }
}

struct RosterActionRequest: Equatable, Codable, Identifiable, Sendable {
    var kind: RosterActionKind
    var playerID: String
    var dropID: String? = nil
    var id: String { "\(kind.rawValue)|\(playerID)" }
}

struct RosterActionContext: Equatable, Sendable {
    var scope: String
    var ownerID: String
    var players: [PlayerIdentity]
    /// Current roster membership, never week-specific lineup assignments.
    var membership: [String: String]
    var activeLimit: Int
    var irLimit: Int
    var allowed: Set<RosterActionKind>
    var unavailableReason: String? = nil
    var checkedAt = Date()
    var pending: PendingRosterAction? = nil
    var activeCount: Int { membership.values.filter { $0 == "ROSTER" }.count }
    var irCount: Int { membership.values.filter { $0 == "INJURED_RESERVE" }.count }
    func player(_ id: String) -> PlayerIdentity { players.first { $0.id == id } ?? PlayerIdentity(id: id, name: "Player \(id)") }
    func problem(for request: RosterActionRequest) -> String? {
        guard pending == nil else { return "Check the previous roster change first." }
        guard allowed.contains(request.kind) else { return unavailableReason ?? "This action isn’t available right now. Check MFL." }
        if let drop = request.dropID {
            guard request.kind == .add || request.kind == .activate, drop != request.playerID,
                  membership[drop] == "ROSTER" else { return "Choose a different active player to drop." }
        }
        switch request.kind {
        case .add:
            guard membership[request.playerID] == nil else { return "This player is already on your roster." }
        case .drop:
            guard membership[request.playerID] == "ROSTER" || membership[request.playerID] == "INJURED_RESERVE" else {
                return "This player is no longer on your roster."
            }
        case .reserve:
            guard membership[request.playerID] == "ROSTER" else { return "Only active-roster players can move to IR." }
            guard irCount < irLimit else { return "Your IR is full." }
        case .activate:
            guard membership[request.playerID] == "INJURED_RESERVE" else { return "This player is no longer on IR." }
        }
        if request.kind == .add || request.kind == .activate,
           activeCount + 1 - (request.dropID == nil ? 0 : 1) > activeLimit {
            return "Choose a player to drop to make room."
        }
        return nil
    }
    func expectedMembership(after request: RosterActionRequest) -> [String: String] {
        var result = membership
        if let drop = request.dropID { result[drop] = nil }
        switch request.kind {
        case .add, .activate: result[request.playerID] = "ROSTER"
        case .reserve: result[request.playerID] = "INJURED_RESERVE"
        case .drop: result[request.playerID] = nil
        }
        return result
    }
}

struct PendingRosterAction: Codable, Equatable, Sendable {
    var scope: String
    var request: RosterActionRequest
    var expectedMembership: [String: String]
    var startedAt = Date()
}

struct RosterActionReceipt: Equatable, Sendable {
    var confirmed: Bool
    var message: String
}

/// Exact owner-scoped schema verified from Josh's September 6 export.
/// Descriptions are presentation only; permission uses unique IDs and 0/1.
enum RosterAbilityPolicy {
    static func allowed(_ response: MFLJSONValue, ownerID: String) -> Set<RosterActionKind> {
        guard let franchises = response.objectValue?["abilities"]?.objectValue?["franchise"]?.arrayValue,
              franchises.count == 1, let franchise = franchises[0].objectValue,
              franchise["id"]?.stringValue == ownerID,
              let entries = franchise["ability"]?.arrayValue else { return [] }
        func grants(_ id: String) -> Bool {
            let matches = entries.compactMap(\.objectValue).filter { $0["id"]?.stringValue == id }
            return matches.count == 1 && matches[0]["value"]?.stringValue == "1"
        }
        var result: Set<RosterActionKind> = []
        if grants("WAIVERS") { result.insert(.add) }
        if grants("DROP") { result.insert(.drop) }
        if grants("INJURED_RESERVE") { result.formUnion([.reserve, .activate]) }
        return result
    }
}
