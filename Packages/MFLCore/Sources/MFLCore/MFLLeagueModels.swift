import Foundation

public struct MFLUserLeagueCollection: Decodable, Equatable, Sendable {
    public let leagues: [MFLUserLeague]

    private enum CodingKeys: String, CodingKey { case league }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leagues = try container.mflArray(of: MFLUserLeague.self, forKey: .league)
    }
}

public struct MFLUserLeague: Decodable, Equatable, Sendable, Identifiable {
    public let leagueID: String
    public let franchiseID: String
    public let name: String
    public let franchiseName: String?
    public let url: URL

    public var id: String { leagueID }

    public var serverHost: MFLAPIHost? {
        guard let host = url.host else { return nil }
        return try? MFLAPIHost(host)
    }

    private enum CodingKeys: String, CodingKey {
        case leagueID = "league_id"
        case franchiseID = "franchise_id"
        case name
        case franchiseName = "franchise_name"
        case url
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leagueID = try container.mflRequiredString(forKey: .leagueID)
        franchiseID = try container.mflRequiredString(forKey: .franchiseID)
        name = try container.mflStringIfPresent(forKey: .name) ?? "League \(leagueID)"
        franchiseName = try container.mflStringIfPresent(forKey: .franchiseName)
        let urlString = try container.mflRequiredString(forKey: .url)
        guard let parsedURL = URL(string: urlString),
              parsedURL.scheme?.lowercased() == "https",
              (try? MFLAPIHost(parsedURL.absoluteString)) != nil
        else {
            throw MFLCoreError.invalidHost(urlString)
        }
        url = parsedURL
    }
}

