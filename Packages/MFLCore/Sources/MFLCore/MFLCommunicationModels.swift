import Foundation

public struct MFLMessageBoard: Decodable, Equatable, Sendable {
    public let threads: [MFLMessageThreadSummary]

    private enum CodingKeys: String, CodingKey { case thread }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threads = try container.mflArray(of: MFLMessageThreadSummary.self, forKey: .thread)
    }
}

public struct MFLMessageThreadSummary: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let subject: String
    public let lastPostTimestamp: Int?
    public let lastPostFranchiseID: String?
    public let replyCount: Int?
    public let attributes: [String: MFLJSONValue]

    public var lastPostDate: Date? {
        lastPostTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: MFLDynamicCodingKey.self)
        var values: [String: MFLJSONValue] = [:]
        for key in container.allKeys {
            values[key.stringValue] = try container.decode(MFLJSONValue.self, forKey: key)
        }

        guard let identifier = values.mflString("id", "thread_id", "threadId"), !identifier.isEmpty else {
            throw DecodingError.keyNotFound(
                MFLDynamicCodingKey(stringValue: "id")!,
                .init(codingPath: decoder.codingPath, debugDescription: "A message board thread requires an id")
            )
        }
        id = identifier
        subject = values.mflString("subject", "title") ?? "Untitled"
        lastPostTimestamp = values.mflInt("lastPostTime", "last_post_time", "timestamp", "time")
        lastPostFranchiseID = values.mflString(
            "lastPostBy",
            "last_post_by",
            "lastPostFranchiseId",
            "franchise_id"
        )
        replyCount = values.mflInt("replies", "replyCount", "postCount", "count")
        attributes = values
    }
}

public struct MFLMessageThread: Decodable, Equatable, Sendable {
    public let id: String?
    public let subject: String?
    public let messages: [MFLMessage]

    private enum CodingKeys: String, CodingKey {
        case id
        case subject
        case message
        case post
        case messages
        case posts
    }

    private enum MessageKeys: String, CodingKey { case message }
    private enum PostKeys: String, CodingKey { case post }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflStringIfPresent(forKey: .id)
        subject = try container.mflStringIfPresent(forKey: .subject)

        if container.contains(.message) {
            messages = try container.mflArray(of: MFLMessage.self, forKey: .message)
        } else if container.contains(.post) {
            messages = try container.mflArray(of: MFLMessage.self, forKey: .post)
        } else if container.contains(.messages) {
            let nested = try container.nestedContainer(keyedBy: MessageKeys.self, forKey: .messages)
            messages = try nested.mflArray(of: MFLMessage.self, forKey: .message)
        } else if container.contains(.posts) {
            let nested = try container.nestedContainer(keyedBy: PostKeys.self, forKey: .posts)
            messages = try nested.mflArray(of: MFLMessage.self, forKey: .post)
        } else {
            messages = []
        }
    }
}

public struct MFLMessage: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let franchiseID: String?
    public let subject: String?
    public let body: String
    public let timestamp: Int?
    public let attributes: [String: MFLJSONValue]

    public var date: Date? {
        timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: MFLDynamicCodingKey.self)
        var values: [String: MFLJSONValue] = [:]
        for key in container.allKeys {
            values[key.stringValue] = try container.decode(MFLJSONValue.self, forKey: key)
        }

        franchiseID = values.mflString("franchise_id", "franchiseId", "franchise", "author")
        subject = values.mflString("subject", "title")
        body = values.mflString("body", "message", "text") ?? ""
        timestamp = values.mflInt("timestamp", "postTime", "post_time", "time", "date")
        id = values.mflString("id", "post_id", "postId")
            ?? "\(franchiseID ?? "unknown")-\(timestamp ?? 0)-\(body.hashValue)"
        attributes = values
    }
}

public struct MFLPendingWaivers: Decodable, Equatable, Sendable {
    public let requests: [MFLPendingWaiver]

    public init(from decoder: any Decoder) throws {
        let value = try MFLJSONValue(from: decoder)
        requests = Self.extractRequests(from: value)
    }

    private static func extractRequests(from value: MFLJSONValue) -> [MFLPendingWaiver] {
        guard let object = value.objectValue else { return [] }

        for key in ["waiverRequest", "waiver", "request", "transaction"] {
            if let candidates = object[key]?.arrayValue {
                return candidates.compactMap { candidate in
                    candidate.objectValue.map { MFLPendingWaiver(values: $0) }
                }
            }
        }

        // Some MFL variants group requests beneath the current franchise.
        if let franchises = object["franchise"]?.arrayValue {
            return franchises.flatMap { franchiseValue -> [MFLPendingWaiver] in
                guard let franchise = franchiseValue.objectValue else { return [] }
                let franchiseID = franchise.mflString("id", "franchise_id")
                for key in ["waiverRequest", "waiver", "request", "transaction"] {
                    if let candidates = franchise[key]?.arrayValue {
                        return candidates.compactMap { candidate in
                            candidate.objectValue.map {
                                MFLPendingWaiver(values: $0, inheritedFranchiseID: franchiseID)
                            }
                        }
                    }
                }
                return []
            }
        }

        return []
    }
}

