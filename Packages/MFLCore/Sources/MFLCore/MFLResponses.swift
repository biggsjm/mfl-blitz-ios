import Foundation

public struct MFLLeagueResponse: Decodable, Equatable, Sendable {
    public let league: MFLLeague
}

public struct MFLPlayersResponse: Decodable, Equatable, Sendable {
    public let players: MFLPlayerCatalog
}

public struct MFLFreeAgentsResponse: Decodable, Equatable, Sendable {
    public let freeAgents: MFLFreeAgentPool
}

public struct MFLRostersResponse: Decodable, Equatable, Sendable {
    public let rosters: MFLRosterCollection
}

public struct MFLLiveScoringResponse: Decodable, Equatable, Sendable {
    public let liveScoring: MFLLiveScoring
}

public struct MFLLeagueStandingsResponse: Decodable, Equatable, Sendable {
    public let leagueStandings: MFLLeagueStandings
}

public struct MFLMessageBoardResponse: Decodable, Equatable, Sendable {
    public let messageBoard: MFLMessageBoard
}

public struct MFLMessageBoardThreadResponse: Decodable, Equatable, Sendable {
    public let messageBoardThread: MFLMessageThread
}

public struct MFLPendingWaiversResponse: Decodable, Equatable, Sendable {
    public let pendingWaivers: MFLPendingWaivers
}

/// Stateless convenience around the Foundation decoder used by `MFLClient`.
public struct MFLResponseDecoder: Sendable {
    public init() {}

    public func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw MFLCoreError.decoding(String(describing: error))
        }
    }
}

struct MFLAPIErrorEnvelope: Decodable {
    let error: MFLJSONValue?
}

extension MFLAPIErrorEnvelope {
    static func message(in data: Data) -> String? {
        (try? JSONDecoder().decode(Self.self, from: data))?.error?.stringValue
    }
}
