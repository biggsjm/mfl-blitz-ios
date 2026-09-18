import Foundation

/// Local evidence about the data being viewed, not a provider-wide uptime check.
/// Resolving or displaying these values never makes a network request.
struct ScoringDataStatus: Equatable {
    enum State: String {
        case updating = "Updating", connected = "Connected", current = "Up to date"
        case delayed = "Delayed", unavailable = "Unavailable", attention = "Needs attention"
        case idle = "Idle", off = "Not enabled", checking = "Checking", preview = "Preview"
        var symbol: String {
            switch self {
            case .updating, .connected, .current: "checkmark.circle.fill"
            case .delayed, .attention: "exclamationmark.circle.fill"
            case .unavailable: "xmark.circle.fill"
            case .idle, .off: "pause.circle.fill"
            case .checking: "clock.fill"
            case .preview: "eye.circle.fill"
            }
        }
    }
    var state: State
    var detail: String
    var checkedAt: Date? = nil

    static func mfl(snapshot: ScoresSnapshot, live: Bool, refreshing: Bool, failed: Bool,
                    offline: Bool, saved: Bool, preview: Bool, now: Date) -> Self {
        if preview { return .init(state: .preview, detail: "Sample scores; no live connection.") }
        let receipt = snapshot.checkedAt.flatMap { $0 > .distantPast && $0 <= now ? $0 : nil }
        if offline { return .init(state: .delayed, detail: "You’re offline. Showing the last saved scores.", checkedAt: receipt) }
        if failed { return .init(state: receipt == nil ? .unavailable : .delayed,
            detail: "The last score check failed. Scores will retry automatically.", checkedAt: receipt) }
        if saved { return .init(state: .delayed, detail: "Showing saved scores while the app reconnects.", checkedAt: receipt) }
        guard let receipt else { return .init(state: .checking, detail: "Waiting for the first score check.") }
        if live && now.timeIntervalSince(receipt) >= ScoreFreshness.staleAfter {
            return .init(state: .delayed, detail: "Live scores haven’t refreshed recently.", checkedAt: receipt)
        }
        return .init(state: live ? .updating : .idle,
            detail: live ? "Receiving fantasy scores from MFL. MFL may trail the game." : "No games active here. Using the latest saved scores.",
            checkedAt: receipt)
    }

