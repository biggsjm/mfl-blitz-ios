import Foundation
import MFLCore

extension LiveMFLRepository {
    func pendingRosterAction() async throws -> PendingRosterAction? {
        let (_, _, workspace) = try requireSession()
        return try privateStore.decode(PendingRosterAction.self, key: "roster.pending.\(workspace.storageScope)")
    }
    func loadRosterActionContext() async throws -> RosterActionContext {
        try await loadRosterActionContext(refresh: false)
    }

    private func loadRosterActionContext(refresh: Bool) async throws -> RosterActionContext {
        let (client, _, workspace) = try requireSession()
        // Browsing reuses short-lived roster/permission and stable rules caches.
        // Confirming a mutation always bypasses them below.
        let policy: MFLRefreshPolicy = refresh ? .reloadIgnoringCache : .useCache
        let league = try await client.league(refreshPolicy: policy)
        let rosters = try await client.rosters(franchiseID: workspace.franchiseID, refreshPolicy: policy)
        let membership = try Self.uniqueMembership(rosters, owner: workspace.franchiseID)
        let capabilities = try await client.abilities(refreshPolicy: policy)
        let catalog = try await client.players()
        try validatePlayerToolsSession(client, workspace.storageScope)
        let supported = league.rostersPerPlayer == 1 && league.playerLimitUnit == "LEAGUE"
            && league.usesSalaries == false && league.usesContractYear == false
            && (league.rosterSize ?? 0) > 0
            && membership.values.allSatisfy { ["ROSTER", "INJURED_RESERVE"].contains($0) }
        var allowed = supported ? RosterAbilityPolicy.allowed(capabilities, ownerID: workspace.franchiseID) : []
        if !["FCFS", "BBID_FCFS"].contains(league.currentWaiverType ?? "") { allowed.remove(.add) }
        if (league.injuredReserveSize ?? 0) <= 0 { allowed.subtract([.reserve, .activate]) }
        let pending = try privateStore.decode(PendingRosterAction.self, key: "roster.pending.\(workspace.storageScope)")
        return RosterActionContext(scope: workspace.storageScope, ownerID: workspace.franchiseID,
            players: catalog.players.filter { membership[$0.id] != nil }.map { TeamPlayerMapper.identity($0, id: $0.id) },
            membership: membership, activeLimit: league.rosterSize ?? 0, irLimit: league.injuredReserveSize ?? 0,
            allowed: allowed, unavailableReason: supported
                ? "MFL hasn’t confirmed permission for this action. You can check it on MFL."
                : "Use MFL to manage this league’s roster format.", pending: pending)
    }

    static func uniqueMembership(_ response: MFLRosterCollection, owner: String) throws -> [String: String] {
        let matches = response.rosters.filter { $0.franchiseID == owner }
        guard matches.count == 1, let roster = matches.first,
              Set(roster.players.map(\.id)).count == roster.players.count,
              roster.players.allSatisfy({ !$0.id.isEmpty && $0.id.allSatisfy(\.isNumber) && $0.hasExplicitStatus }) else {
            throw RepositoryError.server("MFL did not return a complete, unique roster. Nothing was changed.")
        }
        return Dictionary(uniqueKeysWithValues: roster.players.map { ($0.id, $0.status.rawValue) })
    }

    func beginRosterMutation() throws {
        let (_, _, workspace) = try requireSession()
        guard !rosterMutationInFlight else { throw RepositoryError.server("Wait for the current roster change to finish.") }
        guard try privateStore.read("roster.pending.\(workspace.storageScope)") == nil else {
            throw RepositoryError.server("Check the unconfirmed roster change in My Team before making another change.")
        }
        rosterMutationInFlight = true
    }

