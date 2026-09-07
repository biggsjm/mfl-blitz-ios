import Foundation

public struct MFLLeagueCalendarResponse: Decodable, Sendable {
    public let calendar: MFLLeagueCalendar
}

public struct MFLLeagueCalendar: Codable, Equatable, Sendable {
    public var events: [MFLCalendarEvent]

    public init(events: [MFLCalendarEvent]) { self.events = events }

    public init(from decoder: any Decoder) throws {
        let raw = try MFLJSONValue(from: decoder)
        guard let object = raw.objectValue else { throw MFLCoreError.invalidResponse }
        guard let rows = object["event"] else {
            guard object.isEmpty else { throw MFLCoreError.invalidResponse }
            events = []; return
        }
        events = try (rows.arrayValue ?? [rows]).map(MFLCalendarEvent.init(value:))
        guard events.count <= 1_000, Set(events.map(\.id)).count == events.count else { throw MFLCoreError.invalidResponse }
    }

    public func encode(to encoder: any Encoder) throws {
        // Keep the wire-shaped encoding so persisted snapshots use the same strict decoder.
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .event)
    }
    private enum CodingKeys: String, CodingKey { case event }
}

public struct MFLCalendarEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: String
    public var title: String
    public var start: Date
    public var end: Date?
    /// MFL's weekly count. Kept as metadata until a recurrence time zone is verified.
    public var repetitions: Int?

    public init(id: String, type: String, title: String = "", start: Date, end: Date? = nil, repetitions: Int? = nil) {
        self.id = id; self.type = type; self.title = title; self.start = start; self.end = end; self.repetitions = repetitions
    }

    init(value: MFLJSONValue) throws {
        guard let fields = value.objectValue,
              let id = fields["id"]?.stringValue, !id.isEmpty,
              let type = fields["type"]?.stringValue, !type.isEmpty else { throw MFLCoreError.invalidResponse }
        func date(_ key: String) throws -> Date? {
            guard let raw = fields[key]?.stringValue, !raw.isEmpty else { return nil }
            guard let seconds = TimeInterval(raw), seconds.isFinite, seconds >= 0, seconds < 4_200_000_000 else {
                throw MFLCoreError.invalidResponse
            }
            return Date(timeIntervalSince1970: seconds)
        }
        guard let start = try date("start_time") else { throw MFLCoreError.invalidResponse }
        let end = try date("end_time")
        guard end.map({ $0 >= start }) ?? true else { throw MFLCoreError.invalidResponse }
        let repeatText = fields["happens"]?.stringValue ?? ""
        let repetitions: Int?
        if repeatText.isEmpty { repetitions = nil }
        else {
            guard let count = Int(repeatText), (0...104).contains(count) else { throw MFLCoreError.invalidResponse }
            repetitions = count
        }
        self.init(id: id, type: type, title: fields["title"]?.stringValue ?? "", start: start, end: end, repetitions: repetitions)
    }

    public init(from decoder: any Decoder) throws { try self.init(value: MFLJSONValue(from: decoder)) }
    private enum CodingKeys: String, CodingKey { case id, type, title, start_time, end_time, happens }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id); try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encode(String(Int(start.timeIntervalSince1970)), forKey: .start_time)
        try container.encode(end.map { String(Int($0.timeIntervalSince1970)) } ?? "", forKey: .end_time)
        try container.encode(repetitions.map(String.init) ?? "", forKey: .happens)
    }
}
