import Foundation
import Observation
import SwiftUI
import MFLCore

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case onboarding
        case signedIn
    }

    struct LineupSubmissionReceipt: Equatable, Sendable {
        let week: Int
        let starterIDs: Set<String>
        let tiebreakerPlayerIDs: [String]
    }

    struct LineupReplacementRequest: Identifiable {
        let id = UUID()
        let starter: LineupPlayer
        let slotLabel: String
        let week: Int
        fileprivate let sessionGeneration: Int
        fileprivate let assignments: [LineupSlotAssignment]
        fileprivate let positionRequirements: [LineupPositionRequirement]
        fileprivate let requiredStarterCount: Int
    }

    var phase: Phase = .onboarding
    var workspace: LeagueWorkspace?
    var scores = ScoresSnapshot(week: 1, matchups: [], lastUpdated: .distantPast, isLive: false)
    var lineup = LineupSnapshot(
        week: 1,
        players: [],
        requiredStarterCount: 0,
        positionRequirements: [],
        requiredTiebreakerCount: 0,
        tiebreakerPlayerIDs: [],
        deadline: nil,
        lastSubmitted: nil
    )
    var waivers = WaiverSnapshot(
        availableBudget: 0,
        increment: 1,
        maxRounds: 0,
        candidates: [],
        claims: [],
        processesAt: nil
    )
    var standings: [StandingRow] = []
    var teams: [TeamSummary] = []
    var boardThreads: [BoardThread] = []
    var transactions = TransactionsModel()
    var seasonSchedule = SeasonScheduleModel()
    var playerTools = PlayerToolsModel()
    var pendingRosterChange: PendingRosterAction?
    var rosterChangeError: String?
    var rosterRevision = 0
    var scopedScoreInspection: UUID?
    var selectedWeek = 1
    var isBusy = false
    var isRefreshing = false
    var isDemo = false
    var notice: AppNotice?
    var lineupRevision = 0
    var currentWeek = 1
    var scoreRefreshError: String?
    var lineupConflict: String?
    var waiverConflict: String?
    var waiverServerReadFailed = false
    var waiverReadError: String?
    var unconfirmedBoardPost: PendingBoardPost?
    var boardDraftRevision = 0
    var isRestoringSession = false
    var isLoadingScores = false
    var isLoadingLineup = false
    var isLoadingWaivers = false
    var isLoadingBoard = false
    private var restoreRequest: Task<LeagueWorkspace?, any Error>?
    private var didAttemptRestore = false
    private var followsCurrentWeek = true
    private var scoreRequestInFlight = false
    private var fullRefreshInFlight = false
    private var fullRefreshSession = -1
    private var drafts = LeagueDrafts()
    private let privateStore: any PrivateStore
    private var serverWaivers: [WaiverClaim] = []
    private var latestServerLineup: LineupSnapshot?
    private var lastFullRefresh: Date?
    private let foregroundRefreshInterval: TimeInterval
    private var lastWaiverRefresh: Date?

    var canEditLineup: Bool {
        isDemo || (LiveWritePolicy.lineupsEnabled && lineup.editState.allowsEditing)
    }
    var canChangeLineupDraft: Bool {
        canEditLineup && !isBusy && !isLoadingLineup && lineupConflict == nil && lineup.week == selectedWeek
    }
    var canSubmitLineup: Bool { !isBusy && !isLoadingLineup && canEditLineup && lineup.editState.allowsEditing && lineupConflict == nil && lineup.week == selectedWeek }
    var canSubmitWaivers: Bool { !isBusy && !isLoadingWaivers && waiverConflict == nil && (isDemo || (LiveWritePolicy.waiversEnabled && waivers.unavailableReason == nil)) }
    var canPostToBoard: Bool { isDemo || LiveWritePolicy.boardEnabled }
    var hasRestrictedLiveActions: Bool {
        !canEditLineup || !canSubmitWaivers || !canPostToBoard
    }

    private var repository: any LeagueRepository
    private var sessionGeneration = 0
    private var weekLoadGeneration = 0
    private var nextRefreshID = 0
    private var activeRefreshIDs: Set<Int> = []
    private var nextDemoMessageID = 0

    init(repository: any LeagueRepository = LiveMFLRepository(playerCacheDirectory: AppCacheLocations.players), privateStore: any PrivateStore = KeychainPrivateStore(), foregroundRefreshInterval: TimeInterval = 60) {
        self.repository = repository
        self.privateStore = privateStore
        self.foregroundRefreshInterval = foregroundRefreshInterval
        if repository is DemoLeagueRepository {
            installDemoContent()
        }
    }

    func restoreSession() async {
        guard !didAttemptRestore, phase == .onboarding, !isDemo else { return }
        didAttemptRestore = true
        isRestoringSession = true
        isBusy = true
        let generation = sessionGeneration
        defer {
            if generation == sessionGeneration {
                restoreRequest = nil
                if isRestoringSession { isRestoringSession = false; isBusy = false }
            }
        }
        let activeRepository = repository
        let request = Task { try await activeRepository.restoreSession() }
        restoreRequest = request
        do {
            guard let restored = try await request.value, generation == sessionGeneration else { return }
            workspace = restored
            configureTransactions()
            selectedWeek = restored.week
            currentWeek = restored.week
            try restoreDrafts()
            unconfirmedBoardPost = try await repository.pendingBoardPost()
            guard generation == sessionGeneration else { return }
            // Reconnecting means verifying the account, not downloading every
            // optional tab. Show the app immediately once that check succeeds.
            isRestoringSession = false
            isBusy = false
            phase = .signedIn
            await refreshAll()
        } catch {
            guard generation == sessionGeneration else { return }
            notice = .error("Couldn’t restore your MFL session. Sign in to reconnect. Your saved drafts are kept for the same team. \(error.localizedDescription)")
        }
    }

    func cancelReconnect() {
        guard isRestoringSession else { return }
        restoreRequest?.cancel()
        restoreRequest = nil
        sessionGeneration &+= 1
        isRestoringSession = false
        isBusy = false
        notice = nil
        // Keep the saved cookie/drafts; this only dismisses the current attempt.
    }

    func continueInDemo() async {
        sessionGeneration &+= 1
        weekLoadGeneration &+= 1
        repository = DemoLeagueRepository()
        isDemo = true
        isBusy = true
        defer { isBusy = false }
        notice = nil
        drafts = LeagueDrafts()
        installDemoContent()
        phase = .signedIn
    }

    func signIn(credentials: LoginCredentials) async {
        sessionGeneration &+= 1
        weekLoadGeneration &+= 1
        let generation = sessionGeneration
        let activeRepository = repository

        isBusy = true
        var authenticating = true
        defer { if authenticating, generation == sessionGeneration { isBusy = false } }
        notice = nil
        workspace = nil
        selectedWeek = 1
        isDemo = false
        resetContent(for: selectedWeek)

        do {
            let authenticatedWorkspace = try await activeRepository.signIn(with: credentials)
            guard generation == sessionGeneration else { return }

            workspace = authenticatedWorkspace
            selectedWeek = authenticatedWorkspace.week
            currentWeek = authenticatedWorkspace.week
            followsCurrentWeek = true
            isDemo = activeRepository is DemoLeagueRepository
            resetContent(for: selectedWeek)
            configureTransactions()
            try restoreDrafts()
            unconfirmedBoardPost = try await activeRepository.pendingBoardPost()
            // Authentication is complete. Enter the app now; optional league
            // sections load independently and may legitimately be unavailable
            // during the preseason.
            phase = .signedIn
            authenticating = false
            isBusy = false
            await refreshAll()
            guard generation == sessionGeneration else { return }
        } catch {
            guard generation == sessionGeneration else { return }
            notice = .error(error.localizedDescription)
        }
    }

    func refreshAll(showSpinner: Bool = true) async {
        let generation = sessionGeneration
        guard !fullRefreshInFlight || fullRefreshSession != generation,
              !isBusy || lineup.players.isEmpty || isRestoringSession else { return }
        fullRefreshInFlight = true
        fullRefreshSession = generation
        defer { if fullRefreshSession == generation { fullRefreshInFlight = false; lastFullRefresh = Date() } }
        let refreshID = showSpinner ? beginRefreshing() : nil
        defer {
            if let refreshID { endRefreshing(refreshID) }
        }

        let activeRepository = repository
        let requestedWeek = selectedWeek
        let requestedWeekGeneration = weekLoadGeneration

        isLoadingScores = true
        isLoadingLineup = true
        isLoadingWaivers = true
        isLoadingBoard = true
        defer {
            if generation == sessionGeneration {
                if weekLoadGeneration == requestedWeekGeneration {
                    isLoadingScores = false; isLoadingLineup = false
                }
                isLoadingWaivers = false; isLoadingBoard = false
            }
        }
        var failures: [String] = []
        await withTaskGroup(of: RefreshedSection.self) { group in
            group.addTask { .scores(await Self.capture { try await activeRepository.refreshScores(week: requestedWeek) }) }
            group.addTask { .lineup(await Self.capture { try await activeRepository.loadLineup(week: requestedWeek) }) }
            group.addTask { .waivers(await Self.capture { try await activeRepository.loadWaivers() }) }
            group.addTask { .standings(await Self.capture { try await activeRepository.loadStandings() }) }
            group.addTask { .board(await Self.capture { try await activeRepository.loadBoard() }) }

            for await section in group {
                guard generation == sessionGeneration, !Task.isCancelled else { group.cancelAll(); continue }
                if let error = section.error { handleSessionError(error) }
                guard generation == sessionGeneration else { group.cancelAll(); continue }
                switch section {
                case .scores(let result):
                    guard selectedWeek == requestedWeek, weekLoadGeneration == requestedWeekGeneration else { continue }
                    isLoadingScores = false
                    if let value = result.value { scores = value; scoreRefreshError = nil }
                    else { scoreRefreshError = "Scores may be out of date. Pull to retry."; failures.append("scores") }
                case .lineup(let result):
                    guard selectedWeek == requestedWeek, weekLoadGeneration == requestedWeekGeneration else { continue }
                    if let value = result.value { mergeLineup(value); lineupRevision &+= 1 }
                    else { failures.append("lineup") }
                    isLoadingLineup = false
                case .waivers(let result):
                    if let value = result.value { mergeWaivers(value); waiverReadError = nil; lastWaiverRefresh = Date() }
                    else { failures.append("waivers"); waiverReadError = result.error?.localizedDescription }
                    isLoadingWaivers = false
                case .standings(let result):
                    if let value = result.value { standings = value }
                    else { failures.append("standings") }
                case .board(let result):
                    if let value = result.value { boardThreads = value }
                    else { failures.append("the message board") }
                    isLoadingBoard = false
                }
            }
        }

        if generation == sessionGeneration, !failures.isEmpty && !Task.isCancelled {
            notice = .error(refreshFailureMessage(for: failures))
        }
    }

    /// Pull-to-refresh affects the visible section, not every league feed.
    func refreshLineup() async {
        guard !isLoadingLineup, !isBusy else { return }
        let generation = sessionGeneration, requestedWeek = selectedWeek, revision = weekLoadGeneration
        isLoadingLineup = true
        defer { if generation == sessionGeneration, revision == weekLoadGeneration { isLoadingLineup = false } }
        do {
            let fresh = try await repository.loadLineup(week: requestedWeek)
            guard generation == sessionGeneration, revision == weekLoadGeneration, selectedWeek == requestedWeek else { return }
            mergeLineup(fresh); lineupRevision &+= 1
        } catch {
            guard generation == sessionGeneration, revision == weekLoadGeneration else { return }
            handleSessionError(error)
            notice = .error(error.localizedDescription)
        }
    }

    func refreshBoard() async {
        guard !isLoadingBoard, !isBusy else { return }
        let generation = sessionGeneration
        isLoadingBoard = true
        defer { if generation == sessionGeneration { isLoadingBoard = false } }
        do {
            let fresh = try await repository.loadBoard()
            guard generation == sessionGeneration else { return }
            boardThreads = fresh
        } catch {
            guard generation == sessionGeneration else { return }
            handleSessionError(error); notice = .error(error.localizedDescription)
        }
    }

    func refreshStandings() async {
        guard !isRefreshing, !isBusy else { return }
        let generation = sessionGeneration, refreshID = beginRefreshing()
        defer { endRefreshing(refreshID) }
        do {
            let fresh = try await repository.loadStandings()
            guard generation == sessionGeneration else { return }
            standings = fresh
        } catch {
            guard generation == sessionGeneration else { return }
            handleSessionError(error); notice = .error(error.localizedDescription)
        }
    }

    func refreshWaivers() async {
        guard !isLoadingWaivers, !isBusy else { return }
        if let lastWaiverRefresh, waiverReadError == nil, Date().timeIntervalSince(lastWaiverRefresh) < 15 { return }
        let generation = sessionGeneration
        isLoadingWaivers = true
        defer { if generation == sessionGeneration { isLoadingWaivers = false } }
        do {
            let fresh = try await repository.loadWaivers()
            guard generation == sessionGeneration else { return }
            mergeWaivers(fresh); waiverReadError = nil; lastWaiverRefresh = Date()
        } catch {
            guard generation == sessionGeneration else { return }
            handleSessionError(error)
            waiverReadError = "Waivers couldn’t refresh. Your existing data and draft are kept. \(error.localizedDescription)"
        }
    }

    func refreshScores(silent: Bool = false) async {
        guard !scoreRequestInFlight, !isLoadingScores, !isBusy else { return }
        scoreRequestInFlight = true
        defer { scoreRequestInFlight = false }
        let refreshID = beginRefreshing()
        defer { endRefreshing(refreshID) }

        let activeRepository = repository
        let generation = sessionGeneration
        let requestedWeek = selectedWeek
        let requestedWeekGeneration = weekLoadGeneration
        isLoadingScores = true
        defer {
            if generation == sessionGeneration, requestedWeekGeneration == weekLoadGeneration { isLoadingScores = false }
        }

        do {
            let refreshedScores = try await activeRepository.refreshScores(week: requestedWeek)
            guard generation == sessionGeneration, selectedWeek == requestedWeek, requestedWeekGeneration == weekLoadGeneration else { return }
            scores = refreshedScores
            scoreRefreshError = nil
        } catch {
            guard generation == sessionGeneration, selectedWeek == requestedWeek, requestedWeekGeneration == weekLoadGeneration else { return }
            handleSessionError(error)
            scoreRefreshError = "Scores may be out of date. Pull to retry."
            if !silent { notice = .error(error.localizedDescription) }
        }
    }

    func changeWeek(to week: Int, followingCurrent: Bool = false) async {
        guard !isBusy, (1...21).contains(week), week != selectedWeek else { return }
        followsCurrentWeek = followingCurrent
        selectedWeek = week
        lineup = emptyLineup(for: week)
        scores = emptyScores(for: week)
        lineupConflict = nil
        weekLoadGeneration &+= 1
        let requestGeneration = weekLoadGeneration
        let generation = sessionGeneration
        let activeRepository = repository
        let refreshID = beginRefreshing()
        isLoadingScores = true
        isLoadingLineup = true
        defer {
            endRefreshing(refreshID)
            if generation == sessionGeneration, requestGeneration == weekLoadGeneration {
                isLoadingScores = false; isLoadingLineup = false
            }
        }

        async let newScores: ScoresSnapshot? = try? await activeRepository.loadScores(week: week)
        async let newLineup: LineupSnapshot? = try? await activeRepository.loadLineup(week: week)
        let values = await (newScores, newLineup)

        guard generation == sessionGeneration,
              requestGeneration == weekLoadGeneration,
              selectedWeek == week else { return }

        var failures: [String] = []
        if let scores = values.0 {
            self.scores = scores
        } else {
            self.scores = emptyScores(for: week)
            failures.append("scores")
        }
        if let lineup = values.1 {
            mergeLineup(lineup)
        } else {
            self.lineup = emptyLineup(for: week)
            failures.append("lineup")
        }
        lineupRevision &+= 1

        if !failures.isEmpty {
            notice = .error("Couldn’t load Week \(week) \(failures.joined(separator: " and ")).")
        }
    }

    func toggleStarter(_ playerID: String) {
        guard canChangeLineupDraft,
              let index = lineup.players.firstIndex(where: { $0.id == playerID }),
              !lineup.players[index].isLocked,
              lineup.players[index].injuryStatus != .injuredReserve else { return }
        lineup.players[index].isStarter.toggle()
        if lineup.players[index].isStarter {
            lineup.tiebreakerPlayerIDs.removeAll(where: { $0 == playerID })
        }
        saveLineupDraft()
    }

    func replacementRequest(for starterID: String) -> LineupReplacementRequest? {
        guard let slot = lineup.startingSlots.first(where: { $0.id == starterID }) else { return nil }
        let request = LineupReplacementRequest(starter: slot.player, slotLabel: slot.label, week: lineup.week,
            sessionGeneration: sessionGeneration, assignments: lineup.startingAssignments,
            positionRequirements: lineup.positionRequirements, requiredStarterCount: lineup.requiredStarterCount)
        return replaceableStarter(for: request) == nil ? nil : request
    }

    func replacementCandidates(for request: LineupReplacementRequest) -> [LineupPlayer] {
        guard let starter = replaceableStarter(for: request) else { return [] }
        let positions = lineup.replacementPositions(for: starter.id)
        let playersByID = Dictionary(grouping: lineup.players, by: \.id)
        return sortReplacementPlayers(lineup.players.filter { player in
            guard player.id != starter.id, !player.isLocked, player.injuryStatus != .injuredReserve,
                  playersByID[player.id]?.count == 1 else { return false }
            if player.isStarter {
                return lineup.hasValidStarterPositions && lineup.isEligible(player, forSlot: request.slotLabel)
            }
            return positions.contains(player.position)
        })
    }

    private func sortReplacementPlayers(_ players: [LineupPlayer]) -> [LineupPlayer] {
        players.sorted { lhs, rhs in
            // Unpublished projections sort after every published value, even zero.
            if lhs.projectedPoints != rhs.projectedPoints {
                return (lhs.projectedPoints ?? -.infinity) > (rhs.projectedPoints ?? -.infinity)
            }
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    func replacementNeedsFollowUp(for request: LineupReplacementRequest, with playerID: String) -> Bool {
        guard let starter = replaceableStarter(for: request),
              let source = lineup.startingSlots.first(where: { $0.id == playerID }) else { return false }
        return !lineup.isEligible(starter, forSlot: source.label)
    }

    func replacementFollowUpCandidates(for request: LineupReplacementRequest, with playerID: String) -> [LineupPlayer] {
        guard replacementCandidates(for: request).contains(where: { $0.id == playerID }),
              replacementNeedsFollowUp(for: request, with: playerID),
              let source = lineup.startingSlots.first(where: { $0.id == playerID }) else { return [] }
        let counts = Dictionary(grouping: lineup.players, by: \.id)
        return sortReplacementPlayers(lineup.players.filter { player in
            guard !player.isLocked, player.injuryStatus != .injuredReserve, counts[player.id]?.count == 1,
                  player.id != request.starter.id, player.id != playerID,
                  lineup.isEligible(player, forSlot: source.label) else { return false }
            if player.isStarter {
                // A third starter in FLEX can fill the fixed slot while the
                // original outgoing player rotates into their FLEX slot.
                return lineup.startingSlots.contains { $0.id == player.id && $0.isFlex }
                    && lineup.isEligible(request.starter, forSlot: "FLEX")
            }
            var proposed = lineup
            for index in proposed.players.indices {
                if proposed.players[index].id == request.starter.id { proposed.players[index].isStarter = false }
                if proposed.players[index].id == player.id { proposed.players[index].isStarter = true }
            }
            return proposed.hasValidStarterPositions
        })
    }

    func replacementPositions(for request: LineupReplacementRequest) -> [String] {
        guard replaceableStarter(for: request) != nil else { return [] }
        return lineup.replacementPositions(for: request.starter.id)
    }

    @discardableResult
    func replaceStarter(_ request: LineupReplacementRequest, with replacementID: String,
                        fillingVacatedSlotWith fillID: String? = nil) -> Bool {
        // Revalidate at selection time: a refresh, kickoff, week switch, or
        // account change may have happened while the picker was open.
        guard replacementCandidates(for: request).contains(where: { $0.id == replacementID }),
              let outgoing = lineup.players.firstIndex(where: { $0.id == request.starter.id }),
              let incoming = lineup.players.firstIndex(where: { $0.id == replacementID }) else { return false }
        var updated = lineup
        var assignments = lineup.startingAssignments
        guard let target = assignments.firstIndex(where: { $0.playerID == request.starter.id }) else { return false }
        if updated.players[incoming].isStarter {
            guard let source = assignments.firstIndex(where: { $0.playerID == replacementID }) else { return false }
            if replacementNeedsFollowUp(for: request, with: replacementID) {
                // A cross-position move is staged in the picker, then applied
                // atomically only after the user fills the vacated fixed slot.
                guard let fillID,
                      replacementFollowUpCandidates(for: request, with: replacementID).contains(where: { $0.id == fillID }),
                      let fill = updated.players.firstIndex(where: { $0.id == fillID }) else { return false }
                if updated.players[fill].isStarter {
                    guard let third = assignments.firstIndex(where: { $0.playerID == fillID }) else { return false }
                    assignments[third].playerID = request.starter.id
                } else {
                    updated.players[outgoing].isStarter = false
                    updated.players[fill].isStarter = true
                    updated.tiebreakerPlayerIDs.removeAll { $0 == fillID }
                }
                assignments[source].playerID = fillID
            } else {
                guard fillID == nil else { return false }
                assignments[source].playerID = request.starter.id
            }
        } else {
            guard fillID == nil else { return false }
            updated.players[outgoing].isStarter = false
            updated.players[incoming].isStarter = true
            updated.tiebreakerPlayerIDs.removeAll { $0 == replacementID }
        }
        assignments[target].playerID = replacementID
        updated.preferredStartingAssignments = assignments
        lineup = updated
        saveLineupDraft()
        lineupRevision &+= 1
        return true
    }

    private func replaceableStarter(for request: LineupReplacementRequest) -> LineupPlayer? {
        guard canChangeLineupDraft, request.sessionGeneration == sessionGeneration,
              request.week == lineup.week,
              request.assignments == lineup.startingAssignments,
              request.positionRequirements == lineup.positionRequirements,
              request.requiredStarterCount == lineup.requiredStarterCount,
              lineup.startingSlots.first(where: { $0.id == request.starter.id })?.label == request.slotLabel else { return nil }
        let matches = lineup.players.filter { $0.id == request.starter.id }
        guard matches.count == 1, let starter = matches.first,
              starter.isStarter, !starter.isLocked, starter.injuryStatus != .injuredReserve,
              starter.position == request.starter.position,
              !starter.position.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              starter.position != "—" else { return nil }
        return starter
    }

    func setTiebreaker(_ playerID: String) {
        guard canChangeLineupDraft else { return }
        guard !playerID.isEmpty else {
            lineup.tiebreakerPlayerIDs = []
            saveLineupDraft()
            return
        }
        guard let player = lineup.players.first(where: { $0.id == playerID }),
              !player.isStarter,
              !player.isLocked,
              player.injuryStatus != .injuredReserve
        else { return }
        lineup.tiebreakerPlayerIDs = [playerID]
        saveLineupDraft()
    }

    var lineupValidationMessage: String? {
        if let starterValidationMessage { return starterValidationMessage }
        if lineup.tiebreakerPlayerIDs.count != lineup.requiredTiebreakerCount {
            return lineup.requiredTiebreakerCount == 1
                ? "Choose one bench tiebreaker before submitting changes"
                : "Choose \(lineup.requiredTiebreakerCount) bench tiebreakers before submitting changes"
        }
        return nil
    }

    var starterValidationMessage: String? {
        let count = lineup.starters.count
        if count != lineup.requiredStarterCount {
            let difference = lineup.requiredStarterCount - count
            return difference > 0
                ? "Choose \(difference) more starter\(difference == 1 ? "" : "s")"
                : "Move \(-difference) player\((-difference) == 1 ? "" : "s") to the bench"
        }

        for requirement in lineup.positionRequirements {
            let positionCount = lineup.starters.count(where: { $0.position == requirement.position })
            if positionCount < requirement.minimum {
                return "Start at least \(requirement.minimum) \(requirement.position)"
            }
            if positionCount > requirement.maximum {
                return "Start no more than \(requirement.maximum) \(requirement.position)"
            }
        }
        return nil
    }

    @discardableResult
    func submitLineup(reviewing reviewed: LineupSnapshot? = nil) async -> LineupSubmissionReceipt? {
        if let reviewed, !lineupMatchesReview(reviewed) {
            notice = .error("The lineup changed after you opened review. Review the updated starters before submitting.")
            return nil
        }
        guard canSubmitLineup else {
            notice = .error(
                lineup.editState.unavailableMessage
                    ?? "Live lineup submission is unavailable for this week."
            )
            return nil
        }
        if let validationMessage = lineupValidationMessage {
            notice = .error(validationMessage)
            return nil
        }

        let submittedLineup = lineup
        let activeRepository = repository
        let generation = sessionGeneration
        isBusy = true
        defer { isBusy = false }

        do {
            try await activeRepository.submitLineup(submittedLineup)
            guard generation == sessionGeneration else { return nil }

            if lineup.week == submittedLineup.week {
                lineup.lastSubmitted = Date()
                lineup.serverStarterPlayerIDs = Set(submittedLineup.starters.map(\.id))
                drafts.lineups[submittedLineup.week] = LineupDraft(
                    baseline: lineup.serverStarterPlayerIDs, starters: lineup.serverStarterPlayerIDs,
                    tiebreakers: submittedLineup.tiebreakerPlayerIDs,
                    submittedTiebreakers: submittedLineup.tiebreakerPlayerIDs,
                    startingAssignments: lineup.preferredStartingAssignments)
                persistDrafts()
            }
            if isDemo {
                notice = .success("Demo lineup saved on this device.")
            } else if submittedLineup.requiredTiebreakerCount > 0 {
                notice = .success(
                    "Week \(submittedLineup.week) starters confirmed by MFL. Your tiebreaker was sent, but MFL does not expose it for confirmation."
                )
            } else {
                notice = .success("Week \(submittedLineup.week) lineup confirmed by MFL.")
            }
            return LineupSubmissionReceipt(
                week: submittedLineup.week,
                starterIDs: Set(submittedLineup.starters.map(\.id)),
                tiebreakerPlayerIDs: submittedLineup.tiebreakerPlayerIDs
            )
        } catch {
            guard generation == sessionGeneration else { return nil }
            notice = .error(error.localizedDescription)
            handleSessionError(error)
            return nil
        }
    }

    func lineupMatchesReview(_ reviewed: LineupSnapshot) -> Bool {
        reviewed.week == lineup.week && reviewed.requiredStarterCount == lineup.requiredStarterCount
            && reviewed.requiredTiebreakerCount == lineup.requiredTiebreakerCount
            && reviewed.positionRequirements == lineup.positionRequirements
            && Set(reviewed.starters.map(\.id)) == Set(lineup.starters.map(\.id))
            && reviewed.startingAssignments == lineup.startingAssignments
            && reviewed.tiebreakerPlayerIDs == lineup.tiebreakerPlayerIDs
    }

    func upsertClaim(_ claim: WaiverClaim) {
        guard !isBusy else { return }
        var updatedClaim = claim
        if let index = waivers.claims.firstIndex(where: { $0.id == claim.id }) {
            let previousRound = waivers.claims[index].round
            if previousRound != updatedClaim.round {
                updatedClaim.priority = waivers.claims.count(where: {
                    $0.round == updatedClaim.round && $0.id != updatedClaim.id
                }) + 1
            }
            waivers.claims[index] = updatedClaim
        } else {
            updatedClaim.priority = waivers.claims.count(where: { $0.round == updatedClaim.round }) + 1
            waivers.claims.append(updatedClaim)
        }
        normalizeClaimPriorities()
        saveWaiverDraft()
    }

    func removeClaims(inRound round: Int, at offsets: IndexSet) {
        guard !isBusy else { return }
        let orderedIDs = waivers.claims
            .filter { $0.round == round }
            .sorted(using: KeyPathComparator(\.priority))
            .map(\.id)
        let removedIDs = Set(offsets.compactMap { orderedIDs.indices.contains($0) ? orderedIDs[$0] : nil })
        waivers.claims.removeAll(where: { removedIDs.contains($0.id) })
        normalizeClaimPriorities()
        saveWaiverDraft()
    }

    func moveClaims(inRound round: Int, from offsets: IndexSet, to destination: Int) {
        guard !isBusy else { return }
        var ordered = waivers.claims
            .filter { $0.round == round }
            .sorted(using: KeyPathComparator(\.priority))
        ordered.move(fromOffsets: offsets, toOffset: destination)
        let priorityByID = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset + 1) }
        )
        for index in waivers.claims.indices where waivers.claims[index].round == round {
            waivers.claims[index].priority = priorityByID[waivers.claims[index].id] ?? waivers.claims[index].priority
        }
        normalizeClaimPriorities()
        saveWaiverDraft()
    }

    @discardableResult
    func submitWaivers() async -> Bool {
        guard canSubmitWaivers else {
            notice = .error(waiverConflict ?? waivers.unavailableReason ?? "Wait for the current request to finish.")
            return false
        }
        guard hasWaiverChanges else { return false }
        guard waivers.maxRounds > 0,
              waivers.claims.allSatisfy({ (1 ... waivers.maxRounds).contains($0.round) }) else {
            notice = .error("Every bid must belong to one of this league’s configured waiver rounds.")
            return false
        }
        guard waivers.claims.allSatisfy({ $0.bid <= waivers.availableBudget && $0.bid >= waivers.minimumBid }) else {
            notice = .error("Every bid must fit inside your available FAAB budget.")
            return false
        }
        guard waivers.claims.allSatisfy({ $0.bid.isWholeMultiple(of: waivers.increment) }) else {
            notice = .error("Every bid must use the league’s configured FAAB increment.")
            return false
        }
        let hasDuplicateInRound = Dictionary(grouping: waivers.claims, by: \.round).values.contains { claims in
            Set(claims.map(\.player.id)).count != claims.count
        }
        guard !hasDuplicateInRound else {
            notice = .error("A player can appear only once within the same conditional round.")
            return false
        }

        let submittedClaims = waivers.claims.sorted {
            ($0.round, $0.priority) < ($1.round, $1.priority)
        }
        let activeRepository = repository
        let generation = sessionGeneration
        isBusy = true
        defer { isBusy = false }
        do {
            try await activeRepository.submitWaivers(submittedClaims, replacing: drafts.waiverBaseline)
            guard generation == sessionGeneration else { return false }
            serverWaivers = submittedClaims
            drafts.waiverClaims = nil
            drafts.waiverBaseline = submittedClaims
            persistDrafts()
            notice = .success(isDemo ? "Demo waiver queue saved." : "MFL confirmed every saved waiver round, including cancellations.")
            return true
        } catch {
            guard generation == sessionGeneration else { return false }
            // A round may have saved before the connection failed. Preserve the
            // desired queue, fetch reality, and require an explicit comparison.
            if !isDemo {
                if let refreshed = try? await activeRepository.loadWaivers(), generation == sessionGeneration {
                    mergeWaivers(refreshed)
                } else { waiverServerReadFailed = true }
                waiverConflict = "The save stopped. Some rounds may already be on MFL. Compare the saved queue below before continuing."
            }
            handleSessionError(error)
            notice = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func post(subject: String?, body: String, threadID: String? = nil) async -> Bool {
        guard canPostToBoard, !isBusy, !isLoadingBoard, unconfirmedBoardPost == nil else {
            notice = .error("Resolve the previous unconfirmed post before sending another message.")
            return false
        }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return false }

        let trimmedSubject = subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        if threadID == nil, trimmedSubject?.isEmpty != false {
            notice = .error("Add a subject before posting a new thread.")
            return false
        }

        let activeRepository = repository
        let generation = sessionGeneration
        isBusy = true
        defer { isBusy = false }

        do {
            try await activeRepository.postMessage(subject: trimmedSubject, body: trimmedBody, threadID: threadID)
            guard generation == sessionGeneration else { return false }
            drafts.board.removeValue(forKey: threadID ?? "new")
            persistDrafts()
            boardDraftRevision &+= 1

            var refreshedAfterPost = true
            if isDemo {
                applyDemoPost(subject: trimmedSubject, body: trimmedBody, threadID: threadID)
            } else if let threadID {
                do {
                    let loadedThread = try await activeRepository.loadThread(id: threadID)
                    guard generation == sessionGeneration else { return false }
                    if let index = boardThreads.firstIndex(where: { $0.id == threadID }) {
                        boardThreads[index] = loadedThread
                    }
                } catch {
                    refreshedAfterPost = false
                }
            } else {
                do {
                    let refreshedBoard = try await activeRepository.loadBoard()
                    guard generation == sessionGeneration else { return false }
                    boardThreads = refreshedBoard
                } catch {
                    refreshedAfterPost = false
                }
            }

            if isDemo {
                notice = .success("Demo message posted locally.")
            } else if refreshedAfterPost {
                notice = .success("Posted to the MFL message board.")
            } else {
                notice = .success("Posted to MFL. Pull to refresh the message board to see the latest copy.")
            }
            return true
        } catch {
            guard generation == sessionGeneration else { return false }
            unconfirmedBoardPost = try? await activeRepository.pendingBoardPost()
            handleSessionError(error)
            notice = .error(error.localizedDescription)
            return false
        }
    }

    func loadThread(id: String) async {
        if isDemo, id.hasPrefix("demo-local-thread-") { return }

        let generation = sessionGeneration
        do {
            let loaded = try await repository.loadThread(id: id)
            guard generation == sessionGeneration else { return }
            if let index = boardThreads.firstIndex(where: { $0.id == id }) {
                boardThreads[index] = loaded
            }
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func signOut() async {
        guard !isBusy, !transactions.isBusy, !playerTools.isChangingWatchList else { return }
        if !isDemo, let workspace {
            do {
                try privateStore.remove("drafts.\(workspace.storageScope)")
                try privateStore.remove("board.pending.\(workspace.storageScope)")
                try privateStore.remove("trade.draft.\(workspace.storageScope)")
                try privateStore.remove("trade.pending.\(workspace.storageScope)")
                try privateStore.remove("roster.pending.\(workspace.storageScope)")
                try privateStore.remove("watch-action.\(workspace.storageScope)")
                try privateStore.remove("session")
            } catch { notice = .error(error.localizedDescription); return }
        }
        let signedInRepository = repository
        sessionGeneration &+= 1
        weekLoadGeneration &+= 1
        workspace = nil
        isDemo = false
        selectedWeek = 1
        notice = nil
        activeRefreshIDs.removeAll()
        isRefreshing = false
        nextDemoMessageID = 0
        drafts = LeagueDrafts()
        unconfirmedBoardPost = nil
        resetContent(for: selectedWeek)
        repository = LiveMFLRepository(playerCacheDirectory: AppCacheLocations.players)
        phase = .onboarding
        await signedInRepository.signOut()
    }

    private func normalizeClaimPriorities() {
        waivers.claims.sort {
            ($0.round, $0.priority) < ($1.round, $1.priority)
        }
        for round in Set(waivers.claims.map(\.round)) {
            let indices = waivers.claims.indices.filter { waivers.claims[$0].round == round }
            for (offset, index) in indices.enumerated() {
                waivers.claims[index].priority = offset + 1
            }
        }
    }

    private func emptyScores(for week: Int) -> ScoresSnapshot {
        ScoresSnapshot(week: week, matchups: [], lastUpdated: .distantPast, isLive: false)
    }

    private func emptyLineup(for week: Int) -> LineupSnapshot {
        LineupSnapshot(
            week: week,
            players: [],
            requiredStarterCount: 0,
            positionRequirements: [],
            requiredTiebreakerCount: 0,
            tiebreakerPlayerIDs: [],
            deadline: nil,
            lastSubmitted: nil
        )
    }

    private func resetContent(for week: Int) {
        pendingRosterChange = nil; rosterChangeError = nil; rosterRevision += 1
        playerTools.reset(scope: workspace?.storageScope)
        transactions = TransactionsModel()
        seasonSchedule.invalidateSession()
        seasonSchedule = SeasonScheduleModel()
        scopedScoreInspection = nil
        waiverReadError = nil; lastWaiverRefresh = nil; lastFullRefresh = nil
        isLoadingScores = false; isLoadingLineup = false
        isLoadingWaivers = false; isLoadingBoard = false
        lineupConflict = nil
        waiverConflict = nil
        serverWaivers = []
        latestServerLineup = nil
        scores = emptyScores(for: week)
        lineup = emptyLineup(for: week)
        waivers = WaiverSnapshot(
            availableBudget: 0,
            increment: 1,
            maxRounds: 0,
            candidates: [],
            claims: [],
            processesAt: nil
        )
        standings = []
        teams = []
        boardThreads = []
        lineupRevision &+= 1
    }

    private func installDemoContent() {
        isDemo = true
        workspace = SampleData.workspace
        teams = []
        configureTransactions()
        selectedWeek = SampleData.workspace.week
        scores = SampleData.scores
        lineup = SampleData.lineup
        lineup.serverStarterPlayerIDs = Set(lineup.starters.map(\.id))
        drafts.lineups[lineup.week] = LineupDraft(baseline: lineup.serverStarterPlayerIDs,
            starters: lineup.serverStarterPlayerIDs, tiebreakers: lineup.tiebreakerPlayerIDs,
            submittedTiebreakers: lineup.tiebreakerPlayerIDs)
        waivers = SampleData.waivers
        drafts.waiverBaseline = waivers.claims
        standings = SampleData.standings
        boardThreads = SampleData.board
        nextDemoMessageID = 0
        lineupRevision &+= 1
    }

    private func configureTransactions() {
        pendingRosterChange = nil; rosterChangeError = nil
        rosterRevision += 1
        playerTools.reset(scope: workspace?.storageScope)
        scopedScoreInspection = nil
        transactions = TransactionsModel(repository: repository, workspace: workspace, privateStore: privateStore, isDemo: isDemo)
        seasonSchedule.invalidateSession()
        seasonSchedule = SeasonScheduleModel(loader: { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.loadSeasonSchedule()
        })
    }

    var browseScope: LeagueBrowseScope? { workspace.map(LeagueBrowseScope.init(workspace:)) }

    // Destination-local reads must never change selectedWeek, scores or a draft.
    // Reject both successful and failed replies from a replaced account/session.
    private func readForBrowsing<Value: Sendable>(
        _ operation: @Sendable (any LeagueRepository) async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard let scope = browseScope else { throw RepositoryError.missingSession }
        let generation = sessionGeneration
        let activeRepository = repository
        do {
            let value = try await operation(activeRepository)
            try Task.checkCancellation()
            guard generation == sessionGeneration, browseScope == scope else { throw CancellationError() }
            return value
        } catch {
            guard generation == sessionGeneration, browseScope == scope, !Task.isCancelled else {
                throw CancellationError()
            }
            throw error
        }
    }

    func loadTeams(refresh: Bool = false) async throws -> [TeamSummary] {
        let generation = sessionGeneration
        let result = try await readForBrowsing { try await $0.loadTeams(refresh: refresh) }
        guard generation == sessionGeneration, !Task.isCancelled else { throw CancellationError() }
        teams = result
        return result
    }

    func loadTeamRoster(franchiseID: String, lineupWeek: Int? = nil, refresh: Bool = false) async throws -> TeamRosterSnapshot {
        try await readForBrowsing {
            try await $0.loadTeamRoster(franchiseID: franchiseID, lineupWeek: lineupWeek, refresh: refresh)
        }
    }

    func loadPlayerDetail(playerID: String, refresh: Bool = false) async throws -> PlayerDetailSnapshot {
        try await readForBrowsing { try await $0.loadPlayerDetail(playerID: playerID, refresh: refresh) }
    }

    func loadPlayerAvailability(week: Int, refresh: Bool = false) async {
        await playerTools.loadAvailability(week: week, refresh: refresh) {
            try await self.readForBrowsing { try await $0.loadPlayerAvailability(week: week, refresh: refresh) }
        }
    }

    func loadPlayerResearch(playerID: String, beforeWeek: Int?, contextWeek: Int) async throws -> PlayerResearchPage {
        try await readForBrowsing {
            try await $0.loadPlayerResearch(playerID: playerID, beforeWeek: beforeWeek, contextWeek: contextWeek)
        }
    }

    func loadWatchList(refresh: Bool = false) async {
        await playerTools.loadWatchList(refresh: refresh) {
            try await self.readForBrowsing { repository in
                let snapshot = try await repository.loadWatchList(refresh: refresh)
                return snapshot.pending == nil ? snapshot : try await repository.reconcileWatchList()
            }
        }
    }

    func setWatched(playerID: String, isWatched: Bool) async {
        await playerTools.changeWatchList(playerID: playerID, isWatched: isWatched) {
            try await self.readForBrowsing { try await $0.setWatched(playerID: playerID, isWatched: isWatched) }
        }
    }

    func acknowledgeWatchList() async {
        do {
            try await readForBrowsing { try await $0.acknowledgeWatchList() }
            await loadWatchList(refresh: true)
        } catch { notice = .error(error.localizedDescription) }
    }

    func loadSeasonSchedule() async throws -> SeasonScheduleSnapshot {
        try await readForBrowsing { try await $0.loadSeasonSchedule() }
    }

    func loadRosterActionContext() async throws -> RosterActionContext {
        try await readForBrowsing { try await $0.loadRosterActionContext() }
    }

    func loadPendingRosterChange() async {
        do {
            pendingRosterChange = try await readForBrowsing { try await $0.pendingRosterAction() }
            rosterChangeError = nil
        } catch {
            if !(error is CancellationError) { rosterChangeError = "Couldn’t check pending roster changes. Pull to retry." }
        }
    }

    func performRosterAction(_ request: RosterActionRequest, reviewed: RosterActionContext) async throws -> RosterActionReceipt {
        guard !isBusy, !transactions.isBusy else { throw RepositoryError.server("Wait for the current change to finish.") }
        isBusy = true
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { isBusy = false } }
        do {
            let receipt = try await readForBrowsing { try await $0.performRosterAction(request, reviewed: reviewed) }
            await loadPendingRosterChange()
            guard generation == sessionGeneration else { throw CancellationError() }
            if receipt.confirmed {
                isBusy = false
                await rosterDidChange()
            }
            return receipt
        } catch {
            if generation == sessionGeneration { await loadPendingRosterChange() }
            throw error
        }
    }

    func checkRosterChange() async {
        guard !isBusy, !transactions.isBusy else { return }
        isBusy = true
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { isBusy = false } }
        do {
            let receipt = try await readForBrowsing { try await $0.reconcileRosterAction() }
            rosterChangeError = receipt.confirmed ? nil : receipt.message
            pendingRosterChange = try await readForBrowsing { try await $0.pendingRosterAction() }
            if receipt.confirmed { isBusy = false; await rosterDidChange() }
        } catch {
            if generation == sessionGeneration { rosterChangeError = "Couldn’t confirm the move. Check your roster on MFL." }
        }
    }

    func acknowledgeRosterChange() async {
        guard !isBusy else { return }
        do {
            try await readForBrowsing { try await $0.acknowledgeRosterAction() }
            pendingRosterChange = nil; rosterChangeError = nil
            await rosterDidChange()
        } catch { if !(error is CancellationError) { rosterChangeError = error.localizedDescription } }
    }

    private func rosterDidChange() async {
        rosterRevision += 1
        // Existing mergers preserve unsent lineup/waiver drafts and surface
        // conflicts. Trades refresh assets without deleting a saved draft.
        await refreshAll(showSpinner: false)
        await transactions.refresh()
        await transactions.refreshActivity()
        await loadWatchList(refresh: true)
    }

    func loadMatchupScores(week: Int, refresh: Bool = false) async throws -> ScoresSnapshot {
        try await readForBrowsing {
            if refresh { return try await $0.refreshScores(week: week) }
            return try await $0.loadScores(week: week)
        }
    }

    private func beginRefreshing() -> Int {
        nextRefreshID &+= 1
        activeRefreshIDs.insert(nextRefreshID)
        isRefreshing = true
        return nextRefreshID
    }

    private func endRefreshing(_ id: Int) {
        activeRefreshIDs.remove(id)
        isRefreshing = !activeRefreshIDs.isEmpty
    }

    private func refreshFailureMessage(for sections: [String]) -> String {
        if sections.count == 5 {
            return "Couldn’t refresh league data. Pull to refresh and try again."
        }
        return "Couldn’t refresh \(sections.joined(separator: ", ")). Other sections are up to date."
    }

    private func applyDemoPost(subject: String?, body: String, threadID: String?) {
        nextDemoMessageID &+= 1
        let messageID = nextDemoMessageID
        let author = workspace?.franchiseName ?? "You"
        let postedAt = Date()

        if let threadID, let index = boardThreads.firstIndex(where: { $0.id == threadID }) {
            boardThreads[index].posts.append(
                BoardPost(
                    id: "demo-local-post-\(messageID)",
                    author: author,
                    body: body,
                    postedAt: postedAt,
                    isUser: true
                )
            )
            boardThreads[index].replyCount += 1
            boardThreads[index].preview = body
            boardThreads[index].lastActivity = postedAt
            return
        }

        boardThreads.insert(
            BoardThread(
                id: "demo-local-thread-\(messageID)",
                subject: subject ?? "New thread",
                author: author,
                preview: body,
                lastActivity: postedAt,
                replyCount: 0,
                isUnread: false,
                posts: [
                    BoardPost(
                        id: "demo-local-post-\(messageID)",
                        author: author,
                        body: body,
                        postedAt: postedAt,
                        isUser: true
                    )
                ]
            ),
            at: 0
        )
    }
}

