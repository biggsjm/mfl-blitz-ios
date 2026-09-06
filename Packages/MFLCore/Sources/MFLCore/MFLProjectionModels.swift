import Foundation

public struct MFLProjectedScoresResponse: Decodable, Sendable {
    public let projectedScores: MFLProjectedScores
}

/// Fantasy Sharks projections converted by MFL to this league's scoring rules.
public struct MFLProjectedScores: Decodable, Equatable, Sendable {
    public let week: Int?
    public let players: [MFLPlayerProjection]

    private enum CodingKeys: String, CodingKey { case week, playerScore }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        week = try container.mflIntIfPresent(forKey: .week)
        players = try container.mflArray(of: MFLPlayerProjection.self, forKey: .playerScore)
    }

    public var scoresByPlayerID: [String: Decimal] {
        Dictionary(grouping: players, by: \.id).compactMapValues { entries in
            // Never choose arbitrarily between duplicate player copies.
            entries.count == 1 ? entries[0].score : nil
        }
    }
}

public struct MFLPlayerProjection: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let score: Decimal?
    private enum CodingKeys: String, CodingKey { case id, score }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflRequiredString(forKey: .id)
        let value = try container.mflDecimalIfPresent(forKey: .score)
        score = value?.isNaN == false ? value : nil
    }
}
