import Foundation

/// Public availability feeds are independent of fantasy ownership and lineup locks.
public struct MFLInjuriesResponse: Decodable, Sendable {
    public let injuries: MFLInjuries
}

public struct MFLInjuries: Decodable, Equatable, Sendable {
    public let week: Int?
    public let timestamp: Date?
    public let players: [MFLInjury]
    private enum CodingKeys: String, CodingKey { case week, timestamp, injury }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = try c.mflIntIfPresent(forKey: .week)
        timestamp = try c.mflStringIfPresent(forKey: .timestamp).flatMap(Double.init)
            .flatMap { $0.isFinite && $0 > 0 && $0 < 32_503_680_000 ? Date(timeIntervalSince1970: $0) : nil }
        players = try c.mflArray(of: MFLInjury.self, forKey: .injury)
    }
    public var byPlayerID: [String: MFLInjury] {
        Dictionary(grouping: players, by: \.id).compactMapValues { $0.count == 1 ? $0.first : nil }
    }
}

public struct MFLInjury: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let status: String?
    public let details: String?
    private enum CodingKeys: String, CodingKey { case id, status, details }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.mflRequiredString(forKey: .id)
        status = try c.mflStringIfPresent(forKey: .status)
        details = try c.mflStringIfPresent(forKey: .details)
    }
}

public struct MFLNFLScheduleResponse: Decodable, Sendable {
    public let nflSchedule: MFLNFLSchedule
}

public struct MFLNFLSchedule: Decodable, Equatable, Sendable {
    public let week: Int?
    public let matchups: [MFLNFLMatchup]
    private enum CodingKeys: String, CodingKey { case week, matchup }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = try c.mflIntIfPresent(forKey: .week)
        matchups = try c.mflArray(of: MFLNFLMatchup.self, forKey: .matchup)
    }
}

public struct MFLNFLMatchup: Codable, Equatable, Sendable {
    public let kickoff: Date?
    public let teams: [MFLNFLTeam]
    private enum CodingKeys: String, CodingKey { case kickoff, team }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kickoff = try c.mflStringIfPresent(forKey: .kickoff).flatMap(Double.init)
            .flatMap { $0.isFinite && $0 > 0 && $0 < 32_503_680_000 ? Date(timeIntervalSince1970: $0) : nil }
        teams = try c.mflArray(of: MFLNFLTeam.self, forKey: .team)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(kickoff?.timeIntervalSince1970, forKey: .kickoff)
        try c.encode(teams, forKey: .team)
    }
}

public struct MFLNFLTeam: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let isHome: Bool?
    private enum CodingKeys: String, CodingKey { case id, isHome }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.mflRequiredString(forKey: .id)
        isHome = try c.mflBoolIfPresent(forKey: .isHome)
    }
}

public struct MFLByeWeeksResponse: Decodable, Sendable {
    public let nflByeWeeks: MFLByeWeeks
}

public struct MFLByeWeeks: Decodable, Equatable, Sendable {
    public let year: Int?
    public let teams: [MFLByeWeek]
    private enum CodingKeys: String, CodingKey { case year, team }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        year = try c.mflIntIfPresent(forKey: .year)
        teams = try c.mflArray(of: MFLByeWeek.self, forKey: .team)
    }
    public var byTeamID: [String: Int] {
        Dictionary(grouping: teams, by: \.id).compactMapValues { values in
            guard values.count == 1, let week = values.first?.week, (1...25).contains(week) else { return nil }
            return week
        }
    }
}

public struct MFLByeWeek: Codable, Equatable, Sendable {
    public let id: String
    public let week: Int?
    private enum CodingKeys: String, CodingKey { case id, week = "bye_week" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.mflRequiredString(forKey: .id)
        week = try c.mflIntIfPresent(forKey: .week)
    }
}

public enum MFLPlayerScorePeriod: Hashable, Sendable {
    case week(Int), yearToDate, average
    public var parameter: String {
        switch self { case .week(let week): String(week); case .yearToDate: "YTD"; case .average: "AVG" }
    }
}

public struct MFLPlayerScoresResponse: Decodable, Sendable {
    public let playerScores: MFLPlayerScores
}

public struct MFLPlayerScores: Decodable, Equatable, Sendable {
    public let period: String?
    public let players: [MFLPlayerProjection]
    private enum CodingKeys: String, CodingKey { case week, playerScore }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        period = try c.mflStringIfPresent(forKey: .week)
        // Share the projection decoder's strict IDs and optional numeric scores.
        players = try c.mflArray(of: ProjectionEntry.self, forKey: .playerScore).compactMap(\.value)
    }
    public var scoresByPlayerID: [String: Decimal] {
        Dictionary(grouping: players, by: \.id).compactMapValues { $0.count == 1 ? $0.first?.score : nil }
    }
}

public struct MFLWatchList: Decodable, Equatable, Sendable {
    public let playerIDs: Set<String>
    public init(from decoder: any Decoder) throws {
        let root = try MFLJSONValue(from: decoder)
        guard let list = root.objectValue?["myWatchList"]?.objectValue else { throw MFLCoreError.invalidResponse }
        let entries = list["player"]?.arrayValue ?? []
        var ids: Set<String> = []
        for entry in entries {
            guard let id = entry.objectValue?["id"]?.stringValue,
                  !id.isEmpty, id.allSatisfy(\.isNumber), ids.insert(id).inserted else {
                throw MFLCoreError.invalidResponse
            }
        }
        // A nonempty unrecognized container must not turn into an empty list.
        guard list["player"] != nil || list.isEmpty || Set(list.keys).isSubset(of: ["franchise_id"]) else {
            throw MFLCoreError.invalidResponse
        }
        playerIDs = ids
    }
}
