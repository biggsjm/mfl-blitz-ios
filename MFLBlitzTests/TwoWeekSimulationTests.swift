import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

/// An accelerated game clock, not a claim that two real NFL weeks elapsed.
/// Every request terminates in this actor; no URLSession or live league writes.
private actor TwoWeekLeague {
    enum Phase { case pregame, live, final }
    static let owners = ["Avery · Casual", "Morgan · Optimizer", "Casey · Trader", "Riley · Commuter"]
    static let teams = (1...4).map { String(format: "%04d", $0) }
    static func player(_ team: Int, _ offset: Int) -> String { String(10_000 + team * 100 + offset) }
    static func freeAgent(_ week: Int, _ team: Int) -> String { String(90_000 + week * 10 + team) }
    var week = 1
    var phase = Phase.pregame
    var correction = 0
    var rosters: [String: [String]] = [:]
    var starters: [Int: [String: Set<String>]] = [:]
    var queues: [String: [Int: String]] = [:]
    var budgets: [String: Int] = [:]
    var offers: [[String: String]] = []
    var activity: [[String: String]] = []
    var subjects: [String: String] = [:]
    var posts: [String: [[String: String]]] = [:]
    var requestCounts: [String: Int] = [:]
    var writes: [(owner: String, type: String, week: Int)] = []
    var offline: Set<String> = []
    var failAfterSave: Set<String> = []
    var expired: Set<String> = []
    var nextID = 1

    init() {
        for (index, team) in Self.teams.enumerated() {
            rosters[team] = (0..<14).map { Self.player(index + 1, $0) }
            budgets[team] = 100
        }
        for week in 1...2 {
            starters[week] = Dictionary(uniqueKeysWithValues: Self.teams.enumerated().map { index, team in
                (team, Set((0..<9).map { Self.player(index + 1, $0) }))
            })
        }
    }

    func advance(week: Int, phase: Phase) { self.week = week; self.phase = phase }
    func correctScores() { correction = 2 }
    func disconnect(_ team: String, _ value: Bool) { if value { offline.insert(team) } else { offline.remove(team) } }
    func expire(_ team: String, _ value: Bool) { if value { expired.insert(team) } else { expired.remove(team) } }
    func loseNextAcknowledgement(_ type: String) { failAfterSave.insert(type) }
    func countWrites(_ type: String) -> Int { writes.filter { $0.type == type }.count }
    func saved(_ team: String, week: Int) -> Set<String> { starters[week]?[team] ?? [] }

    private var catalog: [[String: String]] {
        let positions = ["QB", "RB", "RB", "WR", "WR", "WR", "TE", "RB", "WR", "QB", "RB", "WR", "TE", "TE"]
        var rows = (1...4).flatMap { team in
            positions.enumerated().map { offset, position in
                ["id": Self.player(team, offset), "name": "Synthetic \(team)-\(offset), Player", "position": position, "team": "CHI"]
            }
        }
        rows += (1...2).flatMap { week in (1...4).map { team in
            ["id": Self.freeAgent(week, team), "name": "Week \(week) Pickup \(team), Player", "position": "TE", "team": "GB"]
        } }
        return rows
    }

    func processWaivers() {
        // Deterministic no-tie synthetic results; not an emulation of MFL's tie breakers.
        for team in Self.teams {
            for (_, picks) in (queues[team] ?? [:]).sorted(by: { $0.key < $1.key }) {
                guard let first = picks.split(separator: ",").first else { continue }
                let parts = first.split(separator: "_").map(String.init)
                guard parts.count == 3, let amount = Int(parts[1]), !(rosters.values.flatMap { $0 }).contains(parts[0]) else { continue }
                rosters[team, default: []].removeAll { $0 == parts[2] }
                rosters[team, default: []].append(parts[0])
                budgets[team, default: 100] -= amount
                activity.append(["id": "w\(week)-\(team)", "type": "BBID_WAIVER", "franchise": team,
                    "transaction": "\(parts[0])|\(amount)|\(parts[2])", "timestamp": String(Int(Date().timeIntervalSince1970))])
            }
            queues[team] = [:]
        }
    }

    private func scoring(_ requested: Int, completed: Bool) -> [String: Any] {
        let seconds = completed || phase == .final ? 0 : phase == .live ? 1_800 : 3_600
        let pairs = requested == 1 ? [["0001", "0002"], ["0003", "0004"]] : [["0001", "0003"], ["0002", "0004"]]
        return ["week": String(requested), "matchup": pairs.map { pair in
            ["franchise": pair.enumerated().map { index, team -> [String: Any] in
                let ids = rosters[team] ?? []
                let starting = starters[requested]?[team] ?? []
                let rows = ids.map { id -> [String: String] in
                    let points = seconds == 3_600 ? 0 : requested * 5 + (Int(id)! % 10) + correction
                    return ["id": id, "status": starting.contains(id) ? "starter" : "nonstarter",
                        "gameSecondsRemaining": String(seconds), "score": String(points)]
                }
                let total = rows.filter { $0["status"] == "starter" }.reduce(0) { $0 + Int($1["score"]!)! }
                return ["id": team, "isHome": index == 1 ? "1" : "0", "score": String(total),
                    "playersYetToPlay": seconds == 3_600 ? "9" : "0", "players": ["player": rows]]
            }]
        }]
    }

    func send(_ request: URLRequest, owner: String) throws -> MFLHTTPResponse {
        func values(_ query: String?) -> [String: String] {
            var components = URLComponents(); components.percentEncodedQuery = query
            return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        }
        let query = values(request.url?.query)
        let form = values(String(data: request.httpBody ?? Data(), encoding: .utf8)?.replacingOccurrences(of: "+", with: "%20"))
        let type = query["TYPE"] ?? form["TYPE"] ?? "status"
        requestCounts["\(owner):\(type)", default: 0] += 1
        if offline.contains(owner) { throw URLError(.notConnectedToInternet) }
        if expired.contains(owner), type == "myleagues" { throw MFLCoreError.unauthorized("Synthetic session expiry") }
        func response(_ value: [String: Any]) throws -> MFLHTTPResponse {
            MFLHTTPResponse(data: try JSONSerialization.data(withJSONObject: value), statusCode: 200, url: request.url)
        }
        if request.url?.path.contains("mfl_status") == true {
            return try response(["mfl_status": ["year": "2026", "weeks": ["CurrentWeek": week,
                "LineupWeek": week, "CompletedWeek": phase == .final ? week : week - 1, "LiveScoringWeek": week]]])
        }
        if request.httpMethod == "POST" {
            writes.append((owner, type, week))
            switch type {
            case "lineup":
                guard phase == .pregame, Int(form["W"] ?? "") == week else { throw MFLCoreError.invalidRequest("Synthetic lineup deadline passed") }
                starters[week]?[owner] = Set((form["STARTERS"] ?? "").split(separator: ",").map(String.init))
            case "blindBidWaiverRequest":
                let round = Int(form["ROUND"] ?? "")!
                if let picks = form["PICKS"], !picks.isEmpty { queues[owner, default: [:]][round] = picks }
                else { queues[owner]?[round] = nil }
            case "tradeProposal":
                offers.append(["trade_id": String(nextID), "offeringteam": owner, "offeredto": form["OFFEREDTO"]!,
                    "will_give_up": form["WILL_GIVE_UP"]!, "will_receive": form["WILL_RECEIVE"]!,
                    "comments": form["COMMENTS"] ?? "", "expires": form["EXPIRES"]!])
                nextID += 1
            case "tradeResponse":
                let offer = offers.first { $0["trade_id"] == form["TRADE_ID"] }!
                if form["RESPONSE"] == "accept" {
                    let sender = offer["offeringteam"]!, recipient = offer["offeredto"]!
                    let give = offer["will_give_up"]!.split(separator: ",").map(String.init)
                    let receive = offer["will_receive"]!.split(separator: ",").map(String.init)
                    rosters[sender]?.removeAll { give.contains($0) }; rosters[sender]?.append(contentsOf: receive)
                    rosters[recipient]?.removeAll { receive.contains($0) }; rosters[recipient]?.append(contentsOf: give)
                    activity.append(["id": "t\(nextID)", "type": "TRADE", "franchise": sender, "franchise2": recipient,
                        "franchise1_gave_up": give.joined(separator: ","), "franchise2_gave_up": receive.joined(separator: ","),
                        "timestamp": String(Int(Date().timeIntervalSince1970))]); nextID += 1
                }
                offers.removeAll { $0["trade_id"] == form["TRADE_ID"] }
            case "messageBoard":
                let thread = form["THREAD"] ?? "thread-\(nextID)"
                if let subject = form["SUBJECT"] { subjects[thread] = subject }
                posts[thread, default: []].append(["id": "post-\(nextID)", "franchise_id": owner,
                    "body": form["BODY"]!, "timestamp": String(Int(Date().timeIntervalSince1970))]); nextID += 1
            default: throw MFLCoreError.invalidRequest("Unexpected synthetic write: \(type)")
            }
            if failAfterSave.remove(type) != nil { throw URLError(.timedOut) }
            return try response(["status": "OK"])
        }
        let requested = Int(query["W"] ?? "") ?? week
        switch type {
        case "myleagues": return try response(["leagues": ["league": [["league_id": "41333", "franchise_id": owner,
            "url": "https://www45.myfantasyleague.com/2026/home/41333"]]]])
        case "league": return try response(["league": ["id": "41333", "name": "Synthetic Four", "startWeek": "1", "precision": "2",
            "partialLineupAllowed": "No", "bestLineup": "No", "lockout": "No", "bbidConditional": "Yes", "currentWaiverType": "BBID_FCFS",
            "maxWaiverRounds": "8", "bbidIncrement": "1", "bbidMinimum": "0", "bbidSeasonLimit": "100",
            "starters": ["count": "9", "position": [["name": "QB", "limit": "1"], ["name": "RB", "limit": "2-4"],
                ["name": "WR", "limit": "3-5"], ["name": "TE", "limit": "1-3"]]],
            "franchises": ["franchise": Self.teams.enumerated().map { index, team in
                ["id": team, "name": "Synthetic Team \(index + 1)", "owner_name": Self.owners[index], "bbidAvailableBalance": String(budgets[team]!)]
            }]]])
        case "players": return try response(["players": ["player": catalog]])
        case "rosters":
            let team = query["FRANCHISE"] ?? query["FRANCHISE_ID"] ?? owner
            return try response(["rosters": ["franchise": ["id": team, "player": (rosters[team] ?? []).map { ["id": $0, "status": "ROSTER"] }]]])
        case "playerRosterStatus":
            return try response(["playerRosterStatuses": ["playerStatus": (rosters[owner] ?? []).map { id in
                ["id": id, "roster_franchise": [["id": owner, "status": starters[requested]?[owner]?.contains(id) == true ? "S" : "NS"]]] as [String: Any]
            }]])
        case "projectedScores": return try response(["projectedScores": ["week": String(requested), "playerScore": catalog.map {
            ["id": $0["id"]!, "score": String(requested * 10 + Int($0["id"]!)! % 10)]
        }]])
        case "liveScoring": return try response(["liveScoring": scoring(requested, completed: requested < week)])
        case "weeklyResults": return try response(["weeklyResults": scoring(requested, completed: true)])
        case "leagueStandings": return try response(["leagueStandings": ["franchise": Self.teams.enumerated().map { index, team in
            ["id": team, "h2hw": String(index.isMultiple(of: 2) ? max(0, week - 1) : 0), "h2hl": "0", "pf": String(week * 80)]
        }]])
        case "freeAgents":
            let owned = Set(rosters.values.flatMap { $0 })
            return try response(["freeAgents": ["leagueUnit": ["unit": "LEAGUE", "player": catalog.filter { !owned.contains($0["id"]!) }.map { ["id": $0["id"]!] }]]])
        case "pendingWaivers": return try response(["pendingWaivers": ["waiverRequest": (queues[owner] ?? [:]).sorted { $0.key < $1.key }.map {
            ["round": String($0.key), "picks": $0.value, "franchise_id": owner]
        }]])
        case "calendar": return try response(["calendar": ["event": []]])
        case "transactions": return try response(["transactions": ["transaction": activity]])
        case "assets": return try response(["assets": ["franchise": Self.teams.map { team in
            ["id": team, "players": ["player": (rosters[team] ?? []).map { ["id": $0] }],
             "blindBiddingDollars": ["amount": String(budgets[team]!)] ] as [String: Any]
        }]])
        case "pendingTrades": return try response(["pendingTrades": ["pendingTrade": offers.filter { $0["offeringteam"] == owner || $0["offeredto"] == owner }]])
        case "messageBoard": return try response(["messageBoard": ["thread": subjects.keys.sorted().map { id in
            ["id": id, "subject": subjects[id]!, "lastPostBy": posts[id]!.last!["franchise_id"]!]
        }]])
        case "messageBoardThread":
            let id = query["THREAD"]!
            return try response(["messageBoardThread": ["id": id, "subject": subjects[id] ?? "", "message": posts[id] ?? []]])
        default: throw MFLCoreError.invalidRequest("Unexpected synthetic read: \(type)")
        }
    }
}

