import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

/// Stateful synthetic MFL server. No network and no real account data.
actor MutationFixtureTransport: MFLHTTPTransport {
    var rounds = [1: "101_5_0000", 2: "102_6_0000"]
    var imports: [String] = []
    var failRound: Int?
    var boardTimeout = false
    var hidePost = false
    var postedBody: String?
    var postedSubject: String?
    var postedThreadID: String?
    var boardAuthor = "0001"
    var currentWeek = 2
    var completedWeek = 1
    var membership = "0001"
    var slowMembership = false
    var projectionsMissing = false
    var projectionError: MFLCoreError?
    var tradeOffers: [[String: String]] = []
    var tradePlayerMoved = false
    var tradeTimeout = false
    var hideTradeReadback = false
    var removedAfterTimeout = false
    var activityRows: [[String: String]] = []
    var minimumBid: String? = "1"
    var flexScoring = false
    var divisionsEnabled = false
    var duplicateDivisionNames = false
    var incompleteStandings = false
    var requestCounts: [String: Int] = [:]
    func setActivity(_ rows: [[String: String]]) { activityRows = rows }
    func setMinimumBid(_ value: String?) { minimumBid = value }
    func enableFlexScoring() { flexScoring = true }
    func enableDivisions(sameNames: Bool = false) { divisionsEnabled = true; duplicateDivisionNames = sameNames }
    func omitStanding() { incompleteStandings = true }

    func seedTrade(outgoing: Bool = false, expired: Bool = false, unknownAsset: Bool = false) {
        tradeOffers = [["trade_id": "900", "offeringteam": outgoing ? "0001" : "0002", "offeredto": outgoing ? "0002" : "0001",
            "will_give_up": outgoing ? "201" : unknownAsset ? "UNKNOWN_123" : "101", "will_receive": outgoing ? "101" : "201",
            "expires": String(Int(Date().addingTimeInterval(expired ? -100 : 86_400).timeIntervalSince1970)), "comments": "Synthetic offer"]]
    }
    func moveTradePlayer() { tradePlayerMoved = true }
    func failTrade(afterRemoval: Bool = false) { tradeTimeout = true; removedAfterTimeout = afterRemoval }
    func hideTrade() { hideTradeReadback = true }
    func revealTrade() { hideTradeReadback = false }
    func changeTradeTerms() { tradeOffers[0]["will_receive"] = "201,BB_2" }

    func configure(failRound: Int? = nil, boardTimeout: Bool = false, hidePost: Bool = false, author: String = "0001") {
        self.failRound = failRound; self.boardTimeout = boardTimeout; self.hidePost = hidePost; boardAuthor = author
    }
    func revealPost() { hidePost = false }
    func changeMembership() { membership = "0002" }
    func delayMembership() { slowMembership = true }
    func omitProjections() { projectionsMissing = true }
    func failProjections(with error: MFLCoreError) { projectionError = error }

    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        var formComponents = URLComponents()
        formComponents.percentEncodedQuery = String(data: request.httpBody ?? Data(), encoding: .utf8)?.replacingOccurrences(of: "+", with: "%20")
        let form = Dictionary(uniqueKeysWithValues: (formComponents.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let type = query["TYPE"] ?? form["TYPE"] ?? ""
        requestCounts[type, default: 0] += 1
        func response(_ value: [String: Any]) throws -> MFLHTTPResponse {
            MFLHTTPResponse(data: try JSONSerialization.data(withJSONObject: value), statusCode: 200, url: request.url)
        }
        if request.url!.path.contains("mfl_status") {
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            return try response(["mfl_status": ["year": "2026", "weeks": ["CurrentWeek": currentWeek,
                "LineupWeek": currentWeek, "CompletedWeek": completedWeek, "LiveScoringWeek": currentWeek]]])
        }
        if request.httpMethod == "POST" {
            imports.append(type)
            if type == "tradeProposal" {
                tradeOffers.append(["trade_id": "901", "offeringteam": "0001", "offeredto": form["OFFEREDTO"]!,
                    "will_give_up": form["WILL_GIVE_UP"]!, "will_receive": form["WILL_RECEIVE"]!,
                    "comments": form["COMMENTS"] ?? "", "expires": form["EXPIRES"]!])
                if tradeTimeout { throw URLError(.timedOut) }
            } else if type == "tradeResponse" {
                if !tradeTimeout || removedAfterTimeout { tradeOffers.removeAll { $0["trade_id"] == form["TRADE_ID"] } }
                if tradeTimeout { throw URLError(.timedOut) }
            } else if type == "blindBidWaiverRequest" {
                let round = Int(form["ROUND"] ?? "")!
                if failRound == round { throw MFLCoreError.transport("Synthetic dropped connection") }
                let picks = form["PICKS"] ?? ""
                if picks.isEmpty { rounds.removeValue(forKey: round) } else { rounds[round] = picks }
            } else if type == "messageBoard" {
                postedBody = form["BODY"]; postedSubject = form["SUBJECT"]; postedThreadID = form["THREAD"]
                if boardTimeout { throw MFLCoreError.transport("Synthetic timeout after save") }
            }
            return try response(["status": "OK"])
        }
        switch type {
        case "pendingTrades":
            return try response(["pendingTrades": ["pendingTrade": hideTradeReadback ? [] : tradeOffers]])
        case "assets":
            return try response(["assets": ["franchise": [
                ["id": "0001", "players": ["player": tradePlayerMoved ? [] : [["id": "201"]]], "blindBiddingDollars": ["amount": "100"]],
                ["id": "0002", "players": ["player": [["id": "101"]]], "futureYearDraftPicks": ["draftPick": [["pick": "FP_0002_2027_1"]]], "blindBiddingDollars": ["amount": "50"]]
            ]]])
        case "myleagues":
            if slowMembership { try await Task.sleep(for: .seconds(60)) }
            return try response(["leagues": ["league": [["league_id": "41333", "franchise_id": membership,
                "url": "https://www45.myfantasyleague.com/2026/home/41333"]]]])
        case "league":
            var fields: [String: Any] = ["id": "41333", "name": "Fixture League", "baseURL": "https://www45.myfantasyleague.com",
                "startWeek": "1", "precision": "2", "bbidConditional": "Yes", "currentWaiverType": "BBID_FCFS",
                "maxWaiverRounds": "8", "bbidIncrement": "1", "bbidSeasonLimit": "100", "standingsSort": "PCT,PTS",
                "divisions": ["division": divisionsEnabled ? [["id": "00", "name": duplicateDivisionNames ? "Warner" : "Faulk"], ["id": "01", "name": "Warner"]] : []],
                "franchises": ["franchise": [["id": "0001", "name": "Fixture One", "bbidAvailableBalance": "100",
                    "owner_name": "  Avery &amp; Morgan  ", "division": divisionsEnabled ? "01" : "",
                    "icon": "https://images.example.com/2015/team-one.png", "logo": "https://images.example.com/team-one.jpg"],
                    ["id": "0002", "name": "Fixture Two", "ownerName": "  ", "division": divisionsEnabled ? "00" : "", "icon": "http://images.example.com/insecure.gif"]]]]
            fields["bbidMinimum"] = minimumBid
            if flexScoring {
                fields["starters"] = ["count": "3", "position": [
                    ["name": "QB", "limit": "1"], ["name": "RB", "limit": "1-2"], ["name": "WR", "limit": "0-1"]]]
            }
            return try response(["league": fields])
        case "leagueStandings":
            var rows = [["id": "0002", "h2hw": "1", "h2hl": "0", "h2ht": "0", "pf": "100"], ["id": "0001", "h2hw": "0", "h2hl": "1", "h2ht": "0", "pf": "90"]]
            if incompleteStandings { rows.removeFirst() }
            return try response(["leagueStandings": ["franchise": rows]])
        case "freeAgents":
            return try response(["freeAgents": ["leagueUnit": ["unit": "LEAGUE", "player": [["id": "101"], ["id": "102"]]]]])
        case "players":
            return try response(["players": ["player": [["id": "101", "name": "One, Player", "position": "WR", "team": "CHI"],
                                                         ["id": "201", "name": "Three, Player", "position": "QB", "team": "DAL"],
                                                         ["id": "102", "name": "Two, Player", "position": "RB", "team": "GB"]]]])
        case "rosters":
            return try response(["rosters": ["franchise": ["id": "0001", "player": [["id": "201", "status": "ROSTER"]]]]])
        case "projectedScores":
            if let projectionError { throw projectionError }
            return try response(["projectedScores": ["week": query["W"] ?? "1", "playerScore": projectionsMissing ? [] : [
                ["id": "101", "score": "13.25"], ["id": "", "score": ""],
                ["id": "102", "score": "0.0"], ["id": "201", "score": "19.5"]]]])
        case "playerRosterStatus":
            return try response(["playerRosterStatuses": ["player": [["id": "201", "franchise": [["id": "0001", "status": "S"]]]]]])
        case "liveScoring":
            let startingIDs = flexScoring ? ["201", "102", "101"] : ["201"]
            return try response(["liveScoring": ["week": query["W"] ?? "1", "matchup": ["franchise": [
                ["id": "0001", "score": "0", "playersYetToPlay": "1", "players": ["player": startingIDs.map { ["id": $0, "status": "starter", "gameSecondsRemaining": "3600", "score": "0"] }]],
                ["id": "0002", "score": "0", "playersYetToPlay": "1", "players": ["player": [["id": "101", "status": "starter", "gameSecondsRemaining": "3600", "score": "0"]]]]]]]])
        case "pendingWaivers":
            return try response(["pendingWaivers": ["waiverRequest": rounds.keys.sorted().map {
                ["round": String($0), "picks": rounds[$0]!, "franchise_id": "0001"]
            }]])
        case "calendar": return try response(["calendar": ["event": []]])
        case "transactions": return try response(["transactions": ["transaction": activityRows]])
        case "weeklyResults":
            return try response(["weeklyResults": ["week": "1", "matchup": ["franchise": [
                ["id": "0001", "score": "103.25"], ["id": "0002", "score": "100.75"]]]]])
        case "messageBoard":
            let threads: [[String: String]] = postedBody != nil && !hidePost && postedThreadID == nil
                ? [["id": "new-thread", "subject": postedSubject ?? "", "lastPostBy": boardAuthor]] : []
            return try response(["messageBoard": ["thread": threads]])
        case "messageBoardThread":
            var messages: [[String: String]] = []
            if postedBody != nil && !hidePost {
                messages = [["id": "new-message", "franchise_id": boardAuthor, "body": postedBody!,
                    "timestamp": String(Int(Date().timeIntervalSince1970))]]
            }
            return try response(["messageBoardThread": ["id": query["THREAD"] ?? "new-thread", "subject": postedSubject ?? "", "message": messages]])
        default: throw MFLCoreError.invalidRequest("Unexpected fixture endpoint \(type)")
        }
    }
}

struct MutationRecoveryTests {
    @Test("Standings use MFL owner names, preserve co-owners, and leave missing names unknown")
    func standingsOwners() async throws {
        let repository = try await connected(MutationFixtureTransport())
        let rows = try await repository.loadStandings()
        #expect(rows.first(where: { $0.id == "0001" })?.ownerName == "Avery & Morgan")
        #expect(rows.first(where: { $0.id == "0002" })?.ownerName == nil)
        #expect(rows.map(\.id) == ["0002", "0001"])
        #expect(rows.last?.divisionID == nil)
        #expect(rows.last?.summary(leagueName: "Fixture League") == "0–1 · 2nd in Fixture League")

        let dividedTransport = MutationFixtureTransport()
        await dividedTransport.enableDivisions()
        let dividedRepository = try await connected(dividedTransport)
        let dividedRows = try await dividedRepository.loadStandings()
        #expect(dividedRows.last?.overallPlace?.position == 2)
        #expect(dividedRows.last?.divisionID == "01")
        #expect(dividedRows.last?.summary(leagueName: "Fixture League") == "0–1 · 1st in Warner")
        let counts = await dividedTransport.requestCounts
        _ = try await dividedRepository.loadStandings()
        #expect(await dividedTransport.requestCounts == counts)

        let sameNames = MutationFixtureTransport()
        await sameNames.enableDivisions(sameNames: true)
        let sameNameRepository = try await connected(sameNames)
        let sameNameRows = try await sameNameRepository.loadStandings()
        #expect(sameNameRows.allSatisfy { $0.division == "Warner" && $0.divisionPlace?.position == 1 })
        #expect(Set(sameNameRows.compactMap(\.divisionID)).count == 2)

        let incomplete = MutationFixtureTransport()
        await incomplete.omitStanding()
        let incompleteRepository = try await connected(incomplete)
        #expect(try await incompleteRepository.loadStandings().allSatisfy { $0.overallPlace == nil && $0.divisionPlace == nil })
    }

    @Test("A confirmed zero-dollar minimum supports a complete synthetic waiver save and readback")
    func zeroDollarWaiver() async throws {
        let transport = MutationFixtureTransport()
        await transport.setMinimumBid(nil)
        let repository = try await connected(transport)
        let saved = try await repository.loadWaivers()
        #expect(saved.minimumBid == 0 && saved.increment == 1 && saved.unavailableReason == nil)
        var desired = saved.claims
        desired[0].bid = 0
        try await repository.submitWaivers(desired, replacing: saved.claims)
        #expect(await transport.rounds[1] == "101_0_0000")
        #expect(await transport.imports == ["blindBidWaiverRequest"])
        let confirmed = try await repository.loadWaivers()
        #expect(confirmed.claims.first?.bid == 0)
        await transport.setMinimumBid("2")
        desired[1].bid = 0
        await #expect(throws: (any Error).self) {
            try await repository.submitWaivers(desired, replacing: confirmed.claims)
        }
        #expect(await transport.imports.count == 1)
    }

    @Test("Live and completed matchups and official standings carry each franchise's safe artwork")
    func franchiseArtwork() async throws {
        let repository = try await connected(MutationFixtureTransport())
        let expected = [URL(string: "https://images.example.com/2015/team-one.png")!, URL(string: "https://images.example.com/team-one.jpg")!]
        for week in [1, 2] {
            let scores = try await repository.refreshScores(week: week)
            #expect(scores.matchups.first?.away.artworkURLs == expected)
            #expect(scores.matchups.first?.home.artworkURLs.isEmpty == true)
        }
        let standings = try await repository.loadStandings()
        #expect(standings.map(\.id) == ["0002", "0001"])
        #expect(standings.first?.artworkURLs.isEmpty == true)
        #expect(standings.last?.artworkURLs == expected)
    }

    @Test("Week 1 projections populate lineup, matchup totals and waiver candidates despite MFL's blank placeholder")
    func projections() async throws {
        let repository = try await connected(MutationFixtureTransport())
        let lineup = try await repository.loadLineup(week: 1)
        #expect(lineup.players.first?.projectedPoints == 19.5)
        let scores = try await repository.refreshScores(week: 2)
        #expect(scores.matchups.first?.away.projectedScore == 19.5)
        #expect(scores.matchups.first?.home.projectedScore == 13.25)
        let waivers = try await repository.loadWaivers()
        #expect(waivers.candidates.first(where: { $0.id == "101" })?.projectedPoints == 13.25)
        #expect(waivers.candidates.first(where: { $0.id == "102" })?.projectedPoints == 0)
        #expect(waivers.projectionWeek == 2)
    }

    @Test("Unavailable projections do not make the roster unavailable or fabricate zeroes")
    func absentProjections() async throws {
        let transport = MutationFixtureTransport()
        await transport.omitProjections()
        let repository = try await connected(transport)
        let lineup = try await repository.loadLineup(week: 1)
        #expect(!lineup.players.isEmpty)
        #expect(lineup.players.first?.projectedPoints == nil)
        #expect(lineup.projectionNote?.contains("unavailable") == true)
    }

    @Test("Projection failures explain the problem without claiming the feed is empty or blocking the roster",
          arguments: [MFLCoreError.decoding("synthetic-sensitive-detail"),
                      .unauthorized("synthetic-sensitive-detail"), .rateLimited(retryAfter: 90)])
    func projectionFailures(error: MFLCoreError) async throws {
        let transport = MutationFixtureTransport()
        await transport.failProjections(with: error)
        let repository = try await connected(transport)
        let lineup = try await repository.loadLineup(week: 1)
        #expect(!lineup.players.isEmpty)
        #expect(lineup.players.allSatisfy { $0.projectedPoints == nil })
        let note = try #require(lineup.projectionNote)
        #expect(!note.contains("synthetic-sensitive-detail"))
        #expect(!note.contains("unavailable from MFL"))
        switch error {
        case .decoding: #expect(note.contains("could not be read"))
        case .unauthorized: #expect(note.contains("denied access"))
        case .rateLimited: #expect(note.contains("limiting requests"))
        default: Issue.record("Unexpected test case")
        }
        let waivers = try await repository.loadWaivers()
        #expect(waivers.projectionNote != nil)
        #expect(!waivers.candidates.isEmpty)
    }

    @Test("Restore has a total deadline and keeps the saved cookie on a timeout")
    func restoreDeadline() async throws {
        let transport = MutationFixtureTransport()
        await transport.delayMembership()
        let store = MemoryPrivateStore()
        try store.encode(SavedSession(cookie: "synthetic-cookie", season: 2026, leagueID: "41333", franchiseID: "0001"), key: "session")
        let repository = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero, restoreTimeout: .milliseconds(20))
        await #expect(throws: (any Error).self) { try await repository.restoreSession() }
        #expect(store.read("session") != nil)
        await #expect(throws: (any Error).self) { try await repository.loadWorkspace() }
    }

    private func connected(_ transport: MutationFixtureTransport, store: MemoryPrivateStore = MemoryPrivateStore()) async throws -> LiveMFLRepository {
        try store.encode(SavedSession(cookie: "synthetic-cookie", season: 2026, leagueID: "41333", franchiseID: "0001"), key: "session")
        let repository = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero)
        _ = try await repository.restoreSession()
        return repository
    }

    @Test("Restoring authenticates membership and uses the current week, not league start week")
    func restoreAndFinalScores() async throws {
        let repository = try await connected(MutationFixtureTransport())
        #expect(try await repository.loadWorkspace().week == 2)
        let scores = try await repository.refreshScores(week: 1)
        #expect(scores.matchups[0].away.score == 103.25)
        #expect(scores.matchups[0].status == .final)
        #expect(scores.scorePrecision == 2)
    }

    @Test("Restored sessions cannot silently move drafts to a different franchise")
    func membershipChange() async throws {
        let transport = MutationFixtureTransport()
        await transport.changeMembership()
        await #expect(throws: (any Error).self) { try await connected(transport) }
    }

    @Test("Clearing all bids explicitly clears and reads back every saved round")
    func clearAll() async throws {
        let transport = MutationFixtureTransport()
        let repository = try await connected(transport)
        let saved = try await repository.loadWaivers()
        #expect(saved.claims.count == 2)
        try await repository.submitWaivers([], replacing: saved.claims)
        #expect(await transport.rounds.isEmpty)
        #expect(await transport.imports.count == 2)
    }

    @Test("Partial waiver saves stop without retry; stale-baseline retries are refused")
    func partialSave() async throws {
        let transport = MutationFixtureTransport()
        let repository = try await connected(transport)
        let saved = try await repository.loadWaivers()
        var desired = saved.claims
        desired[0].bid = 10; desired[1].bid = 11
        await transport.configure(failRound: 2)
        await #expect(throws: (any Error).self) { try await repository.submitWaivers(desired, replacing: saved.claims) }
        #expect(await transport.imports.count == 2)
        #expect(await transport.rounds[1] == "101_10_0000")
        #expect(await transport.rounds[2] == "102_6_0000")
        await #expect(throws: (any Error).self) { try await repository.submitWaivers(desired, replacing: saved.claims) }
        #expect(await transport.imports.count == 2)
    }

    @Test("A new thread saved before timeout is verified by owner and full body without resending")
    func boardTimeout() async throws {
        let transport = MutationFixtureTransport()
        let repository = try await connected(transport)
        await transport.configure(boardTimeout: true)
        try await repository.postMessage(subject: "Fixture subject", body: "Fixture body", threadID: nil)
        #expect(await transport.imports == ["messageBoard"])
        #expect(try await repository.pendingBoardPost() == nil)
    }

    @Test("An ambiguous reply stays blocked across repository recreation until readback confirms it")
    func ambiguousReply() async throws {
        let transport = MutationFixtureTransport()
        let store = MemoryPrivateStore()
        let repository = try await connected(transport, store: store)
        await transport.configure(boardTimeout: true, hidePost: true)
        await #expect(throws: (any Error).self) {
            try await repository.postMessage(subject: nil, body: "Fixture reply", threadID: "existing-thread")
        }
        #expect(try await repository.pendingBoardPost() != nil)
        let restored = try await connected(transport, store: store)
        await #expect(throws: (any Error).self) {
            try await restored.postMessage(subject: nil, body: "Fixture reply", threadID: "existing-thread")
        }
        #expect(await transport.imports.count == 1)
        await transport.revealPost()
        #expect(try await restored.reconcileBoardPost())
        #expect(try await restored.pendingBoardPost() == nil)
    }

    @Test("A matching subject and body from another owner is not confirmation")
    func wrongOwner() async throws {
        let transport = MutationFixtureTransport()
        let repository = try await connected(transport)
        await transport.configure(author: "0002")
        await #expect(throws: (any Error).self) {
            try await repository.postMessage(subject: "Same subject", body: "Same body", threadID: nil)
        }
        #expect(try await repository.pendingBoardPost() != nil)
    }
}