extension AppModel {
    private enum RefreshedSection: Sendable {
        case scores(ReadResult<ScoresSnapshot>)
        case lineup(ReadResult<LineupSnapshot>)
        case waivers(ReadResult<WaiverSnapshot>)
        case standings(ReadResult<[StandingRow]>)
        case board(ReadResult<[BoardThread]>)

        var error: (any Error)? {
            switch self {
            case .scores(let value): value.error
            case .lineup(let value): value.error
            case .waivers(let value): value.error
            case .standings(let value): value.error
            case .board(let value): value.error
            }
        }
    }
    private struct ReadResult<Value: Sendable>: Sendable {
        var value: Value?
        var error: (any Error)?
    }

    private nonisolated static func capture<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async -> ReadResult<Value> {
        do { return ReadResult(value: try await operation()) }
        catch { return ReadResult(error: error) }
    }
    var hasLineupChanges: Bool {
        guard let draft = drafts.lineups[lineup.week] else { return false }
        return draft.starters != draft.baseline || draft.tiebreakers != draft.submittedTiebreakers
    }

    static func sameWaivers(_ lhs: [WaiverClaim], _ rhs: [WaiverClaim]) -> Bool {
        func signature(_ claims: [WaiverClaim]) -> [String] {
            claims.sorted { ($0.round, $0.priority) < ($1.round, $1.priority) }.map {
                "\($0.round)|\($0.priority)|\($0.player.id)|\($0.dropPlayerID ?? "0000")|\($0.bid)"
            }
        }
        return signature(lhs) == signature(rhs)
    }

