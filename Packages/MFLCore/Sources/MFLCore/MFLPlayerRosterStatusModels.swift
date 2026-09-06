import Foundation

/// The player states returned by MFL's `playerRosterStatus` export.
public struct MFLPlayerRosterStatusCollection: Decodable, Equatable, Sendable {
    public let statuses: [MFLPlayerRosterStatus]

    private enum CodingKeys: String, CodingKey {
        case playerStatus
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statuses = try container.mflArray(of: MFLPlayerRosterStatus.self, forKey: .playerStatus)
    }

    /// Finds one requested player's state without requiring callers to build a lookup table.
    public subscript(playerID playerID: String) -> MFLPlayerRosterStatus? {
        statuses.first(where: { $0.id == playerID })
    }
}

/// League-specific roster and lineup state for one MFL player.
public struct MFLPlayerRosterStatus: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let isFreeAgent: Bool?
    public let cannotAdd: Bool?
    /// MFL does not include this flag for every kind of player state; `nil`
    /// means unknown and must not be treated as unlocked.
    public let isLocked: Bool?
    public let rosterFranchises: [MFLPlayerRosterFranchise]

    private enum CodingKeys: String, CodingKey {
        case id
        case isFreeAgent = "is_fa"
        case isFreeAgentCamel = "isFA"
        case cannotAdd = "cant_add"
        case cannotAddCamel = "cantAdd"
        case locked
        case isLocked
        case rosterFranchise = "roster_franchise"
        case rosterFranchiseCamel = "rosterFranchise"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mflRequiredString(forKey: .id)
        isFreeAgent = try container.mflBoolIfPresent(forKey: .isFreeAgent)
            ?? container.mflBoolIfPresent(forKey: .isFreeAgentCamel)
        cannotAdd = try container.mflBoolIfPresent(forKey: .cannotAdd)
            ?? container.mflBoolIfPresent(forKey: .cannotAddCamel)
        isLocked = try container.mflBoolIfPresent(forKey: .locked)
            ?? container.mflBoolIfPresent(forKey: .isLocked)
        if container.contains(.rosterFranchise) {
            rosterFranchises = try container.mflArray(
                of: MFLPlayerRosterFranchise.self,
                forKey: .rosterFranchise
            )
        } else {
            rosterFranchises = try container.mflArray(
                of: MFLPlayerRosterFranchise.self,
                forKey: .rosterFranchiseCamel
            )
        }
    }

    public func rosterFranchise(id franchiseID: String) -> MFLPlayerRosterFranchise? {
        rosterFranchises.first(where: { $0.franchiseID == franchiseID })
    }
}

/// One franchise's assignment for a player in the requested week.
public struct MFLPlayerRosterFranchise: Decodable, Equatable, Sendable, Identifiable {
    public let franchiseID: String
    public let status: MFLPlayerLineupStatus

    public var id: String { franchiseID }
    public var isStarter: Bool { status == .starter }

    private enum CodingKeys: String, CodingKey {
        case franchiseID = "franchise_id"
        case franchiseIDCamel = "franchiseId"
        case id
        case status
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let franchiseID = try container.mflStringIfPresent(forKey: .franchiseID)
            ?? container.mflStringIfPresent(forKey: .franchiseIDCamel)
            ?? container.mflStringIfPresent(forKey: .id),
            !franchiseID.isEmpty
        else {
            throw DecodingError.valueNotFound(
                String.self,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "A player roster assignment requires a franchise id"
                )
            )
        }
        self.franchiseID = franchiseID
        status = MFLPlayerLineupStatus(
            rawValue: try container.mflRequiredString(forKey: .status)
        )
    }
}

/// MFL's documented player assignment codes. Unknown future codes remain intact.
public struct MFLPlayerLineupStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// MFL uses `R` when no submitted lineup is visible as well as for a
    /// generic roster assignment, so it does not prove that a player is benched.
    public static let roster = Self(rawValue: "R")
    public static let starter = Self(rawValue: "S")
    public static let nonStarter = Self(rawValue: "NS")
    public static let injuredReserve = Self(rawValue: "IR")
    public static let taxiSquad = Self(rawValue: "TS")
}