public struct MFLLeague: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let baseURL: String?
    public let startWeek: Int?
    public let endWeek: Int?
    public let lastRegularSeasonWeek: Int?
    public let rosterSize: Int?
    public let injuredReserveSize: Int?
    public let taxiSquadSize: Int?
    public let rostersPerPlayer: Int?
    public let playerLimitUnit: String?
    public let usesSalaries: Bool?
    public let usesContractYear: Bool?
    public let scorePrecision: Int?
    public let currentWaiverType: String?
    public let blindBidSeasonLimit: Decimal?
    public let blindBidMinimum: Decimal?
    public let blindBidIncrement: Decimal?
    public let conditionalBlindBidding: Bool?
    public let maxWaiverRounds: Int?
    public let tiebreakerType: String?
    public let tiebreakerCount: Int?
    public let headToHead: Bool?
    public let standingsSort: String?
    public let partialLineupsAllowed: Bool?
    public let bestLineup: Bool?
    public let lineupLockout: Bool?
    public let franchises: [MFLFranchise]
    public let divisions: [MFLDivision]
    /// MFL's authoritative total starter count. This can be greater than the
    /// sum of position minima when a league has flex positions.
    public let starterCount: Int?
    public let starterRequirements: [MFLStarterRequirement]

    public var serverHost: MFLAPIHost? {
        guard let baseURL else { return nil }
        return try? MFLAPIHost(baseURL)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case startWeek
        case endWeek
        case lastRegularSeasonWeek
        case rosterSize
        case injuredReserve
        case taxiSquad
        case rostersPerPlayer, playerLimitUnit, usesSalaries, usesContractYear
        case precision
        case currentWaiverType
        case bbidSeasonLimit
        case bbidMinimum
        case bbidIncrement
        case bbidConditional
        case maxWaiverRounds
        case tiebreaker
        case tiebreakerCount
        case h2h
        case standingsSort
        case partialLineupAllowed
        case bestLineup
        case lockout
        case franchises
        case divisions
        case starters
    }

    private enum FranchiseKeys: String, CodingKey { case franchise }
    private enum DivisionKeys: String, CodingKey { case division }
    private enum StarterKeys: String, CodingKey {
        case count
        case position
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflRequiredString(forKey: .id)
        name = try container.mflStringIfPresent(forKey: .name) ?? "League \(id)"
        baseURL = try container.mflStringIfPresent(forKey: .baseURL)
        startWeek = try container.mflIntIfPresent(forKey: .startWeek)
        endWeek = try container.mflIntIfPresent(forKey: .endWeek)
        lastRegularSeasonWeek = try container.mflIntIfPresent(forKey: .lastRegularSeasonWeek)
        rosterSize = try container.mflIntIfPresent(forKey: .rosterSize)
        injuredReserveSize = try container.mflIntIfPresent(forKey: .injuredReserve)
        taxiSquadSize = try container.mflIntIfPresent(forKey: .taxiSquad)
        rostersPerPlayer = try container.mflIntIfPresent(forKey: .rostersPerPlayer)
        playerLimitUnit = try container.mflStringIfPresent(forKey: .playerLimitUnit)
        usesSalaries = try container.mflBoolIfPresent(forKey: .usesSalaries)
        usesContractYear = try container.mflBoolIfPresent(forKey: .usesContractYear)
        scorePrecision = try container.mflIntIfPresent(forKey: .precision)
        currentWaiverType = try container.mflStringIfPresent(forKey: .currentWaiverType)
        blindBidSeasonLimit = try container.mflDecimalIfPresent(forKey: .bbidSeasonLimit)
        blindBidMinimum = try container.mflDecimalIfPresent(forKey: .bbidMinimum)
        blindBidIncrement = try container.mflDecimalIfPresent(forKey: .bbidIncrement)
        conditionalBlindBidding = try container.mflBoolIfPresent(forKey: .bbidConditional)
        maxWaiverRounds = try container.mflIntIfPresent(forKey: .maxWaiverRounds)
        tiebreakerType = try container.mflStringIfPresent(forKey: .tiebreaker)
        tiebreakerCount = try container.mflIntIfPresent(forKey: .tiebreakerCount)
        headToHead = try container.mflBoolIfPresent(forKey: .h2h)
        standingsSort = try container.mflStringIfPresent(forKey: .standingsSort)
        partialLineupsAllowed = try container.mflBoolIfPresent(forKey: .partialLineupAllowed)
        bestLineup = try container.mflBoolIfPresent(forKey: .bestLineup)
        lineupLockout = try container.mflBoolIfPresent(forKey: .lockout)

        if container.contains(.franchises) {
            let nested = try container.nestedContainer(keyedBy: FranchiseKeys.self, forKey: .franchises)
            franchises = try nested.mflArray(of: MFLFranchise.self, forKey: .franchise)
        } else {
            franchises = []
        }

        if container.contains(.divisions) {
            let nested = try container.nestedContainer(keyedBy: DivisionKeys.self, forKey: .divisions)
            divisions = try nested.mflArray(of: MFLDivision.self, forKey: .division)
        } else {
            divisions = []
        }

        if container.contains(.starters) {
            let nested = try container.nestedContainer(keyedBy: StarterKeys.self, forKey: .starters)
            starterCount = try nested.mflIntIfPresent(forKey: .count)
            starterRequirements = try nested.mflArray(of: MFLStarterRequirement.self, forKey: .position)
        } else {
            starterCount = nil
            starterRequirements = []
        }
    }
}

