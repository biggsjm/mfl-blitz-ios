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
        // The live Week 1 feed includes an empty {"id":"","score":""}
        // placeholder among valid rows. It is not a player, and must not make
        // the entire projection feed fail decoding. Keep all identified rows,
        // including missing scores, so duplicate-ID protection still applies.
        players = try container.mflArray(of: ProjectionEntry.self, forKey: .playerScore)
            .compactMap(\.value)
    }

    public var scoresByPlayerID: [String: Decimal] {
        Dictionary(grouping: players, by: \.id).compactMapValues { entries in
            // Never choose arbitrarily between duplicate player copies.
            entries.count == 1 ? entries[0].score : nil
        }
    }
}

private struct ProjectionEntry: Decodable {
    let value: MFLPlayerProjection?
    private enum CodingKeys: String, CodingKey { case id }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try container.mflStringIfPresent(forKey: .id),
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            value = nil
            return
        }
        value = try MFLPlayerProjection(from: decoder)
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
