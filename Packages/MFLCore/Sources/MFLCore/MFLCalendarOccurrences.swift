import Foundation

public struct MFLCalendarOccurrence: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var seriesID: String
    public var type: String
    public var title: String
    public var start: Date
    public var end: Date?
}

public struct MFLCalendarOccurrences: Codable, Equatable, Sendable {
    public var events: [MFLCalendarOccurrence]
    public var recurrenceVerified: Bool

    public init(calendar: MFLLeagueCalendar, ics: String?) {
        events = calendar.events.map {
            MFLCalendarOccurrence(id: "\($0.id):0", seriesID: $0.id, type: $0.type, title: $0.title, start: $0.start, end: $0.end)
        }
        let repeating = calendar.events.filter { ($0.repetitions ?? 0) > 0 }
        recurrenceVerified = repeating.isEmpty
        guard !repeating.isEmpty, let ics, let rows = try? MFLICSReader.events(ics) else { return }
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        // MFL currently writes UTC clock values without a Z/TZID. Never interpret
        // these as the device's zone: every JSON anchor must independently agree
        // before we accept the explicitly expanded occurrences from this feed.
        guard !calendar.events.isEmpty, calendar.events.allSatisfy({ source in
            byID[source.id].map { $0.start == source.start && ($0.end == source.end || (source.end == nil && $0.end == source.start)) } ?? false
        }) else { return }
        let anchors = Set(calendar.events.map(\.id))
        var extra: [MFLCalendarOccurrence] = []
        var used: Set<String> = []
        for series in repeating {
            guard let anchor = byID[series.id], let count = series.repetitions,
                  repeating.filter({ byID[$0.id]?.summary == anchor.summary }).count == 1 else { return }
            let children = rows.filter { !anchors.contains($0.id) && $0.summary == anchor.summary && $0.start > series.start }
                .sorted { $0.start < $1.start }
            // Captured MFL ICS emits `happens` additional explicit occurrences.
            // Missing, duplicate, changed/unknown recurrence formats stay partial.
            guard children.count == count, Set(children.map(\.start)).count == children.count else { return }
            for (index, child) in children.enumerated() {
                guard used.insert(child.id).inserted,
                      child.start.timeIntervalSince(series.start) < 740 * 86_400 else { return }
                extra.append(MFLCalendarOccurrence(id: "\(series.id):\(index + 1)", seriesID: series.id,
                    type: series.type, title: series.title, start: child.start, end: child.end == child.start ? nil : child.end))
            }
        }
        guard used.count + anchors.count == rows.count else { return }
        events += extra
        events.sort { ($0.start, $0.id) < ($1.start, $1.id) }
        recurrenceVerified = true
    }
}

/// Deliberately constrained to the MFL export captured alongside its JSON feed,
/// not a general iCalendar importer. No guessed RRULE, floating-zone or date-only
/// interpretation can become a precise reminder.
enum MFLICSReader {
    struct Event { var id: String; var summary: String; var start: Date; var end: Date? }

    static func events(_ text: String) throws -> [Event] {
        guard text.utf8.count < 1_000_000, text.contains("BEGIN:VCALENDAR"), text.contains("END:VCALENDAR") else {
            throw MFLCoreError.invalidResponse
        }
        var lines: [String] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty { lines[lines.count - 1] += line.dropFirst() }
            else { lines.append(line) }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.isLenient = false
        func date(_ value: String?) throws -> Date {
            guard let value, value.count == 15, let date = formatter.date(from: value), formatter.string(from: date) == value else {
                throw MFLCoreError.invalidResponse
            }
            return date
        }
        var fields: [String: String]?
        var result: [Event] = []
        for line in lines {
            if line == "BEGIN:VEVENT" { guard fields == nil else { throw MFLCoreError.invalidResponse }; fields = [:] }
            else if line == "END:VEVENT" {
                guard let entry = fields, let uid = entry["UID"], uid.hasSuffix("@myfantasyleague.com"),
                      let summary = entry["SUMMARY"] else { throw MFLCoreError.invalidResponse }
                let start = try date(entry["DTSTART"])
                let end = try entry["DTEND"].map { try date($0) }
                guard end.map({ $0 >= start }) ?? true else { throw MFLCoreError.invalidResponse }
                result.append(Event(id: String(uid.dropLast("@myfantasyleague.com".count)), summary: summary, start: start, end: end))
                guard result.count <= 1_000 else { throw MFLCoreError.invalidResponse }
                fields = nil
            } else if fields != nil, let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon])
                guard ["UID", "SUMMARY", "DTSTAMP", "DTSTART", "DTEND"].contains(key), fields?[key] == nil else {
                    throw MFLCoreError.invalidResponse
                }
                fields?[key] = String(line[line.index(after: colon)...])
            }
        }
        guard fields == nil, Set(result.map(\.id)).count == result.count else { throw MFLCoreError.invalidResponse }
        return result
    }
}