    var hasWaiverChanges: Bool { !Self.sameWaivers(waivers.claims, drafts.waiverBaseline) }
    var savedWaiverClaims: [WaiverClaim] { serverWaivers }

    private func restoreDrafts() throws {
        drafts = LeagueDrafts()
        guard !isDemo, let workspace else { return }
        drafts = try privateStore.decode(LeagueDrafts.self, key: "drafts.\(workspace.storageScope)") ?? LeagueDrafts()
    }

    private func persistDrafts() {
        guard !isDemo, let workspace else { return }
        do { try privateStore.encode(drafts, key: "drafts.\(workspace.storageScope)") }
        catch { notice = .error(error.localizedDescription) }
    }

    private func saveLineupDraft() {
        var draft = drafts.lineups[lineup.week] ?? LineupDraft(
            baseline: lineup.serverStarterPlayerIDs, starters: [], tiebreakers: [])
        draft.starters = Set(lineup.starters.map(\.id))
        draft.tiebreakers = lineup.tiebreakerPlayerIDs
        draft.startingAssignments = lineup.preferredStartingAssignments
        drafts.lineups[lineup.week] = draft
        persistDrafts()
    }

    private func saveWaiverDraft() {
        drafts.waiverClaims = waivers.claims
        persistDrafts()
    }