public struct MFLPendingWaiver: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let sourceID: String?
    public let type: String?
    public let round: Int?
    public let timestamp: Int?
    public let franchiseID: String?
    public let claims: [MFLWaiverClaim]
    public let attributes: [String: MFLJSONValue]

    public var date: Date? {
        timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public init(from decoder: any Decoder) throws {
        let value = try MFLJSONValue(from: decoder)
        self.init(values: value.objectValue ?? [:])
    }

    init(values: [String: MFLJSONValue], inheritedFranchiseID: String? = nil) {
        sourceID = values.mflString("id", "transaction_id", "request_id")
        type = values.mflString("type", "transactionType", "trans_type")
        round = values.mflInt("round", "waiverRound")
        timestamp = values.mflInt("timestamp", "time", "date")
        franchiseID = values.mflString("franchise_id", "franchiseId", "franchise")
            ?? inheritedFranchiseID
        claims = Self.extractClaims(from: values)
        id = sourceID
            ?? "\(franchiseID ?? "unknown")-\(round ?? 0)-\(timestamp ?? 0)-\(claims.map(\.id).joined(separator: ":"))"
        attributes = values
    }

    private static func extractClaims(from values: [String: MFLJSONValue]) -> [MFLWaiverClaim] {
        for key in ["pick", "claim", "bid", "request"] {
            if let candidates = values[key]?.arrayValue {
                let claims = candidates.compactMap { candidate in
                    candidate.objectValue.flatMap(MFLWaiverClaim.init(values:))
                }
                if !claims.isEmpty { return claims }
            }
        }

        if let picks = values.mflString("picks", "PICKS") {
            return picks.split(separator: ",", omittingEmptySubsequences: true).enumerated().compactMap {
                MFLWaiverClaim(compactPick: String($0.element), fallbackPriority: $0.offset + 1)
            }
        }

        if let claim = MFLWaiverClaim(values: values) {
            return [claim]
        }
        return []
    }
}

public struct MFLWaiverClaim: Decodable, Equatable, Sendable, Identifiable {
    public let playerID: String
    public let dropPlayerID: String?
    public let bidAmount: Decimal?
    public let priority: Int?
    public let attributes: [String: MFLJSONValue]

    public var id: String {
        "\(priority ?? 0)-\(playerID)-\(dropPlayerID ?? "0000")"
    }

    public init(from decoder: any Decoder) throws {
        let value = try MFLJSONValue(from: decoder)
        guard let claim = Self(values: value.objectValue ?? [:]) else {
            throw DecodingError.valueNotFound(
                String.self,
                .init(codingPath: decoder.codingPath, debugDescription: "A waiver claim requires a player id")
            )
        }
        self = claim
    }

    init?(values: [String: MFLJSONValue]) {
        guard let playerID = values.mflString(
            "player",
            "player_id",
            "playerId",
            "add",
            "addPlayer",
            "add_player"
        ), !playerID.isEmpty else { return nil }
        self.playerID = playerID
        let rawDrop = values.mflString("drop", "dropPlayer", "drop_player", "dropPlayerId")
        dropPlayerID = rawDrop == "0000" ? nil : rawDrop
        bidAmount = values.mflDecimal("amount", "bid", "bidAmount", "bid_amount")
        priority = values.mflInt("priority", "rank", "order")
        attributes = values
    }

    init?(compactPick: String, fallbackPriority: Int) {
        let components = compactPick.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2, !components[0].isEmpty else { return nil }
        playerID = components[0]
        if components.count >= 3 {
            bidAmount = Decimal(string: components[1], locale: Locale(identifier: "en_US_POSIX"))
            dropPlayerID = components[2] == "0000" ? nil : components[2]
        } else {
            bidAmount = nil
            dropPlayerID = components[1] == "0000" ? nil : components[1]
        }
        priority = fallbackPriority
        attributes = [:]
    }
}

public struct MFLLineupSubmission: Equatable, Sendable {
    public var week: Int
    public var starterPlayerIDs: [String]
    public var comments: String?
    public var tiebreakerPlayerIDs: [String]
    public var franchiseID: String?

    public init(
        week: Int,
        starterPlayerIDs: [String],
        comments: String? = nil,
        tiebreakerPlayerIDs: [String] = [],
        franchiseID: String? = nil
    ) {
        self.week = week
        self.starterPlayerIDs = starterPlayerIDs
        self.comments = comments
        self.tiebreakerPlayerIDs = tiebreakerPlayerIDs
        self.franchiseID = franchiseID
    }
}

public struct MFLBlindBid: Equatable, Sendable, Identifiable {
    public var playerID: String
    public var amount: Decimal
    public var dropPlayerID: String?

    public var id: String { "\(playerID)-\(dropPlayerID ?? "0000")" }

    public init(playerID: String, amount: Decimal, dropPlayerID: String? = nil) {
        self.playerID = playerID
        self.amount = amount
        self.dropPlayerID = dropPlayerID
    }
}

public struct MFLBlindBidWaiverRequest: Equatable, Sendable {
    public var round: Int?
    public var bids: [MFLBlindBid]
    public var replaceExisting: Bool
    public var franchiseID: String?

    /// An empty `bids` array with `replaceExisting` set clears that waiver round.
    public init(
        round: Int? = nil,
        bids: [MFLBlindBid],
        replaceExisting: Bool = true,
        franchiseID: String? = nil
    ) {
        self.round = round
        self.bids = bids
        self.replaceExisting = replaceExisting
        self.franchiseID = franchiseID
    }
}

public struct MFLMessageBoardPost: Equatable, Sendable {
    public var threadID: String?
    public var subject: String?
    public var body: String
    public var franchiseID: String?

    /// Omit `threadID` and provide a subject to start a thread; provide
    /// `threadID` to reply to an existing thread.
    public init(
        threadID: String? = nil,
        subject: String? = nil,
        body: String,
        franchiseID: String? = nil
    ) {
        self.threadID = threadID
        self.subject = subject
        self.body = body
        self.franchiseID = franchiseID
    }
}

public struct MFLMutationResult: Equatable, Sendable {
    public let message: String?
    public let payload: MFLJSONValue?

    public init(message: String?, payload: MFLJSONValue?) {
        self.message = message
        self.payload = payload
    }
}
