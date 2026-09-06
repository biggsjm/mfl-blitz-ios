import Foundation

public struct MFLPendingTradesResponse: Decodable, Sendable {
    public let pendingTrades: MFLPendingTrades
}

public struct MFLPendingTrades: Decodable, Sendable {
    public let offers: [MFLPendingTrade]

    public init(from decoder: any Decoder) throws {
        let value = try MFLJSONValue(from: decoder)
        if value.stringValue == "", value.objectValue == nil { offers = []; return }
        guard let object = value.objectValue else { throw MFLCoreError.invalidResponse }
        let keys = ["pendingTrade", "trade"].filter { object[$0] != nil }
        guard keys.count <= 1 else { throw MFLCoreError.invalidResponse }
        guard let key = keys.first else {
            guard object.keys.allSatisfy({ ["timestamp", "franchise_id"].contains($0) }) else { throw MFLCoreError.invalidResponse }
            offers = []; return
        }
        let raw = object[key]!
        let rows = raw.objectValue == nil && raw.stringValue == "" ? [] : (raw.arrayValue ?? [raw])
        offers = try rows.map { try MFLPendingTrade(value: $0) }
        guard Set(offers.map(\.id)).count == offers.count else { throw MFLCoreError.invalidResponse }
    }
}

public struct MFLPendingTrade: Equatable, Sendable, Identifiable {
    public let id: String
    public let offeredBy: String?
    public let offeredTo: String
    public let giving: [String]
    public let receiving: [String]
    public let comments: String
    public let description: String
    public let expires: Date?
    public let timestamp: Date?
    public let status: String?

    init(value: MFLJSONValue) throws {
        guard let object = value.objectValue else { throw MFLCoreError.invalidResponse }
        func text(_ keys: String...) -> String? {
            keys.compactMap { object[$0]?.stringValue }.first { !$0.isEmpty }
        }
        guard let id = text("trade_id", "id"), let to = text("offeredto", "offeredTo", "franchise2"),
              let give = text("will_give_up", "willGiveUp", "franchise1_gave_up"),
              let receive = text("will_receive", "willReceive", "franchise2_gave_up") else { throw MFLCoreError.invalidResponse }
        self.id = id
        offeredTo = to
        offeredBy = text("offeringteam", "offeringTeam", "offeredby", "offeredBy", "franchise1", "proposedBy")
        giving = give.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        receiving = receive.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !giving.isEmpty, !receiving.isEmpty,
              Set(giving).count == giving.count, Set(receiving).count == receiving.count else { throw MFLCoreError.invalidResponse }
        comments = text("comments") ?? ""
        description = text("description") ?? ""
        expires = text("expires", "willExpire").flatMap(TimeInterval.init).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        timestamp = text("timestamp").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        status = text("status")
    }
}

public struct MFLTradeAssetsResponse: Decodable, Sendable {
    public let assets: MFLTradeAssets
}

public struct MFLTradeAssets: Decodable, Sendable {
    public let franchises: [MFLFranchiseAssets]

    public init(from decoder: any Decoder) throws {
        let value = try MFLJSONValue(from: decoder)
        guard let object = value.objectValue, let raw = object["franchise"] else { throw MFLCoreError.invalidResponse }
        franchises = try (raw.arrayValue ?? [raw]).map { try MFLFranchiseAssets(value: $0) }
        guard !franchises.isEmpty, Set(franchises.map(\.id)).count == franchises.count else { throw MFLCoreError.invalidResponse }
    }
}

public struct MFLFranchiseAssets: Sendable, Identifiable {
    public let id: String
    public let codes: [String]
    public let blindBidBalance: Decimal?

    init(value: MFLJSONValue) throws {
        guard let object = value.objectValue, let id = object["id"]?.stringValue, !id.isEmpty else { throw MFLCoreError.invalidResponse }
        self.id = id
        var codes: [String] = []
        for (container, child, key) in [("players", "player", "id"), ("currentYearDraftPicks", "draftPick", "pick"), ("futureYearDraftPicks", "draftPick", "pick")] {
            guard let group = object[container] else { continue }
            if group.stringValue == "", group.objectValue == nil { continue }
            guard let nested = group.objectValue else { throw MFLCoreError.invalidResponse }
            guard let raw = nested[child] else {
                guard nested.isEmpty else { throw MFLCoreError.invalidResponse }
                continue
            }
            for item in raw.arrayValue ?? [raw] {
                guard let code = item.objectValue?[key]?.stringValue, !code.isEmpty else { throw MFLCoreError.invalidResponse }
                codes.append(code)
            }
        }
        guard Set(codes).count == codes.count else { throw MFLCoreError.invalidResponse }
        self.codes = codes
        let amount = object["blindBiddingDollars"]?.objectValue?["amount"]?.stringValue
        blindBidBalance = amount.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
    }

    public func owns(_ code: String) -> Bool {
        if code.hasPrefix("BB_"), let amount = MFLTradeAssetCode.blindBidAmount(code), let balance = blindBidBalance {
            return amount > 0 && amount <= balance
        }
        return codes.contains(code)
    }
}

public enum MFLTradeResponse: String, Codable, Sendable {
    case accept, reject, revoke
}

public enum MFLTradeAssetCode {
    public static func isSupported(_ code: String) -> Bool {
        if code.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil { return true }
        if code.range(of: #"^DP_[0-9]+_[0-9]+$"#, options: .regularExpression) != nil { return true }
        if code.range(of: #"^FP_[0-9]+_[0-9]{4}_[1-9][0-9]*$"#, options: .regularExpression) != nil { return true }
        return blindBidAmount(code).map { $0 > 0 } ?? false
    }

    public static func blindBidAmount(_ code: String) -> Decimal? {
        guard code.range(of: #"^BB_[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: String(code.dropFirst(3)), locale: Locale(identifier: "en_US_POSIX"))
    }
}
