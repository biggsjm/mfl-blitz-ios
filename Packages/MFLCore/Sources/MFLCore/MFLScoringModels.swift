import Foundation

public struct MFLLiveScoring: Decodable, Equatable, Sendable {
    public let week: Int?
    public let matchups: [MFLLiveMatchup]

    private enum CodingKeys: String, CodingKey {
        case week
        case matchup
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        week = try container.mflIntIfPresent(forKey: .week)
        matchups = try container.mflArray(of: MFLLiveMatchup.self, forKey: .matchup)
    }
}

public struct MFLLiveMatchup: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let franchises: [MFLLiveFranchise]

    private enum CodingKeys: String, CodingKey {
        case id
        case franchise
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        franchises = try container.mflArray(of: MFLLiveFranchise.self, forKey: .franchise)
        id = try container.mflStringIfPresent(forKey: .id)
            ?? franchises.map(\.franchiseID).joined(separator: "-")
    }
}

public struct MFLLiveFranchise: Decodable, Equatable, Sendable, Identifiable {
    public let franchiseID: String
    public let score: Decimal
    public let isHome: Bool?
    public let gameSecondsRemaining: Int
    public let playersYetToPlay: Int
    public let playersCurrentlyPlaying: Int
    public let players: [MFLLivePlayer]

    public var id: String { franchiseID }

    /// `true` while this franchise can still accrue live points.
    public var isInProgress: Bool {
        gameSecondsRemaining > 0 || playersCurrentlyPlaying > 0
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case score
        case isHome
        case gameSecondsRemaining
        case playersYetToPlay
        case playersCurrentlyPlaying
        case players
    }

    private enum PlayerKeys: String, CodingKey { case player }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        franchiseID = try container.mflRequiredString(forKey: .id)
        score = try container.mflDecimalIfPresent(forKey: .score) ?? 0
        isHome = try container.mflBoolIfPresent(forKey: .isHome)
        gameSecondsRemaining = try container.mflIntIfPresent(forKey: .gameSecondsRemaining) ?? 0
        playersYetToPlay = try container.mflIntIfPresent(forKey: .playersYetToPlay) ?? 0
        playersCurrentlyPlaying = try container.mflIntIfPresent(forKey: .playersCurrentlyPlaying) ?? 0

        if container.contains(.players) {
            let nested = try container.nestedContainer(keyedBy: PlayerKeys.self, forKey: .players)
            players = try nested.mflArray(of: MFLLivePlayer.self, forKey: .player)
        } else {
            players = []
        }
    }
}

public struct MFLLivePlayerStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let starter = Self(rawValue: "starter")
    public static let nonstarter = Self(rawValue: "nonstarter")
}

public struct MFLLivePlayer: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let score: Decimal
    public let status: MFLLivePlayerStatus
    public let gameSecondsRemaining: Int
    public let updatedStats: String?

    public var isStarter: Bool {
        status.rawValue.caseInsensitiveCompare(MFLLivePlayerStatus.starter.rawValue) == .orderedSame
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case score
        case status
        case gameSecondsRemaining
        case updatedStats
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflRequiredString(forKey: .id)
        score = try container.mflDecimalIfPresent(forKey: .score) ?? 0
        status = MFLLivePlayerStatus(
            rawValue: try container.mflStringIfPresent(forKey: .status) ?? "unknown"
        )
        gameSecondsRemaining = try container.mflIntIfPresent(forKey: .gameSecondsRemaining) ?? 0
        updatedStats = try container.mflStringIfPresent(forKey: .updatedStats)
    }
}

public struct MFLLeagueStandings: Decodable, Equatable, Sendable {
    public let franchises: [MFLStanding]
    public let columns: [MFLStandingColumn]

    private enum CodingKeys: String, CodingKey {
        case franchise
        case columnNames
        case column_names
    }

    private enum ColumnKeys: String, CodingKey { case column }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        franchises = try container.mflArray(of: MFLStanding.self, forKey: .franchise)

        let key: CodingKeys? = if container.contains(.column_names) {
            .column_names
        } else if container.contains(.columnNames) {
            .columnNames
        } else {
            nil
        }

        if let key {
            let nested = try container.nestedContainer(keyedBy: ColumnKeys.self, forKey: key)
            columns = try nested.mflArray(of: MFLStandingColumn.self, forKey: .column)
        } else {
            columns = []
        }
    }
}

/// One franchise's standings row. MFL columns vary with league configuration,
/// so every returned value is retained in `values` and common values have typed accessors.
public struct MFLStanding: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let values: [String: MFLJSONValue]

    public var wins: Int? { integerValue(for: "h2hw") }
    public var losses: Int? { integerValue(for: "h2hl") }
    public var ties: Int? { integerValue(for: "h2ht") }
    public var winningPercentage: Decimal? { decimalValue(for: "h2hpct") }
    public var pointsFor: Decimal? { decimalValue(for: "pf") }
    public var pointsAgainst: Decimal? { decimalValue(for: "pa") }
    public var averagePointsFor: Decimal? { decimalValue(for: "avgpf") }
    public var potentialPoints: Decimal? { decimalValue(for: "pp") }
    public var blindBidBalance: Decimal? { decimalValue(for: "bbidbalance") }
    public var streak: String? { stringValue(for: "strk") }

    public func stringValue(for key: String) -> String? {
        values[key]?.stringValue
    }

    public func integerValue(for key: String) -> Int? {
        stringValue(for: key).flatMap(Int.init)
    }

    public func decimalValue(for key: String) -> Decimal? {
        guard let rawValue = stringValue(for: key) else { return nil }
        let normalized = rawValue
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: MFLDynamicCodingKey.self)
        var decoded: [String: MFLJSONValue] = [:]
        decoded.reserveCapacity(container.allKeys.count)
        for key in container.allKeys {
            decoded[key.stringValue] = try container.decode(MFLJSONValue.self, forKey: key)
        }
        guard let id = decoded["id"]?.stringValue, !id.isEmpty else {
            throw DecodingError.keyNotFound(
                MFLDynamicCodingKey(stringValue: "id")!,
                .init(codingPath: decoder.codingPath, debugDescription: "A standings row requires a franchise id")
            )
        }
        self.id = id
        values = decoded
    }
}

public struct MFLStandingColumn: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let abbreviation: String
    public let title: String

    private enum CodingKeys: String, CodingKey {
        case id
        case abbrev
        case title
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflRequiredString(forKey: .id)
        abbreviation = try container.mflStringIfPresent(forKey: .abbrev) ?? id
        title = try container.mflStringIfPresent(forKey: .title) ?? abbreviation
    }
}
