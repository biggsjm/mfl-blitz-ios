@preconcurrency import ActivityKit
import Foundation
import Observation

enum MatchupActivityPolicy {
    static let maximumAge: TimeInterval = ScoreFreshness.staleAfter

    /// A matchup needs a positively identified, actively scoring starter. Bench,
    /// pregame, unknown clocks, historical weeks and cached sessions never start it.
    static func matchup(in scores: ScoresSnapshot, workspace: LeagueWorkspace, currentWeek: Int, now: Date) -> Matchup? {
        guard let matchup = currentMatchup(in: scores, workspace: workspace, currentWeek: currentWeek, now: now),
              activePlayers(in: matchup) > 0 else { return nil }
        return matchup
    }

    /// Start eligibility is stricter than retention. An existing activity must
    /// survive partial reads and the gap between early and late NFL games.
    static func currentMatchup(in scores: ScoresSnapshot, workspace: LeagueWorkspace, currentWeek: Int, now: Date) -> Matchup? {
        guard workspace.weekIsConfirmed, scores.week == currentWeek,
              let checkedAt = scores.checkedAt,
              now.timeIntervalSince(checkedAt) >= 0,
              now.timeIntervalSince(checkedAt) < maximumAge else { return nil }
        let owned = scores.matchups.filter { $0.home.id == workspace.franchiseID || $0.away.id == workspace.franchiseID }
        guard owned.count == 1, let matchup = owned.first,
              matchup.home.reportedScore != nil, matchup.away.reportedScore != nil else { return nil }
        return matchup
    }

    static func phase(in matchup: Matchup) -> String? {
        if activePlayers(in: matchup) > 0 { return "live" }
        for team in [matchup.home, matchup.away] {
            guard !team.starters.isEmpty, team.unclassifiedPlayers.isEmpty,
                  Set(team.players.map(\.id)).count == team.players.count,
                  team.starters.allSatisfy({ $0.lineupStatus == .starter &&
                      ($0.gameSecondsRemaining == 0 || $0.gameSecondsRemaining == 3600) }),
                  team.playersRemaining == team.starters.filter({ $0.gameSecondsRemaining == 3600 }).count
            else { return nil }
        }
        return matchup.home.playersRemaining == 0 && matchup.away.playersRemaining == 0 ? "final" : "waiting"
    }

    static func activePlayers(in matchup: Matchup) -> Int {
        (matchup.home.starters + matchup.away.starters).filter { $0.lineupStatus == .starter && $0.gameState == .live }.count
    }
    static func remaining(in team: MatchupTeam) -> (playing: Int, waiting: Int)? {
        let clocks=team.starters.compactMap(\.gameSecondsRemaining)
        guard !clocks.isEmpty,clocks.count==team.starters.count,team.unclassifiedPlayers.isEmpty,
              Set(team.starters.map(\.id)).count==team.starters.count,clocks.allSatisfy({ (0...3600).contains($0) }),
              team.playersRemaining==clocks.filter({ $0>0 }).count else { return nil }
        return (clocks.filter { $0>0 && $0<3600 }.count,clocks.filter { $0==3600 }.count)
    }

    static func matches(_ attributes: MatchupActivityAttributes, matchup: Matchup, scope: String, week: Int) -> Bool {
        guard attributes.scope == scope, attributes.week == week else { return false }
        if let home = attributes.homeID, let away = attributes.awayID {
            return home == matchup.home.id && away == matchup.away.id
        }
        // Older activities used MFL's response-array order as the fallback ID.
        return attributes.matchupID == matchup.id ||
            attributes.matchupID == "\(matchup.home.id)-\(matchup.away.id)" ||
            attributes.matchupID == "\(matchup.away.id)-\(matchup.home.id)"
    }
}

struct MatchupActivityFinalCheck {
    private var roster: [String]?
    private var firstFinal: Date?