private struct SyntheticManagerTransport: MFLHTTPTransport {
    let league: TwoWeekLeague
    let owner: String
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse { try await league.send(request, owner: owner) }
}

@MainActor
struct TwoWeekSimulationTests {
    private struct Manager {
        let number: Int
        let store = MemoryPrivateStore()
        var id: String { String(format: "%04d", number) }
        @MainActor func open(_ league: TwoWeekLeague) async throws -> (AppModel, LiveMFLRepository) {
            try store.encode(SavedSession(cookie: "synthetic-only-\(id)", season: 2026, leagueID: "41333", franchiseID: id), key: "session")
            let repository = LiveMFLRepository(privateStore: store, transport: SyntheticManagerTransport(league: league, owner: id), requestInterval: .zero)
            let model = AppModel(repository: repository, privateStore: store, foregroundRefreshInterval: 0)
            await model.restoreSession()
            #expect(model.phase == .signedIn)
            #expect(model.workspace?.franchiseID == id)
            #expect(model.canEditLineup && !model.isBusy && !model.isRestoringSession)
            return (model, repository)
        }
    }

    @Test("Four synthetic managers complete two game weeks through production app models and API decoding")
    func twoGameWeeks() async throws {
        let league = TwoWeekLeague()
        let managers = (1...4).map { Manager(number: $0) }
        var sessions: [(AppModel, LiveMFLRepository)] = []
        for manager in managers { sessions.append(try await manager.open(league)) }

        for week in 1...2 {
            await league.advance(week: week, phase: .pregame)
            for (index, manager) in managers.enumerated() {
                let model = sessions[index].0
                await model.refreshForForeground()
                #expect(model.selectedWeek == week && model.lineup.week == week && model.scores.week == week)
                #expect(model.lineupValidationMessage == nil)
                #expect(model.standings.count == 4 && model.standings.allSatisfy { $0.ownerName != nil })
                let matchup = try #require(model.scores.matchups.first { $0.away.id == manager.id || $0.home.id == manager.id })
                let own = matchup.away.id == manager.id ? matchup.away : matchup.home
                #expect(own.starters.filter { $0.lineupSlot == "FLEX" }.count == 2)
                #expect(own.starters.allSatisfy { $0.projectedPoints != nil })

                let flex = try #require(model.lineup.startingSlots.first { $0.isFlex })
                let replacement = try #require(model.replacementRequest(for: flex.id))
                #expect(Set(model.replacementPositions(for: replacement)) == ["RB", "WR", "TE"])
                let candidate = try #require(model.replacementCandidates(for: replacement).first { $0.position == "WR" })
                #expect(model.replaceStarter(replacement, with: candidate.id))
                let reviewed = model.lineup
                #expect(await model.submitLineup(reviewing: reviewed) != nil)
                #expect(await league.saved(manager.id, week: week) == Set(reviewed.starters.map(\.id)))

                // Distinct personal pickup; exercise both $0 and positive bids.
                let pickup = try #require(model.waivers.candidates.first { $0.id == TwoWeekLeague.freeAgent(week, manager.number) })
                let dropID = week == 1 ? TwoWeekLeague.player(manager.number, 12) : TwoWeekLeague.freeAgent(1, manager.number)
                model.upsertClaim(WaiverClaim(player: pickup, bid: index.isMultiple(of: 2) ? 5 : 0,
                    dropPlayerID: dropID, dropPlayerName: "Synthetic bench TE", round: 1, priority: 1))
                if manager.number == 2 {
                    let alternative = try #require(model.waivers.candidates.first { $0.id != pickup.id && $0.id.hasPrefix("900") })
                    model.upsertClaim(WaiverClaim(player: alternative, bid: 0, dropPlayerID: dropID,
                        dropPlayerName: "Synthetic bench TE", round: 1, priority: 2))
                    model.moveClaims(inRound: 1, from: IndexSet(integer: 1), to: 0)
                    #expect(model.waivers.claims.first?.player.id == alternative.id)
                    model.moveClaims(inRound: 1, from: IndexSet(integer: 0), to: 2)
                    model.upsertClaim(WaiverClaim(player: alternative, bid: 0, dropPlayerID: dropID,
                        dropPlayerName: "Synthetic bench TE", round: 2, priority: 1))
                }
                #expect(await model.submitWaivers())
                #expect(!model.hasWaiverChanges)
                if manager.number == 2 {
                    model.removeClaims(inRound: 2, at: IndexSet(integer: 0))
                    #expect(await model.submitWaivers())
                    let savedQueue = try await sessions[index].1.loadWaivers()
                    #expect(savedQueue.claims.count == 2 && savedQueue.claims.allSatisfy { $0.round == 1 })
                    #expect(savedQueue.claims.first?.player.id == pickup.id)
                }
                model.saveBoardDraft(subject: "Week \(week) · \(manager.id)", body: "Synthetic private draft", threadID: nil)
            }

            // Casey sends; Avery receives, reviews, and accepts. Both see the same server offer.
            let trader = sessions[2].0.transactions
            await trader.refresh()
            let give = TwoWeekLeague.player(week == 1 ? 3 : 1, 13)
            let receive = TwoWeekLeague.player(week == 1 ? 1 : 3, 13)
            let proposal = TradeDraft(partnerID: "0001", giving: [give], receiving: [receive], comments: "Synthetic week \(week) trade")
            #expect(await trader.perform(.propose(proposal)))
            let receiver = TransactionsModel(repository: sessions[0].1, workspace: sessions[0].0.workspace, privateStore: managers[0].store)
            await receiver.refresh()
            let offer = try #require(receiver.incoming.first)
            #expect(offer.giving.map(\.id) == [give] && offer.receiving.map(\.id) == [receive])
            #expect(await receiver.perform(.respond(offer, .accept, comments: "")))
            #expect(receiver.incoming.isEmpty && receiver.pending == nil)

            // Riley loses the post acknowledgement after the server saves it.
            await league.loseNextAcknowledgement("messageBoard")
            #expect(await sessions[3].0.post(subject: "Week \(week) discussion", body: "Synthetic week \(week) hello"))
            let board = try await sessions[0].1.loadBoard()
            let thread = try #require(board.first { $0.subject == "Week \(week) discussion" })
            #expect(await sessions[0].0.post(subject: nil, body: "Synthetic reply", threadID: thread.id))
            #expect(try await sessions[3].1.loadThread(id: thread.id).posts.count == 2)

            await league.processWaivers()
            // Reopen recreates private client state, just as next-day use does.
            for (index, manager) in managers.enumerated() {
                sessions[index] = try await manager.open(league)
                let model = sessions[index].0
                #expect(model.waivers.claims.isEmpty && model.waivers.minimumBid == 0)
                #expect(model.lineup.players.contains { $0.id == TwoWeekLeague.freeAgent(week, manager.number) })
                #expect(model.waivers.availableBudget == Decimal(100 - (index.isMultiple(of: 2) ? 5 * week : 0)))
                if index != 3 { #expect(model.boardDraft(threadID: nil).body == "Synthetic private draft") }
                await model.transactions.refreshActivity()
                #expect(model.transactions.activity.contains { $0.isTrade })
                #expect(model.transactions.activity.contains { $0.title == "Blind-bid waiver" })
            }

            await league.advance(week: week, phase: .live)
            for (index, manager) in managers.enumerated() {
                let model = sessions[index].0
                await model.refreshAll()
                #expect(model.scores.isLive)
                #expect(model.lineup.players.allSatisfy { $0.isLocked })
                #expect(model.replacementRequest(for: model.lineup.starters[0].id) == nil)
                #expect(model.scores.matchups.allSatisfy { $0.away.score > 0 && $0.home.score > 0 })
                // Repeated foreground use retains drafts while an interrupted refresh keeps scores.
                if manager.number == 4 {
                    let before = model.scores
                    await league.disconnect(manager.id, true)
                    await model.refreshScores()
                    #expect(model.scoreRefreshError != nil && model.scores.lastUpdated == before.lastUpdated)
                    #expect(!model.isLoadingScores && !model.isRefreshing)
                    await league.disconnect(manager.id, false)
                    await model.refreshScores()
                    #expect(model.scoreRefreshError == nil)
                }
            }

            await league.advance(week: week, phase: .final)
            for session in sessions {
                await session.0.refreshForForeground()
                #expect(!session.0.scores.isLive)
                #expect(session.0.scores.matchups.allSatisfy { $0.away.starters.filter { $0.lineupSlot == "FLEX" }.count == 2 })
            }
            print("[Synthetic two-week test] Week \(week): 4 managers completed lineup/FLEX, bids, scores/locks/finals, trade, board, and reconnection journeys")
        }

        // Historical week selection survives a subsequent refresh; corrections are reread.
        let casual = sessions[0].0
        await casual.changeWeek(to: 1)
        let oldScore = try #require(casual.scores.matchups.first?.away.score)
        await league.correctScores()
        await casual.refreshForForeground()
        #expect(casual.selectedWeek == 1 && casual.currentWeek == 2)
        let correctedScore = try #require(casual.scores.matchups.first?.away.score)
        #expect(correctedScore > oldScore)

        // Session expiry cannot erase or disclose another manager's private draft.
        let commuter = sessions[3].0
        commuter.saveBoardDraft(subject: "Keep", body: "Riley only", threadID: nil)
        await league.expire("0004", true)
        await commuter.refreshForForeground()
        #expect(commuter.phase == .onboarding)
        await league.expire("0004", false)
        let reopened = try await managers[3].open(league).0
        #expect(reopened.boardDraft(threadID: nil).body == "Riley only")
        #expect(casual.boardDraft(threadID: nil).body != "Riley only")
        #expect(await league.countWrites("lineup") == 8)
        #expect(await league.countWrites("blindBidWaiverRequest") == 12)
        #expect(await league.countWrites("tradeProposal") == 2)
        #expect(await league.countWrites("tradeResponse") == 2)
        #expect(await league.countWrites("messageBoard") == 4) // Lost acknowledgements never duplicate posts.
    }
}
