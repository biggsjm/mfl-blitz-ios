import Foundation
import MFLCore

actor LiveMFLRepository: LeagueRepository {
    private var client: MFLClient?
    private var league: MFLLeague?
    private var workspace: LeagueWorkspace?

    func signIn(with credentials: LoginCredentials) async throws -> LeagueWorkspace {
        let reference = try MFLLeagueReference(season: credentials.season, leagueID: credentials.leagueID)
        let configuration = MFLClientConfiguration(
            league: reference,
            userAgent: "MFL Blitz/0.1 (com.biggsjm.MFLBlitz)",
            minimumRequestInterval: .seconds(1)
        )
        let newClient = MFLClient(configuration: configuration)
        _ = try await newClient.authenticate(username: credentials.username, password: credentials.password)
        let loadedLeague = try await newClient.league(refreshPolicy: .reloadIgnoringCache)

        guard let franchise = ownedFranchise(in: loadedLeague, username: credentials.username) else {
            throw RepositoryError.server(
                "MFL accepted the login, but this account could not be matched to a franchise in league \(credentials.leagueID)."
            )
        }

        let scoring = try await newClient.liveScoring(refreshPolicy: .reloadIgnoringCache)
        let host = try await newClient.discoverLeagueHost()
        guard let baseURL = URL(string: "https://\(host.name)") else {
            throw RepositoryError.server("MFL returned an invalid league host.")
        }

        let newWorkspace = LeagueWorkspace(
            leagueID: credentials.leagueID,
            season: credentials.season,
            leagueName: loadedLeague.name,
            franchiseID: franchise.id,
            franchiseName: cleanText(franchise.name),
            baseURL: baseURL,
            week: scoring.week ?? loadedLeague.startWeek ?? 1
        )

        client = newClient
        league = loadedLeague
        workspace = newWorkspace
        return newWorkspace
    }

    func loadWorkspace() async throws -> LeagueWorkspace {
        try requireWorkspace()
    }

    func loadScores(week: Int) async throws -> ScoresSnapshot {
        let (client, _, workspace) = try requireSession()
        async let liveTask = client.liveScoring(week: week, includeBench: true)
        async let leagueTask = client.league()
        let (live, refreshedLeague) = try await (liveTask, leagueTask)
        self.league = refreshedLeague

        let franchiseByID = Dictionary(uniqueKeysWithValues: refreshedLeague.franchises.map { ($0.id, $0) })
        let matchups = live.matchups.compactMap { matchup -> Matchup? in
            guard matchup.franchises.count >= 2 else { return nil }
            let ordered = matchup.franchises.sorted { lhs, rhs in
                if lhs.isHome == rhs.isHome { return lhs.franchiseID < rhs.franchiseID }
                return lhs.isHome == false
            }
            let away = ordered[0]
            let home = ordered[1]
            let awayTeam = makeMatchupTeam(away, franchise: franchiseByID[away.franchiseID])
            let homeTeam = makeMatchupTeam(home, franchise: franchiseByID[home.franchiseID])
            return Matchup(
                id: matchup.id,
                away: awayTeam,
                home: homeTeam,
                isUserMatchup: away.franchiseID == workspace.franchiseID || home.franchiseID == workspace.franchiseID,
                status: gameStatus(for: [away, home])
            )
        }

        return ScoresSnapshot(
            week: live.week ?? week,
            matchups: matchups,
            lastUpdated: Date(),
            isLive: matchups.contains(where: { $0.status.isLive })
        )
    }

    func loadLineup(week: Int) async throws -> LineupSnapshot {
        let (client, league, workspace) = try requireSession()
        async let rosterTask = client.rosters(franchiseID: workspace.franchiseID, week: week)
        async let liveTask = client.liveScoring(week: week, includeBench: true)
        let (rosterCollection, live) = try await (rosterTask, liveTask)
        guard let roster = rosterCollection.rosters.first(where: { $0.franchiseID == workspace.franchiseID }) else {
            throw RepositoryError.server("MFL returned no roster for \(workspace.franchiseName).")
        }

        let catalog = try await client.players(ids: roster.players.map(\.id))
        let playerByID = Dictionary(uniqueKeysWithValues: catalog.players.map { ($0.id, $0) })
        let liveFranchise = live.matchups
            .flatMap(\.franchises)
            .first(where: { $0.franchiseID == workspace.franchiseID })
        let liveByID = Dictionary(uniqueKeysWithValues: (liveFranchise?.players ?? []).map { ($0.id, $0) })

        let players = roster.players.map { rosterPlayer -> LineupPlayer in
            let player = playerByID[rosterPlayer.id]
            let livePlayer = liveByID[rosterPlayer.id]
            return LineupPlayer(
                id: rosterPlayer.id,
                name: cleanText(player?.displayName ?? "Player \(rosterPlayer.id)"),
                position: player?.position ?? "—",
                nflTeam: player?.nflTeam ?? "FA",
                opponent: "—",
                projectedPoints: nil,
                seasonPoints: livePlayer?.score.doubleValue ?? 0,
                isStarter: livePlayer?.isStarter ?? false,
                isLocked: livePlayer.map { $0.gameSecondsRemaining < 3_600 } ?? false,
                injuryStatus: nil,
                gameTime: Date()
            )
        }

        let requirements = league.starterRequirements.map {
            LineupPositionRequirement(
                position: $0.position,
                minimum: $0.minimum ?? 0,
                maximum: $0.maximum ?? $0.minimum ?? 0
            )
        }

        return LineupSnapshot(
            week: live.week ?? week,
            players: players,
            requiredStarterCount: league.starterCount ?? players.filter(\.isStarter).count,
            positionRequirements: requirements,
            requiredTiebreakerCount: league.tiebreakerCount ?? 0,
            tiebreakerPlayerIDs: [],
            deadline: nil,
            lastSubmitted: nil
        )
    }

    func submitLineup(_ lineup: LineupSnapshot) async throws {
        let (client, _, workspace) = try requireSession()
        let submittedStarterIDs = lineup.starters.map(\.id)
        let submittedTiebreakerIDs = lineup.tiebreakerPlayerIDs

        guard hasUniqueIdentifiers(submittedStarterIDs),
              hasUniqueIdentifiers(submittedTiebreakerIDs),
              Set(submittedStarterIDs).isDisjoint(with: submittedTiebreakerIDs)
        else {
            throw RepositoryError.server(
                "The lineup contains a duplicate player or uses a starter as a tiebreaker, so it was not submitted."
            )
        }

        _ = try await client.submitLineup(
            MFLLineupSubmission(
                week: lineup.week,
                starterPlayerIDs: submittedStarterIDs,
                tiebreakerPlayerIDs: submittedTiebreakerIDs
            )
        )

        let verified = try await client.liveScoring(
            week: lineup.week,
            includeBench: true,
            refreshPolicy: .reloadIgnoringCache
        )
        guard let serverFranchise = verified.matchups
            .flatMap(\.franchises)
            .first(where: { $0.franchiseID == workspace.franchiseID })
        else {
            throw RepositoryError.server(
                "MFL replied, but did not return your lineup for verification. Refresh before trying again."
            )
        }

        let serverStarterIDs = serverFranchise.players.filter(\.isStarter).map(\.id)
        guard containsExactlyTheSameIdentifiers(serverStarterIDs, submittedStarterIDs) else {
            throw RepositoryError.server(
                "MFL replied, but its saved starters did not exactly match the submitted lineup. Refresh before trying again."
            )
        }

        // MFL's live-scoring feed normally reports only starter/nonstarter. Some
        // league variants identify a tiebreaker in the raw status; when it does,
        // require the same exact confirmation as the starter list.
        let serverTiebreakerIDs = serverFranchise.players
            .filter { isTiebreakerStatus($0.status) }
            .map(\.id)
        if !serverTiebreakerIDs.isEmpty,
           !containsExactlyTheSameIdentifiers(serverTiebreakerIDs, submittedTiebreakerIDs)
        {
            throw RepositoryError.server(
                "MFL replied, but its saved tiebreakers did not exactly match the submitted lineup. Refresh before trying again."
            )
        }
    }

    func loadWaivers() async throws -> WaiverSnapshot {
        let (client, league, workspace) = try requireSession()
        async let freeAgentTask = client.freeAgents()
        async let pendingTask = client.pendingWaivers()
        let (freeAgentPool, pending) = try await (freeAgentTask, pendingTask)
        let catalog = try await client.players()
        let playerByID = Dictionary(uniqueKeysWithValues: catalog.players.map { ($0.id, $0) })
        let ownedRoster = try await client.rosters(franchiseID: workspace.franchiseID)
        let ownedIDs = Set(ownedRoster.rosters.first?.players.map(\.id) ?? [])
        let ownedNames = Dictionary(uniqueKeysWithValues: catalog.players.filter { ownedIDs.contains($0.id) }.map { ($0.id, $0.displayName) })

        let candidates = freeAgentPool.players.compactMap { freeAgent -> WaiverCandidate? in
            guard let player = playerByID[freeAgent.id],
                  let position = player.position,
                  ["QB", "RB", "WR", "TE", "K", "DEF"].contains(position) else { return nil }
            return WaiverCandidate(
                id: freeAgent.id,
                name: cleanText(player.displayName),
                position: position,
                nflTeam: player.nflTeam ?? "FA",
                rosteredPercent: 0,
                projectedPoints: nil,
                seasonPoints: 0,
                trend: 0,
                injuryStatus: nil
            )
        }
        let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let claims = pending.requests
            .filter { $0.franchiseID == nil || $0.franchiseID == workspace.franchiseID }
            .flatMap { request in
                request.claims.enumerated().compactMap { index, claim -> WaiverClaim? in
                    guard let player = candidateByID[claim.playerID] ?? makeFallbackCandidate(id: claim.playerID, catalog: playerByID) else { return nil }
                    return WaiverClaim(
                        player: player,
                        bid: claim.bidAmount ?? 0,
                        dropPlayerID: claim.dropPlayerID,
                        dropPlayerName: claim.dropPlayerID.flatMap { ownedNames[$0] },
                        round: request.round ?? 1,
                        priority: claim.priority ?? index + 1
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.round == rhs.round { return lhs.priority < rhs.priority }
                return lhs.round < rhs.round
            }

        let franchise = league.franchises.first(where: { $0.id == workspace.franchiseID })
        return WaiverSnapshot(
            availableBudget: franchise?.blindBidAvailableBalance ?? league.blindBidSeasonLimit ?? 0,
            increment: league.blindBidIncrement ?? league.blindBidMinimum ?? 1,
            maxRounds: league.maxWaiverRounds ?? 1,
            candidates: candidates,
            claims: claims,
            processesAt: nil
        )
    }

    func submitWaivers(_ claims: [WaiverClaim]) async throws {
        let (client, league, workspace) = try requireSession()
        let expectedClaims = try waiverVerificationClaims(from: claims)
        let highestSubmittedRound = expectedClaims.map(\.round).max() ?? 0

        if let configuredMaximum = league.maxWaiverRounds,
           highestSubmittedRound > configuredMaximum
        {
            throw RepositoryError.server(
                "The waiver queue contains a round beyond this league's configured limit, so it was not submitted."
            )
        }

        // Read first so only confirmed differences are mutated. MFL has no
        // transactional batch or idempotency key, so all local validation and
        // comparison happens before the first mutation.
        let pendingBeforeWrite = try await client.pendingWaivers(
            franchiseID: workspace.franchiseID,
            refreshPolicy: .reloadIgnoringCache
        )
        let existingClaims = try waiverVerificationClaims(
            from: pendingBeforeWrite,
            franchiseID: workspace.franchiseID
        )
        let expectedByRound = Dictionary(grouping: expectedClaims, by: \.round)
        let existingByRound = Dictionary(grouping: existingClaims, by: \.round)
        let affectedRounds = Set(expectedByRound.keys)
            .union(existingByRound.keys)
            .filter { expectedByRound[$0, default: []] != existingByRound[$0, default: []] }
            .sorted { lhs, rhs in
                // Make non-empty replacements before deliberate clears. If MFL
                // rejects an early request, confirmed existing later rounds are
                // left intact.
                let lhsIsClear = expectedByRound[lhs, default: []].isEmpty
                let rhsIsClear = expectedByRound[rhs, default: []].isEmpty
                if lhsIsClear != rhsIsClear { return rhsIsClear }
                return lhs < rhs
            }

        for round in affectedRounds {
            let bids = expectedByRound[round, default: []].map {
                MFLBlindBid(
                    playerID: $0.playerID,
                    amount: $0.bid,
                    dropPlayerID: $0.dropPlayerID
                )
            }
            _ = try await client.submitBlindBidWaiverRequest(
                MFLBlindBidWaiverRequest(
                    round: round,
                    bids: bids,
                    replaceExisting: true
                )
            )
        }

        if !affectedRounds.isEmpty {
            let verified = try await client.pendingWaivers(
                franchiseID: workspace.franchiseID,
                refreshPolicy: .reloadIgnoringCache
            )
            let savedClaims = try waiverVerificationClaims(
                from: verified,
                franchiseID: workspace.franchiseID
            )
            guard savedClaims == expectedClaims else {
                throw RepositoryError.server(
                    "MFL replied, but its saved waiver count, order, players, drops, or bids did not exactly match the submitted queue. Refresh before trying again."
                )
            }
        }
    }

    func loadStandings() async throws -> [StandingRow] {
        let (client, league, workspace) = try requireSession()
        let standings = try await client.standings()
        let franchiseByID = Dictionary(uniqueKeysWithValues: league.franchises.map { ($0.id, $0) })
        let divisionByID = Dictionary(uniqueKeysWithValues: league.divisions.map { ($0.id, $0.name) })

        return standings.franchises.enumerated().map { index, item in
            let franchise = franchiseByID[item.id]
            return StandingRow(
                id: item.id,
                rank: index + 1,
                name: cleanText(franchise?.name ?? "Franchise \(item.id)"),
                abbreviation: franchise?.abbreviation ?? String(format: "%02d", index + 1),
                division: franchise?.divisionID.flatMap { divisionByID[$0] } ?? "League",
                wins: item.wins ?? 0,
                losses: item.losses ?? 0,
                ties: item.ties ?? 0,
                pointsFor: item.pointsFor?.doubleValue ?? 0,
                pointsAgainst: item.pointsAgainst?.doubleValue ?? 0,
                streak: item.streak ?? "—",
                isUser: item.id == workspace.franchiseID,
                accentSeed: Int(item.id) ?? index
            )
        }
    }

    func loadBoard() async throws -> [BoardThread] {
        let (client, league, _) = try requireSession()
        let board = try await client.messageBoard(count: 30)
        let franchiseByID = Dictionary(uniqueKeysWithValues: league.franchises.map { ($0.id, cleanText($0.name)) })

        return board.threads.map { summary in
            let preview = summary.attributes["body"]?.stringValue
                ?? summary.attributes["message"]?.stringValue
                ?? "Open to read the latest post."
            return BoardThread(
                id: summary.id,
                subject: cleanText(summary.subject),
                author: summary.lastPostFranchiseID.flatMap { franchiseByID[$0] } ?? "League member",
                preview: cleanText(preview),
                lastActivity: summary.lastPostDate ?? .distantPast,
                replyCount: summary.replyCount ?? 0,
                isUnread: false,
                posts: []
            )
        }
    }

    func loadThread(id: String) async throws -> BoardThread {
        let (client, league, workspace) = try requireSession()
        let loaded = try await client.messageBoardThread(id: id)
        let franchiseByID = Dictionary(uniqueKeysWithValues: league.franchises.map { ($0.id, cleanText($0.name)) })
        let existing = try? await loadBoard().first(where: { $0.id == id })
        let posts = loaded.messages.map { message in
            BoardPost(
                id: message.id,
                author: message.franchiseID.flatMap { franchiseByID[$0] } ?? "League member",
                body: cleanText(message.body),
                postedAt: message.date ?? .distantPast,
                isUser: message.franchiseID == workspace.franchiseID
            )
        }
        return BoardThread(
            id: id,
            subject: cleanText(loaded.subject ?? existing?.subject ?? "Message board"),
            author: posts.first?.author ?? existing?.author ?? "League member",
            preview: posts.last?.body ?? existing?.preview ?? "",
            lastActivity: posts.last?.postedAt ?? existing?.lastActivity ?? .distantPast,
            replyCount: max(0, posts.count - 1),
            isUnread: false,
            posts: posts
        )
    }

    func postMessage(subject: String?, body: String, threadID: String?) async throws {
        let (client, _, workspace) = try requireSession()
        let expectedBody = cleanText(body)

        if let threadID {
            let before = try await client.messageBoardThread(
                id: threadID,
                refreshPolicy: .reloadIgnoringCache
            )
            let existingMessageIDs = Set(before.messages.map(\.id))

            _ = try await client.postMessageBoard(
                MFLMessageBoardPost(threadID: threadID, subject: subject, body: body)
            )
            let verified = try await client.messageBoardThread(
                id: threadID,
                refreshPolicy: .reloadIgnoringCache
            )
            let newMessages = verified.messages.filter { !existingMessageIDs.contains($0.id) }
            let confirmed = newMessages.reversed().contains { message in
                message.franchiseID == workspace.franchiseID
                    && cleanText(message.body) == expectedBody
            } || newMessages.reversed().contains { message in
                message.franchiseID == nil
                    && cleanText(message.body) == expectedBody
            }
            guard confirmed else {
                throw messageVerificationUnavailable()
            }
            return
        }

        let expectedSubject = cleanText(subject ?? "")
        let before = try await client.messageBoard(
            count: 30,
            refreshPolicy: .reloadIgnoringCache
        )
        let existingThreadIDs = Set(before.threads.map(\.id))
        _ = try await client.postMessageBoard(
            MFLMessageBoardPost(threadID: threadID, subject: subject, body: body)
        )

        let verified = try await client.messageBoard(
            count: 30,
            refreshPolicy: .reloadIgnoringCache
        )
        let confirmed = verified.threads.contains { thread in
            guard !existingThreadIDs.contains(thread.id),
                  cleanText(thread.subject) == expectedSubject,
                  thread.lastPostFranchiseID == nil || thread.lastPostFranchiseID == workspace.franchiseID
            else {
                return false
            }
            guard let serverBody = messageBody(in: thread.attributes) else {
                // The documented summary export does not promise a body. A new
                // server id plus the exact subject (and author when supplied) is
                // the strongest available confirmation in that representation.
                return true
            }
            return cleanText(serverBody) == expectedBody
        }
        guard confirmed else {
            throw messageVerificationUnavailable()
        }
    }

    func signOut() async {
        await client?.setAuthenticationCookie(nil)
        client = nil
        league = nil
        workspace = nil
    }

    private func requireWorkspace() throws -> LeagueWorkspace {
        guard let workspace else { throw RepositoryError.missingSession }
        return workspace
    }

    private func requireSession() throws -> (MFLClient, MFLLeague, LeagueWorkspace) {
        guard let client, let league, let workspace else { throw RepositoryError.missingSession }
        return (client, league, workspace)
    }

    private func ownedFranchise(in league: MFLLeague, username: String) -> MFLFranchise? {
        if let exact = league.franchises.first(where: {
            $0.username?.caseInsensitiveCompare(username) == .orderedSame
        }) {
            return exact
        }
        let franchisesWithPrivateOwnerData = league.franchises.filter { $0.username != nil }
        return franchisesWithPrivateOwnerData.count == 1 ? franchisesWithPrivateOwnerData[0] : nil
    }

    private func makeMatchupTeam(_ value: MFLLiveFranchise, franchise: MFLFranchise?) -> MatchupTeam {
        MatchupTeam(
            id: value.franchiseID,
            name: cleanText(franchise?.name ?? "Franchise \(value.franchiseID)"),
            abbreviation: franchise?.abbreviation ?? value.franchiseID,
            score: value.score.doubleValue,
            projectedScore: nil,
            playersRemaining: value.playersYetToPlay + value.playersCurrentlyPlaying,
            accentSeed: Int(value.franchiseID) ?? 0
        )
    }

    private func gameStatus(for franchises: [MFLLiveFranchise]) -> GameStatus {
        if franchises.contains(where: { $0.playersCurrentlyPlaying > 0 }) {
            return .live("In progress")
        }
        if franchises.contains(where: { $0.playersYetToPlay > 0 }) {
            return .pregame(nil)
        }
        return .final
    }

    private func makeFallbackCandidate(
        id: String,
        catalog: [String: MFLPlayer]
    ) -> WaiverCandidate? {
        guard let player = catalog[id] else { return nil }
        return WaiverCandidate(
            id: id,
            name: cleanText(player.displayName),
            position: player.position ?? "—",
            nflTeam: player.nflTeam ?? "FA",
            rosteredPercent: 0,
            projectedPoints: nil,
            seasonPoints: 0,
            trend: 0,
            injuryStatus: nil
        )
    }

    private func hasUniqueIdentifiers(_ identifiers: [String]) -> Bool {
        Set(identifiers).count == identifiers.count
    }

    private func containsExactlyTheSameIdentifiers(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.count == rhs.count && Set(lhs) == Set(rhs)
    }

    private func isTiebreakerStatus(_ status: MFLLivePlayerStatus) -> Bool {
        status.rawValue
            .lowercased()
            .filter(\.isLetter)
            .contains("tiebreak")
    }

    private struct VerifiedWaiverClaim: Equatable {
        let round: Int
        let position: Int
        let playerID: String
        let dropPlayerID: String?
        let bid: Decimal
    }

    private struct ServerWaiverClaim {
        let claim: MFLWaiverClaim
    }

    private func waiverVerificationClaims(from claims: [WaiverClaim]) throws -> [VerifiedWaiverClaim] {
        guard claims.allSatisfy({
            $0.round > 0
                && $0.priority > 0
                && isValidMFLIdentifier($0.player.id)
                && $0.bid >= 0
                && !$0.bid.isNaN
                && ($0.dropPlayerID.map { isValidMFLIdentifier($0) } ?? true)
        }) else {
            throw RepositoryError.server(
                "Every waiver request needs a valid player, bid, drop, and positive round, so the queue was not submitted."
            )
        }

        let indexedClaims = claims.enumerated().sorted { lhs, rhs in
            if lhs.element.round == rhs.element.round {
                if lhs.element.priority == rhs.element.priority {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.priority < rhs.element.priority
            }
            return lhs.element.round < rhs.element.round
        }

        let prioritiesByRound = Dictionary(grouping: indexedClaims, by: \.element.round)
        guard prioritiesByRound.values.allSatisfy({ values in
            values.map(\.element.priority) == Array(1 ... values.count)
        }) else {
            throw RepositoryError.server(
                "Waiver alternatives in each round must have a unique, consecutive priority, so the queue was not submitted."
            )
        }

        return indexedClaims.map { indexed in
            return VerifiedWaiverClaim(
                round: indexed.element.round,
                position: indexed.element.priority,
                playerID: indexed.element.player.id,
                dropPlayerID: normalizedDropPlayerID(indexed.element.dropPlayerID),
                bid: indexed.element.bid
            )
        }
    }

    private func waiverVerificationClaims(
        from pending: MFLPendingWaivers,
        franchiseID: String
    ) throws -> [VerifiedWaiverClaim] {
        var claimsByRound: [Int: [ServerWaiverClaim]] = [:]

        for request in pending.requests where requestBelongsToFranchise(request, franchiseID: franchiseID) {
            guard !request.claims.isEmpty else { continue }
            guard let round = request.round, round > 0 else {
                throw waiverVerificationUnavailable()
            }
            guard rawClaimCount(in: request) == request.claims.count else {
                throw waiverVerificationUnavailable()
            }

            let compactDropEvidence = compactClaimsHaveExplicitDrops(in: request)
            for (index, claim) in request.claims.enumerated() {
                let hasExplicitDrop = hasExplicitDropAttribute(claim)
                    || compactDropEvidence?[safe: index] == true
                guard claim.bidAmount != nil, hasExplicitDrop else {
                    throw waiverVerificationUnavailable()
                }
                claimsByRound[round, default: []].append(
                    ServerWaiverClaim(claim: claim)
                )
            }
        }

        var verified: [VerifiedWaiverClaim] = []
        for round in claimsByRound.keys.sorted() {
            guard let serverClaims = claimsByRound[round] else { continue }
            let priorities = serverClaims.map(\.claim.priority)
            if priorities.contains(where: { $0 != nil }) {
                guard priorities.allSatisfy({ $0 != nil }),
                      priorities.compactMap({ $0 }) == Array(1 ... serverClaims.count)
                else {
                    throw waiverVerificationUnavailable()
                }
            }

            for (offset, value) in serverClaims.enumerated() {
                guard let bid = value.claim.bidAmount else {
                    throw waiverVerificationUnavailable()
                }
                verified.append(
                    VerifiedWaiverClaim(
                        round: round,
                        position: offset + 1,
                        playerID: value.claim.playerID,
                        dropPlayerID: normalizedDropPlayerID(value.claim.dropPlayerID),
                        bid: bid
                    )
                )
            }
        }
        return verified
    }

    private func requestBelongsToFranchise(
        _ request: MFLPendingWaiver,
        franchiseID: String
    ) -> Bool {
        request.franchiseID == nil || request.franchiseID == franchiseID
    }

    private func rawClaimCount(in request: MFLPendingWaiver) -> Int {
        for key in ["pick", "claim", "bid", "request"] {
            if let value = request.attributes[key] {
                return value.arrayValue?.count ?? 0
            }
        }
        if let compact = request.attributes["picks"]?.stringValue
            ?? request.attributes["PICKS"]?.stringValue
        {
            return compact.split(separator: ",", omittingEmptySubsequences: true).count
        }
        return request.claims.count
    }

    private func compactClaimsHaveExplicitDrops(in request: MFLPendingWaiver) -> [Bool]? {
        guard let compact = request.attributes["picks"]?.stringValue
            ?? request.attributes["PICKS"]?.stringValue
        else {
            return nil
        }
        return compact.split(separator: ",", omittingEmptySubsequences: true).map { pick in
            pick.split(separator: "_", omittingEmptySubsequences: false).count >= 3
        }
    }

    private func hasExplicitDropAttribute(_ claim: MFLWaiverClaim) -> Bool {
        let keys = Set(claim.attributes.keys.map { $0.lowercased() })
        return !keys.isDisjoint(with: [
            "drop",
            "dropplayer",
            "drop_player",
            "dropplayerid",
            "drop_player_id",
        ])
    }

    private func normalizedDropPlayerID(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "0000" else { return nil }
        return value
    }

    private func isValidMFLIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty
            && !identifier.contains(",")
            && !identifier.contains("_")
            && !identifier.contains("\r")
            && !identifier.contains("\n")
    }

    private func waiverVerificationUnavailable() -> RepositoryError {
        RepositoryError.server(
            "MFL replied, but omitted a waiver round, order, drop, or bid needed to verify the saved queue. Refresh and confirm it on MFL."
        )
    }

    private func messageBody(in attributes: [String: MFLJSONValue]) -> String? {
        attributes["body"]?.stringValue
            ?? attributes["message"]?.stringValue
            ?? attributes["text"]?.stringValue
    }

    private func messageVerificationUnavailable() -> RepositoryError {
        RepositoryError.server(
            "MFL accepted the message, but the board export did not provide enough matching data to verify it. Refresh and confirm it on MFL."
        )
    }

    private func cleanText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
