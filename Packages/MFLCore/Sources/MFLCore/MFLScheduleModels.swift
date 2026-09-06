import Foundation

public struct MFLScheduleResponse: Decodable, Equatable, Sendable {
    public let schedule: MFLSchedule

    public init(schedule: MFLSchedule) { self.schedule = schedule }
}

/// The fantasy league schedule, independent of player scoring and NFL games.
public struct MFLSchedule: Decodable, Equatable, Sendable {
    public let weeks: [MFLScheduleWeek]

    public init(weeks: [MFLScheduleWeek]) { self.weeks = weeks }

    private enum CodingKeys: String, CodingKey { case weeklySchedule }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weeks = try container.mflArray(of: MFLScheduleWeek.self, forKey: .weeklySchedule)
    }
}

public struct MFLScheduleWeek: Decodable, Equatable, Sendable {
    public let week: Int
    public let matchups: [MFLScheduleMatchup]

    public init(week: Int, matchups: [MFLScheduleMatchup]) {
        self.week = week
        self.matchups = matchups
    }

    private enum CodingKeys: String, CodingKey { case week, matchup }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let week = try container.mflIntIfPresent(forKey: .week), week > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .week, in: container,
                debugDescription: "A schedule week must be a positive number.")
        }
        self.week = week
        matchups = try container.mflArray(of: MFLScheduleMatchup.self, forKey: .matchup)
    }
}

public struct MFLScheduleMatchup: Decodable, Equatable, Sendable {
    /// Most schedule responses omit a matchup ID. Consumers must scope fallback
    /// identities to the season and week, including repeated pairs in one week.
    public let id: String?
    public let franchises: [MFLScheduleFranchise]

    public init(id: String? = nil, franchises: [MFLScheduleFranchise]) {
        self.id = id
        self.franchises = franchises
    }

    private enum CodingKeys: String, CodingKey { case id, franchise }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflStringIfPresent(forKey: .id)
        franchises = try container.mflArray(of: MFLScheduleFranchise.self, forKey: .franchise)
    }
}

public struct MFLScheduleFranchise: Decodable, Equatable, Sendable {
    public let franchiseID: String
    public let score: Decimal?
    public let isHome: Bool?
    /// MFL can report "T" before a game has a score. This is not independently
    /// sufficient evidence that a matchup is final or tied.
    public let result: String?
    public let spread: Decimal?

    public init(franchiseID: String, score: Decimal? = nil, isHome: Bool? = nil,
                result: String? = nil, spread: Decimal? = nil) {
        self.franchiseID = franchiseID
        self.score = score
        self.isHome = isHome
        self.result = result
        self.spread = spread
    }

    private enum CodingKeys: String, CodingKey { case id, score, isHome, result, spread }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        franchiseID = try container.mflRequiredString(forKey: .id)
        score = try container.mflDecimalIfPresent(forKey: .score)
        isHome = try container.mflBoolIfPresent(forKey: .isHome)
        result = try container.mflStringIfPresent(forKey: .result)
        spread = try container.mflDecimalIfPresent(forKey: .spread)
    }
}
