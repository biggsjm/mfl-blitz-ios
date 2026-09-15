import Foundation

struct MatchupTimelineUpdate: Identifiable {
    let id: String
    let date: Date
    let teamID: String?
    let teamChange: MatchupTimelineEvent?
    let players: [MatchupTimelineEvent]
    let other: [MatchupTimelineEvent]
    var delta: Double? { teamChange.flatMap { event in event.previous.flatMap { a in event.current.map { $0 - a } } } }

    static func grouped(_ events: [MatchupTimelineEvent]) -> [Self] {
        let scoreEvents = events.filter { $0.kind != "gap" && $0.kind != "tracking" }
        let groups = Dictionary(grouping: scoreEvents) { "\($0.at)|\($0.source)|\($0.teamID ?? "matchup")" }
        return groups.map { key, raw in
            let events = Dictionary(grouping: raw, by: \.id).compactMap { $0.value.first }
            return Self(id: key, date: events[0].date, teamID: events[0].teamID,
                teamChange: events.first { $0.kind == "team" },
                players: events.filter { $0.kind == "player" }.sorted { $0.name < $1.name },
                other: events.filter { $0.kind != "team" && $0.kind != "player" })
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