    func performRosterAction(_ request: RosterActionRequest, reviewed: RosterActionContext) async throws -> RosterActionReceipt {
        try beginRosterMutation()
        defer { rosterMutationInFlight = false }
        let (client, _, workspace) = try requireSession()
        guard reviewed.scope == workspace.storageScope, reviewed.ownerID == workspace.franchiseID,
              !request.playerID.isEmpty, request.playerID.allSatisfy(\.isNumber) else { throw CancellationError() }
        let fresh = try await loadRosterActionContext(refresh: true)
        guard fresh.membership == reviewed.membership, fresh.activeLimit == reviewed.activeLimit,
              fresh.irLimit == reviewed.irLimit else {
            throw RepositoryError.server("Your roster or its limits changed. Close and review the move again; nothing was sent.")
        }
        if let problem = fresh.problem(for: request) { throw RepositoryError.server(problem) }
        if request.kind == .add {
            let pool = try await client.freeAgents(refreshPolicy: .reloadIgnoringCache)
            let status = try await client.playerRosterStatus(playerIDs: [request.playerID],
                franchiseID: workspace.franchiseID, refreshPolicy: .reloadIgnoringCache)
            let entries = status.statuses.filter { $0.id == request.playerID }
            guard pool.players.filter({ $0.id == request.playerID }).count == 1, entries.count == 1,
                  entries[0].canAddImmediately else {
                throw RepositoryError.server("This player is not confirmed available for an immediate add. Check the waiver options on MFL.")
            }
        }
        if request.kind == .reserve {
            let status = try await playerToolsSeasonStatus(client: client)
            let injuries = try await client.injuries(week: status.currentWeek, refreshPolicy: .reloadIgnoringCache)
            guard let injury = injuries.byPlayerID[request.playerID],
                  PlayerHealth(status: injury.status ?? "").qualifiesForNativeIR else {
                throw RepositoryError.server("This player is not listed as Out or IR. Check eligibility on MFL.")
            }
        }
        try validatePlayerToolsSession(client, workspace.storageScope)
        let marker = PendingRosterAction(scope: workspace.storageScope, request: request,
            expectedMembership: fresh.expectedMembership(after: request))
        try privateStore.encode(marker, key: "roster.pending.\(workspace.storageScope)")
        // A marker exists before the only POST. Every uncertain response is read
        // back; never replay an import after timeout, relaunch or cancellation.
        do {
            switch request.kind {
            case .add: _ = try await client.addDrop(addPlayerID: request.playerID, dropPlayerID: request.dropID)
            case .drop: _ = try await client.addDrop(addPlayerID: nil, dropPlayerID: request.playerID)
            case .reserve: _ = try await client.moveInjuredReserve(playerID: request.playerID, activate: false)
            case .activate: _ = try await client.moveInjuredReserve(playerID: request.playerID, activate: true, dropPlayerID: request.dropID)
            }
        } catch { /* Reconcile membership, not the transport acknowledgement. */ }
        try validatePlayerToolsSession(client, workspace.storageScope)
        return try await reconcileRosterAction()
    }

    func reconcileRosterAction() async throws -> RosterActionReceipt {
        let (client, _, workspace) = try requireSession()
        let key = "roster.pending.\(workspace.storageScope)"
        guard let marker = try privateStore.decode(PendingRosterAction.self, key: key) else {
            return RosterActionReceipt(confirmed: false, message: "No roster change is waiting for confirmation.")
        }
        let response = try await client.rosters(franchiseID: workspace.franchiseID, refreshPolicy: .reloadIgnoringCache)
        try validatePlayerToolsSession(client, workspace.storageScope)
        let membership = try Self.uniqueMembership(response, owner: workspace.franchiseID)
        guard marker.scope == workspace.storageScope, membership == marker.expectedMembership else {
            return RosterActionReceipt(confirmed: false, message: "This change isn’t confirmed. Check your roster on MFL before trying again.")
        }
        try privateStore.remove(key)
        return RosterActionReceipt(confirmed: true, message: "Roster updated")
    }

    func acknowledgeRosterAction() async throws {
        let (_, _, workspace) = try requireSession()
        guard !rosterMutationInFlight else { throw RepositoryError.server("Wait for the current roster change.") }
        try privateStore.remove("roster.pending.\(workspace.storageScope)")
    }
}
