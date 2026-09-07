import Foundation

/// Display-only context. Missing schedules are not byes, and kickoff alone
/// never proves that a game is live or final.
struct MatchupGameInfo {
    let opponent: String?
    let kickoff: Date?
    let status: String?
    let symbol: String
    let isLive: Bool

    init(player: MatchupPlayer, availability: PlayerAvailabilitySnapshot?, scope: String?, week: Int?,
         now: Date = Date()) {
        let data = availability.flatMap { $0.scope == scope && $0.week == week ? $0 : nil }
        let game = data?.games[player.nflTeam]
        isLive = player.gameState == .live

        if let week, data?.byeWeeks[player.nflTeam] == week && !isLive {
            opponent = nil; kickoff = nil; status = "Bye week"; symbol = "calendar"
        } else if isLive {
            opponent = game?.opponentLabel; kickoff = nil; status = "Live"
            symbol = "dot.radiowaves.left.and.right"
        } else if player.gameState == .final, let game,
                  game.kickoff.map({ $0 <= now }) ?? true {
            opponent = game.opponentLabel; kickoff = nil; status = "Final"; symbol = "checkmark.circle"
        } else if let game {
            opponent = game.opponentLabel; kickoff = game.kickoff
            status = game.kickoff == nil ? "Time TBD" : nil; symbol = "clock"
        } else {
            opponent = nil; kickoff = nil
            switch player.gameState {
            case .pregame: status = "Yet to play"; symbol = "clock"
            case .final: status = "Final / no game"; symbol = "checkmark.circle"
            case .unknown: status = "Status unavailable"; symbol = "questionmark.circle"
            case .live: status = "Live"; symbol = "dot.radiowaves.left.and.right"
            }
        }
    }

    func label(locale: Locale, timeZone: TimeZone) -> String {
        let timing = kickoff.map { date in
            let day = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated))
            let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
            return "\(day) \(time)"
        } ?? status
        return [opponent, timing].compactMap { $0 }.joined(separator: " · ")
    }

    static func timeZoneLabel(locale: Locale, timeZone: TimeZone) -> String {
        "Times in \(timeZone.localizedName(for: .shortGeneric, locale: locale) ?? timeZone.identifier)"
    }
}
