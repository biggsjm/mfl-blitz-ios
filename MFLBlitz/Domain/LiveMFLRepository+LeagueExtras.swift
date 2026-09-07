import Foundation
import MFLCore

extension LiveMFLRepository {
    func loadTradingBlock(refresh: Bool) async throws -> TradingBlockSnapshot {
        let (client, league, workspace) = try requireSession()
        async let blockTask = client.tradingBlockSnapshot(refreshPolicy: refresh ? .reloadIgnoringCache : .useCache)
        async let assetsTask = client.tradeAssets()
        async let playersTask = client.players()
        let ((block, fetchedAt), assets, players) = try await (blockTask, assetsTask, playersTask)
        try Task.checkCancellation()
        guard try requireSession().2.storageScope == workspace.storageScope else { throw CancellationError() }
        let teams = assets.franchises.compactMap { owned -> TradeTeam? in
            guard let franchise = league.franchises.first(where: { $0.id == owned.id }) else { return nil }
            return TradeTeam(id: owned.id, name: cleanText(franchise.name), abbreviation: franchise.abbreviation ?? owned.id,
                artworkURLs: TeamArtworkURLPolicy.candidates(icon: franchise.iconURL, logo: franchise.logoURL),
                assets: owned.codes.map { tradeAsset($0, players: players.playersByID, league: league, season: workspace.season) },
                blindBidBalance: owned.blindBidBalance, ownerName: cleanText(franchise.ownerName ?? ""))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // Include assets on stale listings even if their owner changed. They are
        // display-only and fresh ownership preflight will reject a new proposal.
        var displayTeams = teams
        for listing in block.listings {
            guard let index = displayTeams.firstIndex(where: { $0.id == listing.id }) else { continue }
            let missing = listing.codes.subtracting(Set(displayTeams[index].assets.map(\.id)))
            for code in missing {
                var asset = tradeAsset(code, players: players.playersByID, league: league, season: workspace.season)
                asset.detail += " · Check current ownership"
                asset.kind = .unknown
                displayTeams[index].assets.append(asset)
            }
        }
        return TradingBlockSnapshot(scope: workspace.storageScope, listings: block.listings, teams: displayTeams, fetchedAt: fetchedAt)
    }

    func pendingTradingBlock() async throws -> PendingTradingBlock? {
        let (_, _, workspace) = try requireSession()
        return try privateStore.decode(PendingTradingBlock.self, key: "block.pending.\(workspace.storageScope)")
    }

    func publishTradingBlock(_ draft: TradingBlockDraft) async throws -> TradingBlockReceipt {
        try beginRosterMutation()
        defer { rosterMutationInFlight = false }
        let (client, _, workspace) = try requireSession()
        guard try await pendingTradingBlock() == nil else { throw RepositoryError.server("Check the previous publication before changing your block.") }
        let memberships = try await client.myLeagues(includeFranchiseNames: false, refreshPolicy: .reloadIgnoringCache)
        let matching = memberships.leagues.filter { $0.leagueID == workspace.leagueID }
        guard matching.count == 1, matching[0].franchiseID == workspace.franchiseID else { throw RepositoryError.missingSession }
        let fresh = try await loadTradingBlock(refresh: true)
        try TradingBlockPolicy.validate(draft, fresh: fresh, ownerID: workspace.franchiseID)
        let abilities = try await client.abilities(refreshPolicy: .reloadIgnoringCache)
        guard TradingBlockPolicy.permits(abilities, ownerID: workspace.franchiseID),
              !draft.codes.contains(where: { $0.hasPrefix("FP_") }) || TradingBlockPolicy.permits(abilities, ownerID: workspace.franchiseID, ability: "FDP_TRADES") else {
            throw RepositoryError.server("Trading these assets is unavailable for your franchise right now.")
        }
        guard try requireSession().2.storageScope == workspace.storageScope else { throw RepositoryError.missingSession }
        let expected = MFLTradingBlockListing(id: workspace.franchiseID, codes: draft.codes,
            lookingFor: draft.isRemoval ? "" : draft.lookingFor.trimmingCharacters(in: .whitespacesAndNewlines))
        try privateStore.encode(PendingTradingBlock(scope: workspace.storageScope, intended: expected), key: "block.pending.\(workspace.storageScope)")
        do {
            if draft.isRemoval { try await client.removeTradingBlock() }
            else { try await client.publishTradingBlock(codes: expected.codes, lookingFor: expected.lookingFor) }
            return try await reconcileTradingBlock()
        } catch {
            // The request may have reached MFL. Keep the durable marker and do
            // not retry even for cancellation, failed acknowledgement or 429.
            return TradingBlockReceipt(confirmed: false, snapshot: nil)
        }
    }

    func reconcileTradingBlock() async throws -> TradingBlockReceipt {
        let (_, _, workspace) = try requireSession()
        guard let pending = try await pendingTradingBlock(), pending.scope == workspace.storageScope else {
            return TradingBlockReceipt(confirmed: true, snapshot: nil)
        }
        let fresh = try await loadTradingBlock(refresh: true)
        guard try requireSession().2.storageScope == workspace.storageScope else { throw RepositoryError.missingSession }
        let listing = fresh.listings.first { $0.id == workspace.franchiseID }
        let removing = pending.intended.codes.isEmpty && pending.intended.lookingFor.isEmpty
        // MFL may omit an emptied owner or retain an explicitly empty row.
        // Only a successful, fully parsed fresh export can confirm absence.
        let confirmed = listing.map { $0.codes == pending.intended.codes && cleanText($0.lookingFor) == cleanText(pending.intended.lookingFor) } ?? removing
        if confirmed { try privateStore.remove("block.pending.\(workspace.storageScope)") }
        return TradingBlockReceipt(confirmed: confirmed, snapshot: fresh, removed: confirmed && removing)
    }

    func loadLeagueCalendar(refresh: Bool) async throws -> LeagueCalendarSnapshot {
        let (client, _, workspace) = try requireSession()
        let (source, date) = try await client.calendarOccurrences(refreshPolicy: refresh ? .reloadIgnoringCache : .useCache)
        try Task.checkCancellation()
        guard try requireSession().2.storageScope == workspace.storageScope else { throw CancellationError() }
        return LeagueCalendarSnapshot(scope: workspace.storageScope, source: source, fetchedAt: date)
    }
}