    static func nfl(players: [MatchupPlayer], week: Int, feed: NFLWeekFeed?,
                    scoringGames: NFLScoringSnapshot?, availability: PlayerAvailabilitySnapshot?, scope: String?,
                    mflCheckedAt: Date?, configured: Bool, failures: Int, loading: Bool,
                    preview: Bool, now: Date) -> Self {
        if preview { return .init(state: .preview, detail: "Sample NFL stats; no live connection.") }
        guard configured else { return .init(state: .off, detail: "NFL stats aren’t connected for this account.") }
        let feed = feed.flatMap { $0.week == week ? $0 : nil }
        let games = scoringGames.flatMap { $0.week == week && $0.scope == scope ? $0 : nil }
        let availability = availability.flatMap { $0.week == week && $0.scope == scope ? $0 : nil }
        var expected = 0, active = false, missing = false, stale = false, usable = false
        var uncertain = players.isEmpty
        var receipts: [Date] = []
        for player in Set(players) {
            let game = feed?.game(team: player.nflTeam)
            uncertain = uncertain || (game == nil && player.gameState == .unknown)
            // A postponed or canceled fixture is not an active game merely
            // because its scheduled kickoff has passed.
            if let game, ["PST", "CANC", "SUSP", "INT"].contains(game.status) { continue }
            let mflGame = games?.games[player.nflTeam]
            let freshMFL = mflCheckedAt.map { $0 <= now && now.timeIntervalSince($0) < ScoreFreshness.staleAfter } == true
            let mflLive = (games?.isStale(now: now) == false && mflGame?.gameSecondsRemaining.map { (1..<3600).contains($0) } == true)
                || (freshMFL && player.gameState == .live)
            let hadGame = mflGame?.score != nil || availability?.games[player.nflTeam]?.kickoff.map { $0 <= now } == true
            let mflFinal = player.gameState == .final && hadGame && availability?.byeWeeks[player.nflTeam] != week
            let unconfirmedLive = player.gameState == .live && game?.isFinal != true && !freshMFL
            guard game?.isLive == true || game?.isFinal == true || mflLive || mflFinal || unconfirmedLive else { continue }
            expected += 1
            active = active || game?.isLive == true || mflLive
            guard let game else { missing = true; continue }
            let box = game.player(matching: player)
            let hasStats = box?.hasUsableStats == true
            usable = usable || hasStats
            if let stamp = game.statsReceipt(for: player), stamp > 0, stamp <= now.timeIntervalSince1970 {
                receipts.append(Date(timeIntervalSince1970: stamp))
            }
            // A successful HTTP response with NS/empty stats is not healthy
            // when MFL already confirms play. Zero-valued stats are valid.
            if game.status == "NS" || game.statsReceipt(for: player) == nil {
                missing = true
            } else if !hasStats {
                let boxes = NFLFeedGame.isDefense(player.position) ? (game.defenses ?? []) : game.players
                // Providers can omit players who haven't recorded any stats.
                // An empty game or unexplained fantasy points still needs attention.
                if !boxes.contains(where: \.hasUsableStats) || (player.livePoints ?? 0) != 0 { missing = true }
            }
            stale = stale || unconfirmedLive || game.statsAreStale(for: player, now: now) || game.gameIsStale(now: now)
        }
        let checked = receipts.min() // Oldest relevant box, never the HTTP receipt.
        if failures > 0 {
            return .init(state: failures >= 3 && !usable ? .unavailable : .delayed,
                detail: usable ? "Stats couldn’t refresh. Showing the last available stats." : "NFL stats couldn’t be reached. The app will retry automatically.", checkedAt: checked)
        }
        if expected == 0 {
            let checking = uncertain || (loading && feed == nil)
            return .init(state: checking ? .checking : .idle,
                detail: checking ? "Waiting for NFL game information." : "No active games here. Saved stats are kept between games.")
        }
        if missing { return .init(state: .delayed,
            detail: players.count == 1 ? "This player’s stats haven’t arrived yet. MFL points are tracked separately." : "Some player stats haven’t arrived yet. MFL points are tracked separately.", checkedAt: checked) }
        if stale { return .init(state: .delayed, detail: "Some NFL stats haven’t refreshed recently. Showing the last available stats.", checkedAt: checked) }
        return .init(state: active ? .updating : .current,
            detail: active ? "Recent NFL stats are available for the games shown." : "Final stats are saved for the games shown.", checkedAt: checked)
    }

    static func background(enabled: Bool, configured: Bool, tracking: Bool, registered: Bool,
                           attention: Bool, expiresAt: Date?, checkedAt: Date?, now: Date) -> Self {
        guard enabled, configured else { return .init(state: .off, detail: "Background Live Activity updates aren’t enabled on this iPhone.") }
        if attention { return .init(state: .attention, detail: "Background scoring couldn’t connect. Scores still refresh while Blitz is open.", checkedAt: checkedAt) }
        if registered, let expiresAt, expiresAt > now {
            return .init(state: .connected, detail: "This iPhone’s Live Activity is registered for background updates.", checkedAt: checkedAt)
        }
        if expiresAt != nil { return .init(state: .attention, detail: "Open your live matchup to reconnect background updates.", checkedAt: checkedAt) }
        return .init(state: tracking ? .checking : .idle,
            detail: tracking ? "Connecting this Live Activity for background updates." : "Open a live matchup to start background updates.")
    }

    static func alerts(permissionKnown: Bool, permissionRequired: Bool, busy: Bool,
                       week: Int, acknowledgedWeek: Int?, expiresAt: Date?, now: Date) -> Self {
        if permissionRequired { return .init(state: .attention, detail: "Allow notifications in Lineup alerts to receive reminders.") }
        if permissionKnown, acknowledgedWeek == week, let expiresAt, expiresAt > now {
            return .init(state: .connected, detail: "Alerts are registered for your saved Week \(week) lineup.")
        }
        return .init(state: busy ? .checking : .attention,
            detail: busy ? "Connecting alerts for Week \(week)." : "Open Lineup alerts to reconnect your Week \(week) reminders.")
    }
}

extension NFLFeedPlayer {
    var hasUsableStats: Bool {
        groups.contains { $0.stats.contains { stat in
            guard let value = stat.value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !value.isEmpty && !["-", "—", "N/A"].contains(value.uppercased())
        } }
    }
}
