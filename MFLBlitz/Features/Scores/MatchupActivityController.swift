@preconcurrency import ActivityKit
import Foundation
import Observation

enum MatchupActivityPolicy {
    static let maximumAge: TimeInterval = 120

    /// A matchup needs a positively identified, actively scoring starter. Bench,
    /// pregame, unknown clocks, historical weeks and cached sessions never start it.
    static func matchup(in scores: ScoresSnapshot, workspace: LeagueWorkspace, currentWeek: Int, now: Date) -> Matchup? {
        guard workspace.weekIsConfirmed, scores.week == currentWeek,
              now.timeIntervalSince(scores.lastUpdated) >= 0,
              now.timeIntervalSince(scores.lastUpdated) < maximumAge else { return nil }
        let owned = scores.matchups.filter { $0.home.id == workspace.franchiseID || $0.away.id == workspace.franchiseID }
        guard owned.count == 1, let matchup = owned.first,
              matchup.home.score.isFinite, matchup.away.score.isFinite,
              activePlayers(in: matchup) > 0 else { return nil }
        return matchup
    }

    static func activePlayers(in matchup: Matchup) -> Int {
        (matchup.home.starters + matchup.away.starters).filter { $0.lineupStatus == .starter && $0.gameState == .live }.count
    }
}

@MainActor @Observable
final class MatchupActivityController {
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "matchup-live-activity-enabled") }
    }
    private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private var scope: String?
    private var activity: Activity<MatchupActivityAttributes>?
    private var observation: Task<Void, Never>?
    private var dismissedKey: String?
    private var isUpdating = false
    private var generation = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // This feature was requested to appear automatically during the matchup;
        // iOS's own Live Activities setting always takes precedence.
        enabled = defaults.object(forKey: "matchup-live-activity-enabled") as? Bool ?? true
    }

    func synchronize(scores: ScoresSnapshot, workspace: LeagueWorkspace, currentWeek: Int, isDemo: Bool, isCached: Bool) async {
        guard !isDemo, !isCached, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        if scope != workspace.storageScope {
            if scope != nil { await end() }
            scope = workspace.storageScope
            dismissedKey = defaults.string(forKey: "matchup-live-activity-dismissed")
        }
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { await end(); return }
        let requestGeneration = generation
        // A stale or unrelated response is not evidence that the games ended.
        guard scores.week == currentWeek, workspace.weekIsConfirmed,
              Date().timeIntervalSince(scores.lastUpdated) >= 0,
              Date().timeIntervalSince(scores.lastUpdated) < MatchupActivityPolicy.maximumAge else { return }
        guard let matchup = MatchupActivityPolicy.matchup(in: scores, workspace: workspace, currentWeek: currentWeek, now: Date()) else {
            await end(); return
        }
        let key = "\(workspace.storageScope)|\(scores.week)|\(matchup.id)"
        guard dismissedKey != key else { return }
        let attributes = MatchupActivityAttributes(scope: workspace.storageScope, week: scores.week, matchupID: matchup.id,
            homeName: String(matchup.home.name.prefix(80)), awayName: String(matchup.away.name.prefix(80)),
            homeAbbreviation: String(matchup.home.abbreviation.prefix(5)), awayAbbreviation: String(matchup.away.abbreviation.prefix(5)))
        let state = MatchupActivityAttributes.ContentState(
            homeScore: matchup.home.score.formatted(.number.precision(.fractionLength(min(3, max(0, scores.scorePrecision))))),
            awayScore: matchup.away.score.formatted(.number.precision(.fractionLength(min(3, max(0, scores.scorePrecision))))),
            activePlayers: MatchupActivityPolicy.activePlayers(in: matchup), updatedAt: scores.lastUpdated)
        let content = ActivityContent(state: state, staleDate: scores.lastUpdated.addingTimeInterval(MatchupActivityPolicy.maximumAge))
        if activity == nil {
            for existing in Activity<MatchupActivityAttributes>.activities {
                if existing.attributes.scope == attributes.scope, existing.attributes.week == attributes.week,
                   existing.attributes.matchupID == attributes.matchupID {
                    activity = existing
                    observe(existing, key: key)
                } else { await existing.end(nil, dismissalPolicy: .immediate) }
            }
        }
        if let activity, activity.attributes.week != attributes.week || activity.attributes.matchupID != attributes.matchupID {
            await endActivities()
        }
        do {
            guard generation == requestGeneration, enabled, scope == workspace.storageScope else { return }
            if let activity { await activity.update(content) }
            else {
                let created = try Activity.request(attributes: attributes, content: content, pushType: nil)
                activity = created
                observe(created, key: key)
            }
            errorMessage = nil
        } catch { errorMessage = "The Live Activity couldn’t start. Check Live Activities in iOS Settings." }
    }

    private func observe(_ observed: Activity<MatchupActivityAttributes>, key: String) {
        observation?.cancel()
        observation = Task { [weak self] in
                    for await status in observed.activityStateUpdates {
                        guard !Task.isCancelled else { return }
                        guard self?.activity?.id == observed.id else { return }
                        if status == .dismissed {
                            self?.dismissedKey = key
                            self?.defaults.set(key, forKey: "matchup-live-activity-dismissed")
                            self?.activity = nil
                        } else if status == .ended {
                            self?.activity = nil
                        }
                    }
        }
    }

    func end() async {
        generation += 1
        await endActivities()
    }

    private func endActivities() async {
        observation?.cancel(); observation = nil
        activity = nil
        for existing in Activity<MatchupActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
    }

    func resume() { dismissedKey = nil; defaults.removeObject(forKey: "matchup-live-activity-dismissed") }
    func disconnect() async { await end(); resume(); scope = nil }
}