    private func mergeLineup(_ fresh: LineupSnapshot) {
        // A lineup refresh owns isLoadingLineup until this merge completes, so
        // its submit button cannot race this read. Other tabs may already be usable.
        latestServerLineup = fresh
        lineup = fresh
        lineupConflict = nil
        let saved = drafts.lineups[fresh.week]
        let dirty = saved.map { $0.starters != $0.baseline || $0.tiebreakers != $0.submittedTiebreakers } ?? false
        guard let saved, dirty else {
            let retained = saved?.tiebreakers.filter { id in fresh.bench.contains { $0.id == id } } ?? []
            lineup.tiebreakerPlayerIDs = retained
            if saved?.starters == Set(fresh.starters.map(\.id)) {
                lineup.preferredStartingAssignments = saved?.startingAssignments
            }
            drafts.lineups[fresh.week] = LineupDraft(baseline: fresh.serverStarterPlayerIDs,
                starters: Set(fresh.starters.map(\.id)), tiebreakers: retained,
                submittedTiebreakers: retained, startingAssignments: lineup.preferredStartingAssignments)
            persistDrafts()
            return
        }
        let rosterIDs = Set(fresh.players.map(\.id))
        if fresh.serverStarterPlayerIDs != saved.baseline || !saved.starters.isSubset(of: rosterIDs) {
            lineupConflict = "Your MFL lineup or roster changed. Your draft is kept, but review the current MFL lineup before starting a new edit."
        }
        for index in lineup.players.indices {
            let desired = saved.starters.contains(lineup.players[index].id)
            if lineup.players[index].isLocked && desired != lineup.players[index].isStarter {
                lineupConflict = "A player in your draft is now locked. Load the current MFL lineup before making more changes."
            } else { lineup.players[index].isStarter = desired }
        }
        lineup.tiebreakerPlayerIDs = saved.tiebreakers
        lineup.preferredStartingAssignments = saved.startingAssignments
    }

