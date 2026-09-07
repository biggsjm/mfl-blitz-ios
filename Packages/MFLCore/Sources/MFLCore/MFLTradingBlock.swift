import Foundation

public struct MFLTradingBlockResponse: Decodable, Sendable {
    public let tradeBaits: MFLTradingBlock
}

public struct MFLTradingBlock: Codable, Equatable, Sendable {
    public var listings: [MFLTradingBlockListing]
    public init(listings: [MFLTradingBlockListing]) { self.listings = listings }

    public init(from decoder: any Decoder) throws {
        let value = try MFLJSONValue(from: decoder)
        guard let object = value.objectValue else { throw MFLCoreError.invalidResponse }
        guard let rows = object["tradeBait"] else {
            guard object.isEmpty else { throw MFLCoreError.invalidResponse }
            listings = []; return
        }
        listings = try (rows.arrayValue ?? [rows]).map(MFLTradingBlockListing.init(value:))
        guard listings.count <= 256, Set(listings.map(\.id)).count == listings.count else { throw MFLCoreError.invalidResponse }
    }
    private enum CodingKeys: String, CodingKey { case tradeBait }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(listings, forKey: .tradeBait)
    }
}

public struct MFLTradingBlockListing: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var codes: Set<String>
    public var lookingFor: String
    public var updatedAt: Date?

    public init(id: String, codes: Set<String>, lookingFor: String, updatedAt: Date? = nil) {
        self.id = id; self.codes = codes; self.lookingFor = lookingFor; self.updatedAt = updatedAt
    }

    init(value: MFLJSONValue) throws {
        guard let fields = value.objectValue,
              let id = fields["franchise_id"]?.stringValue, !id.isEmpty,
              let give = fields["willGiveUp"]?.stringValue,
              let needs = fields["inExchangeFor"]?.stringValue else { throw MFLCoreError.invalidResponse }
        let codes = give.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard Set(codes).count == codes.count else { throw MFLCoreError.invalidResponse }
        var timestamp: Date?
        if let text = fields["timestamp"]?.stringValue, !text.isEmpty {
            guard let seconds = TimeInterval(text), seconds.isFinite, seconds > 0, seconds < 4_200_000_000 else { throw MFLCoreError.invalidResponse }
            timestamp = Date(timeIntervalSince1970: seconds)
        }
        self.init(id: id, codes: Set(codes), lookingFor: needs, updatedAt: timestamp)
    }
    public init(from decoder: any Decoder) throws { try self.init(value: MFLJSONValue(from: decoder)) }
    private enum CodingKeys: String, CodingKey { case franchise_id, willGiveUp, inExchangeFor, timestamp }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .franchise_id)
        try container.encode(codes.sorted().joined(separator: ","), forKey: .willGiveUp)
        try container.encode(lookingFor, forKey: .inExchangeFor)
        try container.encodeIfPresent(updatedAt.map { String(Int($0.timeIntervalSince1970)) }, forKey: .timestamp)
    }

    public func sameTerms(as other: Self?) -> Bool {
        other.map { $0.id == id && $0.codes == codes && $0.lookingFor == lookingFor } ?? false
    }
}