public struct MFLFranchise: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let abbreviation: String?
    public let divisionID: String?
    public let conferenceID: String?
    public let iconURL: URL?
    public let logoURL: URL?
    public let ownerName: String?
    public let email: String?
    public let username: String?
    public let blindBidAvailableBalance: Decimal?
    public let waiverSortOrder: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case abbrev
        case division
        case conference
        case icon
        case logo
        case ownerName
        case owner_name
        case email
        case username
        case bbidAvailableBalance
        case waiverSortOrder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflRequiredString(forKey: .id)
        name = try container.mflStringIfPresent(forKey: .name) ?? "Franchise \(id)"
        abbreviation = try container.mflStringIfPresent(forKey: .abbrev)
        divisionID = try container.mflStringIfPresent(forKey: .division)
        conferenceID = try container.mflStringIfPresent(forKey: .conference)
        iconURL = try container.mflStringIfPresent(forKey: .icon).flatMap(URL.init(string:))
        logoURL = try container.mflStringIfPresent(forKey: .logo).flatMap(URL.init(string:))
        ownerName = try container.mflStringIfPresent(forKey: .ownerName)
            ?? container.mflStringIfPresent(forKey: .owner_name)
        email = try container.mflStringIfPresent(forKey: .email)
        username = try container.mflStringIfPresent(forKey: .username)
        blindBidAvailableBalance = try container.mflDecimalIfPresent(forKey: .bbidAvailableBalance)
        waiverSortOrder = try container.mflIntIfPresent(forKey: .waiverSortOrder)
    }
}

public struct MFLDivision: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let conferenceID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case conference
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflRequiredString(forKey: .id)
        name = try container.mflStringIfPresent(forKey: .name) ?? "Division \(id)"
        conferenceID = try container.mflStringIfPresent(forKey: .conference)
    }
}

public struct MFLStarterRequirement: Decodable, Equatable, Sendable, Identifiable {
    public let position: String
    public let limit: String

    public var id: String { position }

    /// The minimum implied by limits such as `2`, `2-3`, or `2+`.
    public var minimum: Int? {
        Int(limit.prefix(while: \Character.isNumber))
    }

    /// The maximum implied by a fixed or ranged limit. `nil` means unbounded/unknown.
    public var maximum: Int? {
        if let separator = limit.firstIndex(of: "-") {
            return Int(limit[limit.index(after: separator)...])
        }
        return limit.allSatisfy(\.isNumber) ? Int(limit) : nil
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case limit
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.mflRequiredString(forKey: .name)
        limit = try container.mflStringIfPresent(forKey: .limit) ?? "0"
    }
}

public struct MFLPlayerCatalog: Decodable, Equatable, Sendable {
    public let timestamp: Int?
    public let players: [MFLPlayer]
    /// Built once with the validated daily catalog, shared by every tab.
    public let playersByID: [String: MFLPlayer]

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case player
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.mflIntIfPresent(forKey: .timestamp)
        players = try container.mflArray(of: MFLPlayer.self, forKey: .player)
        guard Set(players.map(\.id)).count == players.count else { throw MFLCoreError.invalidResponse }
        playersByID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
    }
}

public struct MFLPlayer: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    /// MFL's source name, normally formatted as `Last, First`.
    public let name: String
    public let position: String?
    public let nflTeam: String?
    public let status: String?
    public let jerseyNumber: String?
    public let birthDate: String?
    public let height: String?
    public let weight: String?
    public let draftYear: Int?
    public let draftRound: Int?

    public var displayName: String {
        let parts = name.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2 else { return name }
        return "\(parts[1]) \(parts[0])"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case position
        case team
        case status
        case jersey
        case jerseyNumber
        case birthdate
        case birthDate
        case height
        case weight
        case draft_year
        case draftYear
        case draft_round
        case draftRound
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflRequiredString(forKey: .id)
        name = try container.mflStringIfPresent(forKey: .name) ?? "Player \(id)"
        position = try container.mflStringIfPresent(forKey: .position)
        nflTeam = try container.mflStringIfPresent(forKey: .team)
        status = try container.mflStringIfPresent(forKey: .status)
        jerseyNumber = try container.mflStringIfPresent(forKey: .jerseyNumber)
            ?? container.mflStringIfPresent(forKey: .jersey)
        birthDate = try container.mflStringIfPresent(forKey: .birthDate)
            ?? container.mflStringIfPresent(forKey: .birthdate)
        height = try container.mflStringIfPresent(forKey: .height)
        weight = try container.mflStringIfPresent(forKey: .weight)
        draftYear = try container.mflIntIfPresent(forKey: .draftYear)
            ?? container.mflIntIfPresent(forKey: .draft_year)
        draftRound = try container.mflIntIfPresent(forKey: .draftRound)
            ?? container.mflIntIfPresent(forKey: .draft_round)
    }
}