    func discardLineupDraft() {
        guard !isBusy, let fresh = latestServerLineup else { return }
        drafts.lineups.removeValue(forKey: fresh.week)
        mergeLineup(fresh)
        lineupRevision &+= 1
        persistDrafts()
    }

    private func mergeWaivers(_ fresh: WaiverSnapshot) {
        waiverServerReadFailed = false
        serverWaivers = fresh.claims
        waivers = fresh
        if let desired = drafts.waiverClaims,
           !Self.sameWaivers(desired, drafts.waiverBaseline) {
            waivers.claims = desired
            if !Self.sameWaivers(fresh.claims, drafts.waiverBaseline) {
                waiverConflict = "MFL’s saved requests changed while you had a draft. Compare both queues before continuing."
            }
        } else {
            drafts.waiverBaseline = fresh.claims
            drafts.waiverClaims = nil
            waiverConflict = nil
        }
        persistDrafts()
    }

    /// Called only after the user reviews the server queue, never as an automatic retry.
    func resolveWaiverConflict(keepDraft: Bool) {
        guard !isBusy, !waiverServerReadFailed else { return }
        if !keepDraft { waivers.claims = serverWaivers; drafts.waiverClaims = nil }
        drafts.waiverBaseline = serverWaivers
        waiverConflict = nil
        persistDrafts()
    }

