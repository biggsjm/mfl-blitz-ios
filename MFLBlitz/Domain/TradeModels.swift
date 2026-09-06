import Foundation
import MFLCore

struct TradeAsset: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case player, pick, budget, unknown }
    let id: String
    var name: String
    var detail: String
    var kind: Kind
}

struct TradeTeam: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var abbreviation: String
    var artworkURLs: [URL] = []
    var assets: [TradeAsset]
    var blindBidBalance: Decimal?
}

struct TradeOffer: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var offeredBy: String?
    var offeredTo: String
    var giving: [TradeAsset]
    var receiving: [TradeAsset]
    var comments: String
    var expires: Date?
    var timestamp: Date?
    var status: String?

    var isExpired: Bool { expires.map { $0 <= Date() } ?? false }
    var isActionable: Bool {
        offeredBy != nil && !isExpired && !giving.isEmpty && !receiving.isEmpty
            && (giving + receiving).allSatisfy { $0.kind != .unknown }
            && (status == nil || ["pending", "offered"].contains(status!.lowercased()))
    }
    func matchesTerms(of other: TradeOffer) -> Bool {
        id == other.id && offeredBy == other.offeredBy && offeredTo == other.offeredTo
            && Set(giving.map(\.id)) == Set(other.giving.map(\.id))
            && Set(receiving.map(\.id)) == Set(other.receiving.map(\.id))
            && expires == other.expires && comments == other.comments && status == other.status
    }
    func sending(for franchise: String) -> [TradeAsset] { offeredBy == franchise ? giving : receiving }
    func getting(for franchise: String) -> [TradeAsset] { offeredBy == franchise ? receiving : giving }
    func otherTeam(for franchise: String) -> String? { offeredBy == franchise ? offeredTo : offeredBy }
}

struct TradeDraft: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var partnerID: String = ""
    var giving: Set<String> = []
    var receiving: Set<String> = []
    var comments = ""
    var expires = Date(timeIntervalSince1970: floor(Date().addingTimeInterval(7 * 86_400).timeIntervalSince1970))
    var countering: TradeOffer?
    var acknowledgesOriginalStaysOpen = false
}

struct TradeSnapshot: Sendable {
    var teams: [TradeTeam] = []
    var offers: [TradeOffer] = []
    var updatedAt: Date?
}

enum TradeCommand: Codable, Equatable, Sendable {
    case propose(TradeDraft)
    case respond(TradeOffer, MFLTradeResponse, comments: String)
}

struct PendingTradeAction: Codable, Sendable {
    var command: TradeCommand
    var existingIDs: Set<String>
    var startedAt = Date()
    var acknowledgedByMFL = false
}

struct TradeReceipt: Sendable {
    var confirmed: Bool
    var message: String
    /// The authoritative readback can also update the inbox without another request.
    var snapshot: TradeSnapshot? = nil
}

struct TransactionActivity: Identifiable, Sendable {
    let id: String
    var title: String
    var detail: String
    var date: Date?
    var isTrade: Bool
    var teamName: String?
    var partnerName: String?
    var bid: Decimal?
    var moves: [TransactionActivityMove] = []
}

struct TransactionActivityMove: Sendable {
    let label: String
    let names: String
}
