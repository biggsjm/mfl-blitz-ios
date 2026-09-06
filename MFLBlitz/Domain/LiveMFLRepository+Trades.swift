import Foundation
import MFLCore

extension LiveMFLRepository {
    func loadTrades() async throws -> TradeSnapshot {
        let (client, league, workspace) = try requireSession()
        async let pendingTask = client.pendingTrades(franchiseID: workspace.franchiseID)
        async let assetsTask = client.tradeAssets()
        async let catalogTask = client.players()
        let (pending, assets, catalog) = try await (pendingTask, assetsTask, catalogTask)
        let players = Dictionary(grouping: catalog.players, by: \.id).compactMapValues { $0.count == 1 ? $0[0] : nil }
        let teams = assets.franchises.compactMap { owned -> TradeTeam? in
            guard let franchise = league.franchises.first(where: { $0.id == owned.id }) else { return nil }
            return TradeTeam(id: owned.id, name: cleanText(franchise.name), abbreviation: franchise.abbreviation ?? owned.id,
                artworkURLs: TeamArtworkURLPolicy.candidates(icon: franchise.iconURL, logo: franchise.logoURL),
                assets: owned.codes.map { tradeAsset($0, players: players, league: league, season: workspace.season) },
                blindBidBalance: owned.blindBidBalance)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard teams.contains(where: { $0.id == workspace.franchiseID }) else {
            throw RepositoryError.server("MFL did not return your tradable assets. Reconnect before trading.")
        }
        let snapshot = TradeSnapshot(teams: teams, offers: pending.offers.map {
            tradeOffer($0, assets: assets, players: players, league: league, workspace: workspace)
        }.filter { $0.offeredTo == workspace.franchiseID || $0.offeredBy == workspace.franchiseID || $0.offeredBy == nil }, updatedAt: Date())
        #if DEBUG
        print("[MFL trades] decoded teams=\(teams.count) assets=\(teams.reduce(0) { $0 + $1.assets.count }) pending=\(snapshot.offers.count)")
        #endif
        return snapshot
    }

    private func tradeOffer(_ raw: MFLPendingTrade, assets: MFLTradeAssets, players: [String: MFLPlayer],
                            league: MFLLeague, workspace: LeagueWorkspace) -> TradeOffer {
        var proposer = raw.offeredBy
        if proposer == nil {
            // Some MFL feeds omit the proposer ID. Resolve only when every
            // non-cash asset identifies exactly one current owner; never infer
            // direction from text, list order, or the signed-in franchise alone.
            let codes = raw.giving.filter { !$0.hasPrefix("BB_") }
            let owners = assets.franchises.filter { owner in !codes.isEmpty && codes.allSatisfy(owner.owns) }
            if owners.count == 1 { proposer = owners[0].id }
        }
        if proposer == raw.offeredTo || !league.franchises.contains(where: { $0.id == proposer }) { proposer = nil }
        return TradeOffer(id: raw.id, offeredBy: proposer, offeredTo: raw.offeredTo,
            giving: raw.giving.map { tradeAsset($0, players: players, league: league, season: workspace.season) },
            receiving: raw.receiving.map { tradeAsset($0, players: players, league: league, season: workspace.season) },
            comments: cleanText(raw.comments), expires: raw.expires, timestamp: raw.timestamp, status: raw.status)
    }

    private nonisolated func tradeAsset(_ code: String, players: [String: MFLPlayer], league: MFLLeague, season: Int) -> TradeAsset {
        guard MFLTradeAssetCode.isSupported(code) else {
            return TradeAsset(id: code, name: "Unrecognized asset: \(code)", detail: "Review the complete offer on MFL", kind: .unknown)
        }
        if let amount = MFLTradeAssetCode.blindBidAmount(code) {
            return TradeAsset(id: code, name: "\(amount.formatted(.currency(code: "USD"))) blind-bid budget", detail: "FAAB dollars", kind: .budget)
        }
        let parts = code.split(separator: "_").map(String.init)
        if parts.first == "DP", parts.count == 3, let round = Int(parts[1]), let pick = Int(parts[2]), round < 1_000, pick < 1_000 {
            return TradeAsset(id: code, name: "\(season) · Round \(round + 1), pick \(pick + 1)", detail: "Current-year draft pick", kind: .pick)
        }
        if parts.first == "FP", parts.count == 4 {
            let original = league.franchises.first { $0.id == parts[1] }
            return TradeAsset(id: code, name: "\(parts[2]) · Round \(parts[3])", detail: "Originally \(cleanText(original?.name ?? parts[1]))", kind: .pick)
        }
        if let player = players[code] {
            return TradeAsset(id: code, name: cleanText(player.displayName),
                detail: [player.position, player.nflTeam].compactMap { $0 }.joined(separator: " · "), kind: .player)
        }
        return TradeAsset(id: code, name: "Player \(code)", detail: "Name unavailable · review on MFL", kind: .unknown)
    }

    func pendingTradeAction() async throws -> PendingTradeAction? {
        let (_, _, workspace) = try requireSession()
        return try privateStore.decode(PendingTradeAction.self, key: "trade.pending.\(workspace.storageScope)")
    }

    func performTrade(_ command: TradeCommand) async throws -> TradeReceipt {
        guard !tradeMutationInFlight else { throw RepositoryError.server("A trade action is already being checked.") }
        tradeMutationInFlight = true
        defer { tradeMutationInFlight = false }
        let (client, _, workspace) = try requireSession()
        let key = "trade.pending.\(workspace.storageScope)"
        guard try await pendingTradeAction() == nil else { throw RepositoryError.server("Check your unconfirmed trade action before sending another.") }
        let fresh = try await loadTrades()
        try validateTrade(command, in: fresh, owner: workspace.franchiseID)
        guard try requireSession().2.storageScope == workspace.storageScope else { throw RepositoryError.missingSession }
        var marker = PendingTradeAction(command: command, existingIDs: Set(fresh.offers.map(\.id)))
        // If durable storage fails, nothing is sent. A timeout/relaunch must not
        // turn into a duplicate offer or a second accept/reject request.
        try privateStore.encode(marker, key: key)
        do {
            switch command {
            case .propose(let draft):
                try await client.proposeTrade(to: draft.partnerID, giving: draft.giving.sorted(), receiving: draft.receiving.sorted(),
                    comments: draft.comments.trimmingCharacters(in: .whitespacesAndNewlines), expires: draft.expires,
                    actingFranchiseID: workspace.franchiseID)
            case .respond(let offer, let response, let comments):
                try await client.respondToTrade(id: offer.id, response: response, comments: comments, actingFranchiseID: workspace.franchiseID)
            }
            marker.acknowledgedByMFL = true
            try privateStore.encode(marker, key: key)
            return try await reconcileTradeAction()
        } catch {
            // Do not replay a write even if the HTTP response or readback failed.
            return TradeReceipt(confirmed: false, message: "This trade action is not confirmed. It was not sent again. Check MFL before taking another action.")
        }
    }

    private func validateTrade(_ command: TradeCommand, in snapshot: TradeSnapshot, owner: String) throws {
        func owns(_ codes: Set<String>, teamID: String) -> Bool {
            guard let team = snapshot.teams.first(where: { $0.id == teamID }), !codes.isEmpty,
                  codes.filter({ $0.hasPrefix("BB_") }).count <= 1 else { return false }
            return codes.allSatisfy { code in
                if let amount = MFLTradeAssetCode.blindBidAmount(code) { return amount > 0 && amount <= (team.blindBidBalance ?? -1) }
                return team.assets.contains { $0.id == code && $0.kind != .unknown }
            }
        }
        func current(_ offer: TradeOffer) throws {
            guard let value = snapshot.offers.first(where: { $0.id == offer.id }), value.matchesTerms(of: offer), value.isActionable else {
                throw RepositoryError.server("This offer changed, expired, or is no longer pending. Refresh and review it again.")
            }
        }
        switch command {
        case .propose(let draft):
            guard draft.partnerID != owner, owns(draft.giving, teamID: owner), owns(draft.receiving, teamID: draft.partnerID),
                  draft.expires > Date(), draft.comments.count <= 1_000 else {
                throw RepositoryError.server("A selected asset, owner, budget, or expiration changed. Refresh and review your draft; nothing was sent.")
            }
            if let original = draft.countering {
                try current(original)
                guard original.offeredTo == owner, original.offeredBy == draft.partnerID, draft.acknowledgesOriginalStaysOpen else {
                    throw RepositoryError.server("Review the original offer and acknowledge that it remains open before sending a counteroffer.")
                }
            }
            guard !snapshot.offers.contains(where: { $0.offeredBy == owner && $0.offeredTo == draft.partnerID
                && Set($0.giving.map(\.id)) == draft.giving && Set($0.receiving.map(\.id)) == draft.receiving && !$0.isExpired }) else {
                throw RepositoryError.server("You already have this offer pending with that team. Review it under Sent.")
            }
        case .respond(let offer, let response, let comments):
            try current(offer)
            guard comments.count <= 1_000,
                  (response == .revoke ? offer.offeredBy == owner : offer.offeredTo == owner) else {
                throw RepositoryError.server("Only the recipient can accept or decline, and only the sender can withdraw this offer.")
            }
            if response == .accept {
                guard let sender = offer.offeredBy,
                      owns(Set(offer.giving.map(\.id)), teamID: sender), owns(Set(offer.receiving.map(\.id)), teamID: owner) else {
                    throw RepositoryError.server("The assets in this offer are no longer available from the same teams. Nothing was accepted.")
                }
            }
        }
    }

    func reconcileTradeAction() async throws -> TradeReceipt {
        let (_, _, workspace) = try requireSession()
        guard let pending = try await pendingTradeAction() else { return TradeReceipt(confirmed: true, message: "No trade action needs verification.") }
        let fresh = try await loadTrades()
        let confirmed: Bool
        let message: String
        switch pending.command {
        case .propose(let draft):
            confirmed = fresh.offers.contains { !pending.existingIDs.contains($0.id) && $0.offeredBy == workspace.franchiseID
                && $0.offeredTo == draft.partnerID && Set($0.giving.map(\.id)) == draft.giving
                && Set($0.receiving.map(\.id)) == draft.receiving
                && $0.comments == cleanText(draft.comments.trimmingCharacters(in: .whitespacesAndNewlines))
                && $0.expires.map { Int($0.timeIntervalSince1970) == Int(draft.expires.timeIntervalSince1970) } == true }
            message = draft.countering == nil ? "MFL confirmed your trade offer." : "MFL confirmed your counteroffer. The original offer remains open; decline it separately if you no longer want it."
        case .respond(let offer, let response, _):
            // Disappearance alone cannot prove an accept vs a rejection/expiry.
            confirmed = pending.acknowledgedByMFL && !fresh.offers.contains { $0.id == offer.id }
            switch response {
            case .accept: message = "MFL confirmed your acceptance. The trade may still require league approval or processing; check Activity and your roster."
            case .reject: message = "MFL confirmed your decline."
            case .revoke: message = "MFL confirmed your withdrawal."
            }
        }
        if confirmed { try privateStore.remove("trade.pending.\(workspace.storageScope)") }
        return TradeReceipt(confirmed: confirmed, message: confirmed ? message : "MFL hasn’t confirmed the outcome yet. Check the trade on MFL; do not send it again.", snapshot: fresh)
    }

    func acknowledgeUnconfirmedTrade() async throws {
        guard !tradeMutationInFlight else { throw RepositoryError.server("Wait for the current trade check to finish.") }
        let (_, _, workspace) = try requireSession()
        try privateStore.remove("trade.pending.\(workspace.storageScope)")
    }

    func loadTransactionActivity() async throws -> [TransactionActivity] {
        let (client, league, workspace) = try requireSession()
        let value = try await client.transactionActivity()
        let catalog = try await client.players()
        let players = Dictionary(grouping: catalog.players, by: \.id).compactMapValues { $0.count == 1 ? $0[0] : nil }
        guard let container = value.objectValue?["transactions"] else { throw MFLCoreError.invalidResponse }
        if container.stringValue == "", container.objectValue == nil { return [] }
        guard let object = container.objectValue else { throw MFLCoreError.invalidResponse }
        let rows = object["transaction"]?.arrayValue ?? []
        let activity = rows.enumerated().compactMap { index, value -> TransactionActivity? in
            guard let fields = value.objectValue, let type = fields["type"]?.stringValue else { return nil }
            let titles = ["TRADE": "Trade", "WAIVER": "Waiver", "BBID_WAIVER": "Blind-bid waiver", "FREE_AGENT": "Free-agent move", "IR": "Injured reserve", "TAXI": "Taxi squad"]
            guard let title = titles[type] else { return nil }
            let team = league.franchises.first { $0.id == (fields["franchise"]?.stringValue ?? fields["franchise1"]?.stringValue) }
            let description = cleanText(fields["description"]?.stringValue ?? "")
            let details = TransactionDetails(type: type, fields: fields)
            let moves = details.moves.map { move in
                TransactionActivityMove(label: move.label, names: move.codes.map {
                    tradeAsset($0, players: players, league: league, season: workspace.season).name
                }.joined(separator: ", "))
            }
            return TransactionActivity(id: fields["id"]?.stringValue ?? "\(index)-\(fields["timestamp"]?.stringValue ?? "")",
                title: title, detail: description.isEmpty ? "Full details are available on MFL." : description,
                date: fields["timestamp"]?.stringValue.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)), isTrade: type == "TRADE",
                teamName: team.map { cleanText($0.name) },
                partnerName: details.partnerID.map { partner in cleanText(league.franchises.first { $0.id == partner }?.name ?? "Team \(partner)") },
                bid: details.bid, moves: moves)
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        #if DEBUG
        print("[MFL transactions] activity records=\(activity.count)")
        #endif
        return activity
    }
}