    func boardDraft(threadID: String?) -> BoardDraft { drafts.board[threadID ?? "new"] ?? BoardDraft() }

    var savedBoardDrafts: [SavedBoardDraft] {
        drafts.board.filter { $0.value.hasContent }
            .map { SavedBoardDraft(id: $0.key, draft: $0.value) }
            .sorted { left, right in
                if (left.threadID == nil) != (right.threadID == nil) { return left.threadID == nil }
                return left.id < right.id
            }
    }

    @discardableResult
    func saveBoardDraft(subject: String, body: String, threadID: String?) -> Bool {
        let draft = BoardDraft(subject: subject, body: body)
        return updateBoardDraft(draft.hasContent ? draft : nil, threadID: threadID)
    }

    @discardableResult
    func discardBoardDraft(threadID: String?) -> Bool {
        updateBoardDraft(nil, threadID: threadID)
    }

    private func updateBoardDraft(_ draft: BoardDraft?, threadID: String?) -> Bool {
        let key = threadID ?? "new"
        if draft == nil, drafts.board[key] == nil { return true }
        var updated = drafts
        updated.board[key] = draft
        do {
            if !isDemo {
                guard let workspace else { return false }
                try privateStore.encode(updated, key: "drafts.\(workspace.storageScope)")
            }
            drafts = updated
            return true
        } catch {
            notice = .error(error.localizedDescription)
            return false
        }
    }

