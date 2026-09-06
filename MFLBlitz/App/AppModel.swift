import Foundation
import Observation
import SwiftUI

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
    var boardThreads: [BoardThread] = []
    var selectedWeek = 1
    var isBusy = false
    var isRefreshing = false
    var isDemo = false
    var notice: AppNotice?
    var lineupRevision = 0

    var canSubmitChanges: Bool { isDemo || LiveWritePolicy.isEnabled }

    private var repository: any LeagueRepository
    private var sessionGeneration = 0
    private var weekLoadGeneration = 0
    private var nextRefreshID = 0
    private var activeRefreshIDs: Set<Int> = []
    private var nextDemoMessageID = 0

    init(repository: any LeagueRepository = LiveMFLRepository()) {
        self.repository = repository
        if repository is DemoLeagueRepository {
            installDemoContent()
        }
    }

    func continueInDemo() async {
        sessionGeneration &+= 1
        weekLoadGeneration &+= 1
        repository = DemoLeagueRepository()
        isDemo = true
        isBusy = true
        defer { isBusy = false }
        notice = nil
        installDemoContent()
        phase = .signedIn
    }

    func signIn(credentials: LoginCredentials) async {
        sessionGeneration &+= 1
        weekLoadGeneration &+= 1
        let generation = sessionGeneration
        let activeRepository = repository

        isBusy = true
        defer { isBusy = false }
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
            isDemo = activeRepository is DemoLeagueRepository
            resetContent(for: selectedWeek)
            await refreshAll(showSpinner: false)
            guard generation == sessionGeneration else { return }
            phase = .signedIn
        } catch {
            guard generation == sessionGeneration else { return }
            notice = .error(error.localizedDescription)
        }
    }

    func refreshAll(showSpinner: Bool = true) async {
        let refreshID = showSpinner ? beginRefreshing() : nil
        defer {
            if let refreshID { endRefreshing(refreshID) }
        }

        let activeRepository = repository
        let generation = sessionGeneration
        let requestedWeek = selectedWeek

        async let newScores: ScoresSnapshot? = try? await activeRepository.loadScores(week: requestedWeek)
        async let newLineup: LineupSnapshot? = try? await activeRepository.loadLineup(week: requestedWeek)
        async let newWaivers: WaiverSnapshot? = try? await activeRepository.loadWaivers()
        async let newStandings: [StandingRow]? = try? await activeRepository.loadStandings()
        async let newBoard: [BoardThread]? = try? await activeRepository.loadBoard()
        let values = await (newScores, newLineup, newWaivers, newStandings, newBoard)

        guard generation == sessionGeneration else { return }

        var failures: [String] = []
        if selectedWeek == requestedWeek {
            if let scores = values.0 {
                self.scores = scores
            } else {
                failures.append("scores")
            }
            if let lineup = values.1 {
                self.lineup = lineup
                lineupRevision &+= 1
            } else {
                failures.append("lineup")
            }
        }
        if let waivers = values.2 {
            self.waivers = waivers
        } else {
            failures.append("waivers")
        }
        if let standings = values.3 {
            self.standings = standings
        } else {
            failures.append("standings")
        }
        if let board = values.4 {
            boardThreads = board
        } else {
            failures.append("the message board")
        }

        if !failures.isEmpty {
            notice = .error(refreshFailureMessage(for: failures))
        }
    }

    func changeWeek(to week: Int) async {
        guard week != selectedWeek else { return }
        selectedWeek = week
        weekLoadGeneration &+= 1
        let requestGeneration = weekLoadGeneration
        let generation = sessionGeneration
        let activeRepository = repository
        let refreshID = beginRefreshing()
        defer { endRefreshing(refreshID) }

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
            self.lineup = lineup
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
        guard let index = lineup.players.firstIndex(where: { $0.id == playerID }),
              !lineup.players[index].isLocked else { return }
        lineup.players[index].isStarter.toggle()
        if lineup.players[index].isStarter {
            lineup.tiebreakerPlayerIDs.removeAll(where: { $0 == playerID })
        }
    }

    func setTiebreaker(_ playerID: String) {
        lineup.tiebreakerPlayerIDs = playerID.isEmpty ? [] : [playerID]
    }

    var lineupValidationMessage: String? {
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
        if lineup.tiebreakerPlayerIDs.count != lineup.requiredTiebreakerCount {
            return lineup.requiredTiebreakerCount == 1
                ? "Choose one bench tiebreaker"
                : "Choose \(lineup.requiredTiebreakerCount) bench tiebreakers"
        }
        return nil
    }

    @discardableResult
    func submitLineup() async -> LineupSubmissionReceipt? {
        guard canSubmitChanges else {
            notice = .error(liveWriteDisabledMessage)
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
            }
            notice = .success(isDemo ? "Demo lineup saved on this device." : "Week \(submittedLineup.week) lineup submitted to MFL.")
            return LineupSubmissionReceipt(
                week: submittedLineup.week,
                starterIDs: Set(submittedLineup.starters.map(\.id)),
                tiebreakerPlayerIDs: submittedLineup.tiebreakerPlayerIDs
            )
        } catch {
            guard generation == sessionGeneration else { return nil }
            notice = .error(error.localizedDescription)
            return nil
        }
    }

    func upsertClaim(_ claim: WaiverClaim) {
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
    }

    func removeClaims(inRound round: Int, at offsets: IndexSet) {
        let orderedIDs = waivers.claims
            .filter { $0.round == round }
            .sorted(using: KeyPathComparator(\.priority))
            .map(\.id)
        let removedIDs = Set(offsets.compactMap { orderedIDs.indices.contains($0) ? orderedIDs[$0] : nil })
        waivers.claims.removeAll(where: { removedIDs.contains($0.id) })
        normalizeClaimPriorities()
    }

    func moveClaims(inRound round: Int, from offsets: IndexSet, to destination: Int) {
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
    }

    @discardableResult
    func submitWaivers() async -> Bool {
        guard canSubmitChanges else {
            notice = .error(liveWriteDisabledMessage)
            return false
        }
        guard !waivers.claims.isEmpty else { return false }
        guard waivers.maxRounds > 0,
              waivers.claims.allSatisfy({ (1 ... waivers.maxRounds).contains($0.round) }) else {
            notice = .error("Every bid must belong to one of this league’s configured waiver rounds.")
            return false
        }
        guard waivers.claims.allSatisfy({ $0.bid <= waivers.availableBudget && $0.bid >= 0 }) else {
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
            try await activeRepository.submitWaivers(submittedClaims)
            guard generation == sessionGeneration else { return false }
            notice = .success(isDemo ? "Demo waiver queue saved." : "Waiver requests submitted to MFL.")
            return true
        } catch {
            guard generation == sessionGeneration else { return false }
            notice = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func post(subject: String?, body: String, threadID: String? = nil) async -> Bool {
        guard canSubmitChanges else {
            notice = .error(liveWriteDisabledMessage)
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
            notice = .error(error.localizedDescription)
            return false
        }
    }

    func loadThread(id: String) async {
        if isDemo, id.hasPrefix("demo-local-thread-") { return }

        do {
            let loaded = try await repository.loadThread(id: id)
            if let index = boardThreads.firstIndex(where: { $0.id == id }) {
                boardThreads[index] = loaded
            }
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func signOut() async {
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
        resetContent(for: selectedWeek)
        repository = LiveMFLRepository()
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
        boardThreads = []
        lineupRevision &+= 1
    }

    private func installDemoContent() {
        isDemo = true
        workspace = SampleData.workspace
        selectedWeek = SampleData.workspace.week
        scores = SampleData.scores
        lineup = SampleData.lineup
        waivers = SampleData.waivers
        standings = SampleData.standings
        boardThreads = SampleData.board
        nextDemoMessageID = 0
        lineupRevision &+= 1
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

    private var liveWriteDisabledMessage: String {
        "This 0.1 safety preview is read-only for connected leagues. Live writes unlock after disposable-league verification and MFL client registration."
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
