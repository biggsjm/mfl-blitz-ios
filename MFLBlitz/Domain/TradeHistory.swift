import Foundation
import MFLCore

struct TradeHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case pending, closed, accepted, declined, withdrawn
        var title: String { rawValue.capitalized }
    }
    var id: String { offer.id }
    var offer: TradeOffer
    var partnerName: String
    var firstSeen: Date
    var changedAt: Date
    var outcome: Outcome = .pending
    var unread = false
}

/// Scoped secure storage belongs to TransactionsModel. No inferred rejection,
/// expiry or acceptance from a missing ID, and no transitions on failed reads.
struct TradeHistory: Codable, Equatable, Sendable {
    var entries: [TradeHistoryEntry] = []

    mutating func observe(_ snapshot: TradeSnapshot, ownerID: String, now: Date = Date()) throws {
        guard snapshot.updatedAt != nil, Set(snapshot.offers.map(\.id)).count == snapshot.offers.count else {
            throw MFLCoreError.invalidResponse
        }
        let hadBaseline = !entries.isEmpty
        let ids = Set(snapshot.offers.map(\.id))
        for index in entries.indices where entries[index].outcome == .pending && !ids.contains(entries[index].id) {
            entries[index].outcome = .closed
            entries[index].changedAt = now
            entries[index].unread = true
        }
        for incoming in snapshot.offers {
            if let index = entries.firstIndex(where: { $0.id == incoming.id }) {
                var offer = incoming
                // A lightweight inbox may omit the sender. Retain an earlier
                // verified sender only for the exact same terms and recipient.
                let old = entries[index].offer
                if offer.offeredBy == nil, old.offeredTo == offer.offeredTo,
                   Set(old.giving.map(\.id)) == Set(offer.giving.map(\.id)),
                   Set(old.receiving.map(\.id)) == Set(offer.receiving.map(\.id)) {
                    offer.offeredBy = old.offeredBy
                }
                if !old.matchesTerms(of: offer) || entries[index].outcome != .pending {
                    entries[index].changedAt = now
                    entries[index].unread = true
                }
                entries[index].offer = offer
                entries[index].outcome = .pending
            } else {
                entries.append(TradeHistoryEntry(offer: incoming,
                    partnerName: snapshot.teams.first { $0.id == incoming.otherTeam(for: ownerID) }?.name ?? "Unknown team",
                    firstSeen: now, changedAt: now, unread: hadBaseline && incoming.offeredTo == ownerID))
            }
            if let index = entries.firstIndex(where: { $0.id == incoming.id }),
               let name = snapshot.teams.first(where: { $0.id == entries[index].offer.otherTeam(for: ownerID) })?.name {
                entries[index].partnerName = name
            }
        }
        // Never evict an active offer. Bound archived terms to the latest 200.
        let open = entries.filter { $0.outcome == .pending }
        let closed = entries.filter { $0.outcome != .pending }.sorted { $0.changedAt > $1.changedAt }.prefix(200)
        entries = open + closed
    }

    mutating func confirm(_ command: TradeCommand, now: Date = Date()) {
        guard case .respond(let offer, let action, _) = command,
              let index = entries.firstIndex(where: { $0.id == offer.id }) else { return }
        entries[index].outcome = switch action { case .accept: .accepted; case .reject: .declined; case .revoke: .withdrawn }
        entries[index].changedAt = now
        entries[index].unread = false // This device performed the confirmed action.
    }
}