    mutating func phase(for matchup: Matchup, checkedAt: Date) -> String? {
        guard let phase = MatchupActivityPolicy.phase(in: matchup) else { firstFinal = nil; return nil }
        let ids = matchup.home.starters.map { "home:\($0.id)" }.sorted() + matchup.away.starters.map { "away:\($0.id)" }.sorted()
        guard phase == "final" else {
            firstFinal = nil
            if matchup.home.unclassifiedPlayers.isEmpty, matchup.away.unclassifiedPlayers.isEmpty,
               !matchup.home.starters.isEmpty, !matchup.away.starters.isEmpty { roster = ids }
            return phase
        }
        // A partial lineup cannot end an activity whose full starters were seen.
        guard roster == nil || roster == ids else { firstFinal = nil; return "waiting" }
        roster = ids
        if let firstFinal {
            let interval = checkedAt.timeIntervalSince(firstFinal)
            if interval >= 60 && interval < MatchupActivityPolicy.maximumAge { return "final" }
            if interval >= 0 && interval < 60 { return "waiting" }
        }
        firstFinal = checkedAt
        return "waiting"
    }
}

struct MatchupActivityLifecycleEvent: Codable, Identifiable {
    var date: Date
    var message: String
    var id: Date { date }
}

@MainActor @Observable
final class MatchupActivityController {
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "matchup-live-activity-enabled") }
    }
    private(set) var errorMessage: String?
    private(set) var statusMessage = "Waiting for your live matchup."
    private(set) var lifecycleHistory: [MatchupActivityLifecycleEvent] = []
    let backgroundSync = MatchupBackgroundSync()
    private let defaults: UserDefaults
    private var scope: String?
    private var activity: Activity<MatchupActivityAttributes>?
    private var observation: Task<Void, Never>?
    private var dismissedKey: String?
    private var allowWaitingStart = false
    private var continuationAvailable = false
    var needsContinuation: Bool {
        continuationAvailable || activity?.content.state.continuationNeeded == true ||
            backgroundSync.expiresAt.map { $0.timeIntervalSinceNow < 1800 } == true
    }
    private var isUpdating = false
    private var generation = 0
    private var changeTracker = MatchupActivityChangeTracker()
    private var finalCheck = MatchupActivityFinalCheck()
    private var artworkTask: Task<Void, Never>?
    private var artworkPublication: Task<Void, Never>?
    private var artworkPublicationPending = false
    private var submittedState: MatchupActivityAttributes.ContentState?
    private var artworkKey: String?
    private var artworkAttempt: Date?
    private var homeArtwork: MatchupActivityAttributes.Artwork?
    private var awayArtwork: MatchupActivityAttributes.Artwork?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // This feature was requested to appear automatically during the matchup;
        // iOS's own Live Activities setting always takes precedence.
        enabled = defaults.object(forKey: "matchup-live-activity-enabled") as? Bool ?? true
        if let data = defaults.data(forKey: "matchup-live-activity-history"),
           let history = try? JSONDecoder().decode([MatchupActivityLifecycleEvent].self, from: data) {
            lifecycleHistory = Array(history.suffix(30))
        }
    }

    func scorePreview(scope: String?, week: Int, matchupID: String) -> ScoresSnapshot? {
        guard let scope else { return nil }
        return Activity<MatchupActivityAttributes>.activities.sorted { $0.content.state.updatedAt > $1.content.state.updatedAt }
            .compactMap { ScoringLiveReceipt.preview(attributes: $0.attributes, state: $0.content.state,
                scope: scope, week: week, matchupID: matchupID) }.first
    }

    /// Read the activity's delivered content when returning from the Lock Screen.
    /// Only the matching matchup may borrow this receipt; player rows keep theirs.
    func latestScoreState(matchup: Matchup, scope: String?, week: Int) -> MatchupActivityAttributes.ContentState? {
        guard let scope else { return nil }
        var candidates = Activity<MatchupActivityAttributes>.activities
        if let activity, !candidates.contains(where: { $0.id == activity.id }) { candidates.append(activity) }
        return candidates.filter {
            MatchupActivityPolicy.matches($0.attributes, matchup: matchup, scope: scope, week: week)
        }.map { candidate in
            candidate.id == activity?.id
                ? candidate.content.state.reconciling(with: submittedState)
                : candidate.content.state
        }.max { $0.updatedAt < $1.updatedAt }
    }

    func synchronize(scores: ScoresSnapshot, workspace: LeagueWorkspace, currentWeek: Int, isDemo: Bool, isCached: Bool,
                     standings: [StandingRow] = [], nflFeed: NFLWeekFeed? = nil) async {
        guard !isDemo, !isCached, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false; publishPreparedArtwork() }
        if scope != workspace.storageScope {
            if scope != nil { await end(reason: "Stopped after changing league or team.") }
            scope = workspace.storageScope
            dismissedKey = defaults.string(forKey: "matchup-live-activity-dismissed")
        }
        guard enabled else { await end(reason: "Live Activities turned off in Blitz."); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { await end(reason: "Live Activities unavailable in iOS Settings."); return }
        let requestGeneration = generation
        // A stale or unrelated response is not evidence that the games ended.
        guard scores.week == currentWeek, workspace.weekIsConfirmed,
              let checkedAt = scores.checkedAt,
              Date().timeIntervalSince(checkedAt) >= 0,
              Date().timeIntervalSince(checkedAt) < MatchupActivityPolicy.maximumAge else { return }
        // A missing total, owner matchup, or clock is not an instruction to end.
        guard let matchup = MatchupActivityPolicy.currentMatchup(in: scores, workspace: workspace, currentWeek: currentWeek, now: Date()),
              let phase = finalCheck.phase(for: matchup, checkedAt: checkedAt) else { return }
        let key = "\(workspace.storageScope)|\(scores.week)|\(matchup.id)"
        guard dismissedKey != key else { return }
        var attributes = MatchupActivityAttributes(scope: workspace.storageScope, week: scores.week, matchupID: matchup.id,
            homeName: String(matchup.home.name.prefix(80)), awayName: String(matchup.away.name.prefix(80)),
            homeAbbreviation: String(matchup.home.abbreviation.prefix(5)), awayAbbreviation: String(matchup.away.abbreviation.prefix(5)),
            backgroundPush: backgroundSync.canRequestPush ? true : nil,
            homeID: matchup.home.id, awayID: matchup.away.id)
        if activity == nil {
            let available = Activity<MatchupActivityAttributes>.activities
            if let lastID = defaults.string(forKey: "matchup-live-activity-last-id"), !available.contains(where: { $0.id == lastID }) {
                recordLifecycle("Previous activity was no longer available when Blitz reopened.")
                defaults.removeObject(forKey: "matchup-live-activity-last-id")
            }
            for existing in available {
                guard existing.activityState == .active || existing.activityState == .stale else { continue }
                if MatchupActivityPolicy.matches(existing.attributes, matchup: matchup, scope: workspace.storageScope, week: scores.week),
                   !backgroundSync.canRequestPush || existing.attributes.backgroundPush == true {
                    activity = existing
                    recordLifecycle("Reconnected to the existing Live Activity.")
                    observe(existing, key: key)
                } else {
                    recordLifecycle("Replaced an activity for another matchup or push setup.")
                    await existing.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
        if let activity, !MatchupActivityPolicy.matches(activity.attributes, matchup: matchup, scope: workspace.storageScope, week: scores.week) {
            recordLifecycle("Stopped after the current matchup changed.")
            await endActivities()
        }
        // Retain/update an existing activity between games, but never start a
        // fresh activity for an upcoming or already-finished matchup.
        guard activity != nil || phase == "live" || (allowWaitingStart && phase == "waiting") else { return }
        if let activity { attributes = activity.attributes }
        else { submittedState = nil }
        changeTracker.observe(matchup, scope: workspace.storageScope, week: scores.week,
            checkedAt: checkedAt, precision: scores.scorePrecision, now: Date())
        let imageKey = key + "|" + (matchup.away.artworkURLs + matchup.home.artworkURLs).map(\.absoluteString).joined(separator: "|")
        if artworkKey != imageKey {
            artworkTask?.cancel(); artworkTask = nil; artworkAttempt = nil
            homeArtwork = activity?.content.state.homeArtwork
            awayArtwork = activity?.content.state.awayArtwork
            artworkKey = imageKey
        }
        var state = MatchupActivityAttributes.ContentState(
            homeScore: matchup.home.score.pointsText(precision: scores.scorePrecision),
            awayScore: matchup.away.score.pointsText(precision: scores.scorePrecision),
            activePlayers: MatchupActivityPolicy.activePlayers(in: matchup), updatedAt: checkedAt,
            homeProjection: ScoringGamePresentation.projection(for: matchup.home, in: matchup, stale: false).points?.pointsText(precision: scores.scorePrecision),
            awayProjection: ScoringGamePresentation.projection(for: matchup.away, in: matchup, stale: false).points?.pointsText(precision: scores.scorePrecision),
            latestChange: changeTracker.latest, homeArtwork: homeArtwork, awayArtwork: awayArtwork, phase: phase)
            .preservingArtwork(from: activity?.content.state)
        let home=MatchupActivityPolicy.remaining(in:matchup.home),away=MatchupActivityPolicy.remaining(in:matchup.away)
        state.homePlaying=home?.playing; state.homeYetToPlay=home?.waiting
        state.awayPlaying=away?.playing; state.awayYetToPlay=away?.waiting
        let starters=matchup.away.starters+matchup.home.starters
        state.nextKickoff=starters.compactMap { player -> Date? in
            guard let game=nflFeed?.game(team:player.nflTeam),game.status=="NS",!game.gameIsStale(),game.kickoff>Date().timeIntervalSince1970 else { return nil }
            return Date(timeIntervalSince1970:game.kickoff)
        }.min()
        if let pid=state.latestChange?.playerID,let player=starters.first(where:{$0.id==pid}),
           let game=nflFeed?.game(team:player.nflTeam),!game.statsAreStale(for:player),
           let text=game.player(matching:player)?.summary,text.count<=160 { state.statContext=text }
        state.continuationNeeded=needsContinuation
        // Resume token tracking and artwork recovery even when a push is newer
        // than the foreground response. Never move its score timestamp backward.
        state = state.reconciling(with: submittedState).reconciling(with: activity?.content.state)
        state.homeRecord = nil; state.awayRecord = nil
        let content = ActivityContent(state: state.fittingActivityBudget(attributes: attributes),
            staleDate: state.phase == "final" ? nil : state.updatedAt.addingTimeInterval(MatchupActivityPolicy.maximumAge))
        do {
            guard generation == requestGeneration, enabled, scope == workspace.storageScope else { return }
            submittedState = content.state
            if state.phase == "final", let activity {
                recordLifecycle("Ended after confirmed final scores.")
                defaults.removeObject(forKey: "matchup-live-activity-last-id")
                observation?.cancel(); observation = nil
                self.activity = nil
                artworkTask?.cancel(); artworkTask = nil
                artworkPublication?.cancel(); artworkPublication = nil; artworkPublicationPending = false
                await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(900)))
                await backgroundSync.stop(id: activity.id)
                statusMessage = "Final score."
                return
            }
            if let activity { await activity.update(content) }
            else {
                let created = try Activity.request(attributes: attributes, content: content, pushType: backgroundSync.canRequestPush ? .token : nil)
                activity = created
                allowWaitingStart = false
                recordLifecycle("Started a Live Activity.")
                observe(created, key: key)
            }
            guard generation == requestGeneration, enabled, scope == workspace.storageScope,
                  let activity, activity.activityState == .active || activity.activityState == .stale else { return }
            backgroundSync.track(activity, value: MatchupSyncRegistration(workspace: workspace,
                matchup: matchup, precision: scores.scorePrecision, attributes: attributes, state: content.state))
            statusMessage = state.phase == "waiting" ? "Live Activity is waiting for the next game." : "Live Activity is running."
            errorMessage = nil
            loadArtwork(for: matchup, key: imageKey)
        } catch {
            recordLifecycle("iOS could not start the Live Activity.")
            errorMessage = "The Live Activity couldn’t start. Check Live Activities in iOS Settings."
        }
    }

    private func loadArtwork(for matchup: Matchup, key: String) {
        guard artworkTask == nil,
              homeArtwork?.imageData == nil || awayArtwork?.imageData == nil,
              artworkAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        artworkAttempt = Date()
        let generation = generation
        artworkTask = Task { [weak self] in
            async let home = MatchupActivityArtworkStore.shared.prepare(urls: matchup.home.artworkURLs)
            async let away = MatchupActivityArtworkStore.shared.prepare(urls: matchup.away.artworkURLs)
            let images = await (home, away)
            guard !Task.isCancelled, let self, self.generation == generation, self.artworkKey == key else { return }
            self.homeArtwork = images.0 ?? self.homeArtwork; self.awayArtwork = images.1 ?? self.awayArtwork
            self.artworkTask = nil
            guard images.0 != nil || images.1 != nil else { return }
            self.artworkPublicationPending = true
            self.publishPreparedArtwork()
        }
    }

    private func publishPreparedArtwork() {
        guard artworkPublicationPending, !isUpdating, let activity,
              activity.activityState == .active || activity.activityState == .stale else { return }
        artworkPublicationPending = false
        var state = (submittedState ?? activity.content.state).reconciling(with: activity.content.state)
        state.homeArtwork = homeArtwork ?? state.homeArtwork
        state.awayArtwork = awayArtwork ?? state.awayArtwork
        let content = ActivityContent(state: state.fittingActivityBudget(attributes: activity.attributes),
            staleDate: state.updatedAt.addingTimeInterval(MatchupActivityPolicy.maximumAge))
        submittedState = content.state
        isUpdating = true
        let generation = generation
        // Capture the exact outgoing value. Activity.content is an asynchronously
        // observed snapshot, not a receipt containing this just-submitted artwork.
        artworkPublication = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isUpdating = false
                self.artworkPublication = nil
                self.publishPreparedArtwork()
            }
            await self.backgroundSync.publishArtwork(content: content, updateActivity: { content in
                await activity.update(content)
            }, isCurrent: { [weak self] in
                !Task.isCancelled && self?.generation == generation && self?.activity?.id == activity.id
            })
        }
    }

    private func observe(_ observed: Activity<MatchupActivityAttributes>, key: String) {
        defaults.set(observed.id, forKey: "matchup-live-activity-last-id")
        observation?.cancel()
        observation = Task { [weak self] in
                    for await status in observed.activityStateUpdates {
                        guard !Task.isCancelled else { return }
                        guard self?.activity?.id == observed.id else { return }
                        if status == .dismissed {
                            self?.continuationAvailable = observed.content.state.continuationNeeded == true
                            self?.recordLifecycle("iOS reported that the Live Activity was removed.")
                            self?.statusMessage = "Live Activity was removed. You can restart it below."
                            self?.dismissedKey = key
                            self?.defaults.set(key, forKey: "matchup-live-activity-dismissed")
                            self?.activity = nil
                            await self?.backgroundSync.stop(id: observed.id)
                        } else if status == .ended {
                            self?.continuationAvailable = observed.content.state.continuationNeeded == true
                            self?.recordLifecycle("iOS reported that the Live Activity ended.")
                            self?.statusMessage = "Live Activity ended."
                            self?.activity = nil
                            await self?.backgroundSync.stop(id: observed.id)
                        } else if status == .stale {
                            self?.recordLifecycle("Live Activity is waiting for a fresh score update.")
                            self?.statusMessage = "Live Activity is waiting for fresh scores."
                        } else if status == .active {
                            self?.statusMessage = "Live Activity is running."
                        }
                    }
        }
    }

    func recordLifecycle(_ message: String, date: Date = .now) {
        guard lifecycleHistory.last?.message != message else { return }
        lifecycleHistory = Array((lifecycleHistory + [.init(date: date, message: message)]).suffix(30))
        if let data = try? JSONEncoder().encode(lifecycleHistory) { defaults.set(data, forKey: "matchup-live-activity-history") }
    }

    func end(reason: String = "Stopped in Blitz.") async {
        generation += 1
        recordLifecycle(reason)
        statusMessage = "Live Activity stopped."
        await endActivities()
    }

    func markStale(week: Int, scope: String) async {
        guard let activity, activity.attributes.week == week, activity.attributes.scope == scope else { return }
        // A failed foreground read cannot invalidate a still-fresh server receipt.
        // ActivityKit's existing staleDate will mark it delayed if pushes stop.
        guard activity.attributes.backgroundPush != true else { return }
        changeTracker.reset()
        await activity.update(ActivityContent(state: activity.content.state, staleDate: .now))
    }

    private func endActivities() async {
        let ending = Activity<MatchupActivityAttributes>.activities
        artworkTask?.cancel(); artworkTask = nil
        artworkPublication?.cancel(); artworkPublication = nil; artworkPublicationPending = false
        submittedState = nil
        artworkKey = nil; artworkAttempt = nil; homeArtwork = nil; awayArtwork = nil
        changeTracker.reset()
        finalCheck = MatchupActivityFinalCheck()
        defaults.removeObject(forKey: "matchup-live-activity-last-id")
        observation?.cancel(); observation = nil
        activity = nil
        await backgroundSync.stop()
        for existing in ending {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
    }

    func resume(allowWaiting: Bool = false) {
        allowWaitingStart = allowWaiting; continuationAvailable = false
        dismissedKey = nil; defaults.removeObject(forKey: "matchup-live-activity-dismissed")
        statusMessage = "Waiting for your live matchup."
    }
    func disconnect() async { await end(); resume(); scope = nil }
}
