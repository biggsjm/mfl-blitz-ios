import Foundation
import MFLCore

protocol LeagueFeedSnapshot: Codable, Sendable {
    var scope: String { get }
    var fetchedAt: Date { get }
}

struct TradingBlockSnapshot: LeagueFeedSnapshot {
    var scope: String
    var listings: [MFLTradingBlockListing]
    var teams: [TradeTeam]
    var fetchedAt: Date
    var publicationAvailable = true

    func listing(for ownerID: String) -> MFLTradingBlockListing? {
        listings.first { $0.id == ownerID && (!$0.codes.isEmpty || !$0.lookingFor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    }
}

struct TradingBlockDraft: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var codes: Set<String> = []
    var lookingFor = ""
    var baseline: MFLTradingBlockListing?
    // An empty existing listing is a deliberate removal, not a blank new draft.
    var isRemoval: Bool { codes.isEmpty && baseline != nil }
    var hasContent: Bool { isRemoval || !codes.isEmpty || !lookingFor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasChanges: Bool { codes != (baseline?.codes ?? []) || lookingFor != (baseline?.lookingFor ?? "") }
    var canPublish: Bool { isRemoval || (hasChanges && !codes.isEmpty && lookingFor.count <= 256) }
}

struct PendingTradingBlock: Codable, Sendable {
    var scope: String
    var intended: MFLTradingBlockListing
    var startedAt = Date()
}

struct TradingBlockReceipt: Sendable {
    var confirmed: Bool
    var snapshot: TradingBlockSnapshot?
    var removed = false
}

enum LeagueEventKind: String, Codable, CaseIterable, Sendable {
    case waivers, addsOpen, addsClose, trades, draft, keepers, custom
    init(type: String) {
        self = switch type {
        case "WAIVER_BBID", "WAIVER_REVERSE": .waivers
        case "WAIVER_UNLOCK": .addsOpen
        case "WAIVER_LOCK": .addsClose
        case "TRADE": .trades
        case "DRAFT_START", "AUCTION_START": .draft
        case "KEEPERS": .keepers
        default: .custom
        }
    }
    var title: String {
        switch self {
        case .waivers: "Waivers process"
        case .addsOpen: "Adds open"
        case .addsClose: "Adds close"
        case .trades: "Trade deadline"
        case .draft: "Draft starts"
        case .keepers: "Select keepers"
        case .custom: "League event"
        }
    }
    var symbol: String {
        switch self {
        case .waivers: "list.bullet.clipboard"
        case .addsOpen: "person.badge.plus"
        case .addsClose: "lock"
        case .trades: "arrow.triangle.swap"
        case .draft: "person.3"
        case .keepers: "person.crop.circle.badge.checkmark"
        case .custom: "calendar"
        }
    }
    var destination: TeamToolsRoute.Destination? {
        switch self {
        case .waivers, .addsOpen, .addsClose: .addsDrops
        case .trades: .trades
        default: nil
        }
    }
    var actionTitle: String? {
        switch self {
        case .waivers: "Manage bids"
        case .addsOpen, .addsClose: "Browse players"
        case .trades: "View trades"
        default: nil
        }
    }
}

extension MFLCalendarOccurrence {
    var kind: LeagueEventKind { LeagueEventKind(type: type) }
    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.title : title }
}

struct LeagueCalendarSnapshot: LeagueFeedSnapshot {
    var scope: String
    var source: MFLCalendarOccurrences
    var fetchedAt: Date
    var events: [MFLCalendarOccurrence] { source.events.sorted { ($0.start, $0.id) < ($1.start, $1.id) } }
}

enum TradingBlockPolicy {
    static func permits(_ abilities: MFLJSONValue, ownerID: String, ability: String = "TRADES") -> Bool {
        guard let franchises = abilities.objectValue?["abilities"]?.objectValue?["franchise"]?.arrayValue,
              franchises.count == 1, let franchise = franchises[0].objectValue, franchise["id"]?.stringValue == ownerID,
              let rows = franchise["ability"]?.arrayValue else { return false }
        let matches = rows.compactMap(\.objectValue).filter { $0["id"]?.stringValue == ability }
        return matches.count == 1 && matches[0]["value"]?.stringValue == "1"
    }

    static func validate(_ draft: TradingBlockDraft, fresh: TradingBlockSnapshot, ownerID: String) throws {
        let current = fresh.listing(for: ownerID)
        let same = draft.baseline.map { $0.sameTerms(as: current) } ?? (current == nil)
        guard same else { throw RepositoryError.server("Your trading block changed on MFL. Your draft is kept; review the latest listing before publishing.") }
        // Explicit whole-list removal is allowed even for an old or unsupported
        // asset. The matching baseline prevents silently deleting another edit.
        if draft.isRemoval { return }
        guard draft.canPublish, let owner = fresh.teams.first(where: { $0.id == ownerID }),
              draft.codes.allSatisfy({ code in owner.assets.contains { $0.id == code && [.player, .pick].contains($0.kind) } }),
              (current?.codes ?? []).allSatisfy({ MFLTradeAssetCode.isSupported($0) && !$0.hasPrefix("BB_") }) else {
            throw RepositoryError.server("Review your selected players, picks and note. Unsupported assets must be managed on MFL; nothing was published.")
        }
    }
}
