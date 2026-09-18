import Foundation

/// Display-only context. Missing schedules are not byes, and kickoff alone
/// never proves that a game is live or final.
struct MatchupGameInfo {
    let opponent: String?
    let kickoff: Date?
    let status: String?
    let symbol: String
    let isLive: Bool
    let scoreLabel: String?
    let compactScoreLabel: String?
    let gameIsStale: Bool
    let possessionLabel: String?
    let gameCheckedAt: Date?

    init(player: MatchupPlayer, availability: PlayerAvailabilitySnapshot?, scope: String?, week: Int?,
         scoringGames: NFLScoringSnapshot? = nil, nflGame: NFLFeedGame? = nil, now: Date = Date()) {
        let data = availability.flatMap { $0.scope == scope && $0.week == week ? $0 : nil }
        let liveData = scoringGames.flatMap { $0.scope == scope && $0.week == week ? $0 : nil }
        let liveGame = liveData?.games[player.nflTeam]
        let providerGame = nflGame.flatMap {
            $0.week == week && [$0.home, $0.away].contains(NFLFeedGame.team(player.nflTeam)) ? $0 : nil
        }
        let seconds = liveGame?.gameSecondsRemaining
        // NFL providers can still report NS after MFL starts scoring. A real
        // running clock proves play; scheduled kickoff or points alone do not.
        let mflIsLive = seconds.map { (1..<3600).contains($0) } == true ||
            (player.gameState == .live && (seconds == nil || seconds == 3600))
        let schedule = providerGame.map {
            let home = NFLFeedGame.team(player.nflTeam) == $0.home
            return NFLGameContext(opponent: home ? $0.away : $0.home, isHome: home,
                kickoff: Date(timeIntervalSince1970: $0.kickoff))
        }
        let game = liveGame ?? data?.games[player.nflTeam] ?? schedule
        if let nflGame = providerGame, nflGame.status != "NS" || !mflIsLive {
            let ownHome = NFLFeedGame.team(player.nflTeam) == nflGame.home
            let other = ownHome ? nflGame.away : nflGame.home
            opponent = "\(ownHome ? "vs" : "@") \(other)"
            isLive = nflGame.isLive
            gameIsStale = nflGame.gameIsStale(now: now)
            gameCheckedAt = Date(timeIntervalSince1970: nflGame.checkedAt)
            possessionLabel = nil
            if nflGame.status != "NS", let home = nflGame.homeScore, let away = nflGame.awayScore {
                scoreLabel = "\(ownHome ? nflGame.home : nflGame.away) \(Int(ownHome ? home : away)) · \(other) \(Int(ownHome ? away : home))"
                compactScoreLabel = "\(ownHome ? "vs" : "@") \(other) \(Int(ownHome ? home : away))–\(Int(ownHome ? away : home))"
            } else { scoreLabel = nil; compactScoreLabel = nil }
            kickoff = nflGame.status == "NS" ? Date(timeIntervalSince1970: nflGame.kickoff) : nil
            status = kickoff == nil ? nflGame.statusLabel : nil
            symbol = nflGame.isLive ? "dot.radiowaves.left.and.right" : nflGame.isFinal ? "checkmark.circle" : "clock"
            return
        }
        // A fresh receipt does not make the NFL scoreboard current. The
        // separate league feed can already have advanced well beyond it.
        // Allow ordinary clock corrections / short feed skew, but label a
        // scoreboard more than two game minutes behind as last known data.
        let behindPlayerClock: Bool
        if let seconds, let playerSeconds = player.gameSecondsRemaining,
           (1..<3600).contains(seconds), (1..<3600).contains(playerSeconds) {
            behindPlayerClock = seconds - playerSeconds > 120
        } else { behindPlayerClock = false }
        gameIsStale = (liveData?.isStale(now: now) ?? false) || behindPlayerClock
        gameCheckedAt = liveGame == nil ? nil : liveData?.checkedAt
        isLive = mflIsLive
        if let liveGame, let own = liveGame.score, let other = liveGame.opponentScore,
           seconds != 3600, liveGame.kickoff.map({ $0 <= now }) ?? true {
            scoreLabel = "\(player.nflTeam) \(own) · \(liveGame.opponent) \(other)"
            compactScoreLabel = "\(liveGame.opponentLabel) \(own)–\(other)"
        } else { scoreLabel = nil; compactScoreLabel = nil }
        if isLive, !gameIsStale, liveGame?.hasPossession == true {
            possessionLabel = liveGame?.inRedZone == true ? "Ball · Red zone" : "Has ball"
        } else { possessionLabel = nil }

        if let seconds, (1..<3600).contains(seconds) {
            opponent = game?.opponentLabel; kickoff = nil
            // MFL's remaining-time estimate can lag or move backward between
            // servers. It proves play, not the current quarter or game clock.
            // Only the NFL provider branch above supplies a real clock/break.
            status = "Live"
            symbol = "dot.radiowaves.left.and.right"
            return
        }
        if seconds == 0, scoreLabel != nil {
            opponent = game?.opponentLabel; kickoff = nil
            // An equal score at zero may still be heading to overtime.
            status = liveGame?.score == liveGame?.opponentScore ? "Regulation complete" : "Final"
            symbol = "checkmark.circle"
            return
        }

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
        [scoreLabel ?? opponent, timingLabel(locale: locale, timeZone: timeZone)].compactMap { $0 }.joined(separator: " · ")
    }

    func timingLabel(locale: Locale, timeZone: TimeZone) -> String? {
        kickoff.map { date in
            let day = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated))
            let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
            return "\(day) \(time)"
        } ?? status
    }

    static func timeZoneLabel(locale: Locale, timeZone: TimeZone) -> String {
        "Times in \(timeZone.localizedName(for: .shortGeneric, locale: locale) ?? timeZone.identifier)"
    }
}