public struct MFLRosterCollection: Decodable, Equatable, Sendable {
    public let rosters: [MFLRoster]

    private enum CodingKeys: String, CodingKey { case franchise }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rosters = try container.mflArray(of: MFLRoster.self, forKey: .franchise)
    }
}

public struct MFLRoster: Decodable, Equatable, Sendable, Identifiable {
    public let franchiseID: String
    public let week: Int?
    public let players: [MFLRosterPlayer]

    public var id: String { franchiseID }

    private enum CodingKeys: String, CodingKey {
        case id
        case week
        case player
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        franchiseID = try container.mflRequiredString(forKey: .id)
        week = try container.mflIntIfPresent(forKey: .week)
        players = try container.mflArray(of: MFLRosterPlayer.self, forKey: .player)
    }
}

public struct MFLRosterStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let roster = Self(rawValue: "ROSTER")
    public static let injuredReserve = Self(rawValue: "INJURED_RESERVE")
    public static let taxiSquad = Self(rawValue: "TAXI_SQUAD")
}

public struct MFLRosterPlayer: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let status: MFLRosterStatus
    public let hasExplicitStatus: Bool
    public let salary: Decimal?
    public let contractYear: Int?
    public let contractStatus: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case salary
        case contractYear
        case contractStatus
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflRequiredString(forKey: .id)
        hasExplicitStatus = try container.mflStringIfPresent(forKey: .status).map { !$0.isEmpty } ?? false
        status = MFLRosterStatus(
            rawValue: try container.mflStringIfPresent(forKey: .status) ?? MFLRosterStatus.roster.rawValue
        )
        salary = try container.mflDecimalIfPresent(forKey: .salary)
        contractYear = try container.mflIntIfPresent(forKey: .contractYear)
        contractStatus = try container.mflStringIfPresent(forKey: .contractStatus)
    }
}

public struct MFLFreeAgentPool: Decodable, Equatable, Sendable {
    public let leagueUnits: [MFLFreeAgentLeagueUnit]

    public var players: [MFLFreeAgent] {
        leagueUnits.flatMap(\.players)
    }

    private enum CodingKeys: String, CodingKey {
        case leagueUnit
        case player
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.leagueUnit) {
            leagueUnits = try container.mflArray(of: MFLFreeAgentLeagueUnit.self, forKey: .leagueUnit)
        } else {
            let players = try container.mflArray(of: MFLFreeAgent.self, forKey: .player)
            leagueUnits = players.isEmpty ? [] : [MFLFreeAgentLeagueUnit(unit: nil, players: players)]
        }
    }
}

public struct MFLFreeAgentLeagueUnit: Decodable, Equatable, Sendable, Identifiable {
    public let unit: String?
    public let players: [MFLFreeAgent]

    public var id: String { unit ?? "league" }

    private enum CodingKeys: String, CodingKey {
        case unit
        case id
        case player
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unit = try container.mflStringIfPresent(forKey: .unit)
            ?? container.mflStringIfPresent(forKey: .id)
        players = try container.mflArray(of: MFLFreeAgent.self, forKey: .player)
    }

    init(unit: String?, players: [MFLFreeAgent]) {
        self.unit = unit
        self.players = players
    }
}

public struct MFLFreeAgent: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let salary: Decimal?
    public let contractYear: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case salary
        case contractYear
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflRequiredString(forKey: .id)
        salary = try container.mflDecimalIfPresent(forKey: .salary)
        contractYear = try container.mflIntIfPresent(forKey: .contractYear)
    }
}