    func checkUnconfirmedPost() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let generation = sessionGeneration
        do {
            if try await repository.reconcileBoardPost(), generation == sessionGeneration {
                drafts.board.removeValue(forKey: unconfirmedBoardPost?.threadID ?? "new")
                unconfirmedBoardPost = nil
                persistDrafts()
                boardDraftRevision &+= 1
                if let refreshed = try? await repository.loadBoard(), generation == sessionGeneration {
                    boardThreads = refreshed
                }
                notice = .success("MFL confirmed your post. It was not sent again.")
            } else if generation == sessionGeneration {
                notice = .error("The post is not confirmed yet. Check the MFL board before allowing another send.")
            }
        } catch { if generation == sessionGeneration { notice = .error(error.localizedDescription) } }
    }

    func acknowledgeUnconfirmedPost() async {
        guard !isBusy else { return }
        do { try await repository.acknowledgeUnconfirmedPost(); unconfirmedBoardPost = nil }
        catch { notice = .error(error.localizedDescription) }
    }

    func refreshForForeground() async {
        guard phase == .signedIn, !isDemo, !isBusy else { return }
        if let lastFullRefresh, Date().timeIntervalSince(lastFullRefresh) < foregroundRefreshInterval { return }
        guard !fullRefreshInFlight || fullRefreshSession != sessionGeneration else { return }
        let generation = sessionGeneration
        do {
            let latest = try await repository.currentWeek()
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            if let refreshedWorkspace = try? await repository.loadWorkspace(), generation == sessionGeneration {
                workspace = refreshedWorkspace
            }
            guard generation == sessionGeneration else { return }
            currentWeek = latest
            if followsCurrentWeek && selectedWeek != latest {
                await changeWeek(to: latest, followingCurrent: true)
            }
        } catch {
            guard generation == sessionGeneration else { return }
            handleSessionError(error)
        }
        guard phase == .signedIn, !Task.isCancelled else { return }
        await refreshAll()
    }

    private func handleSessionError(_ error: any Error) {
        let expired: Bool
        if case MFLCoreError.unauthorized = error { expired = true }
        else if case RepositoryError.missingSession = error { expired = true }
        else { expired = false }
        guard expired else { return }
        persistDrafts()
        sessionGeneration &+= 1
        phase = .onboarding
        notice = .error("Your MFL session expired. Sign in again; your drafts are kept for this team.")
    }
}
