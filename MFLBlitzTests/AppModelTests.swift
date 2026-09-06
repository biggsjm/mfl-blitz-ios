import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

@MainActor
struct AppModelTests {
    @Test("Preview mode opens Champion Hall")
    func previewMode() async {
        let model = AppModel(repository: DemoLeagueRepository())

        await model.continueInDemo()

        #expect(model.phase == .signedIn)
        #expect(model.workspace?.leagueName == "Champion Hall")
        #expect(model.scores.matchups.count == 6)
    }

    @Test("Preview matchups include position-by-position scoring")
    func previewMatchupPlayerScoring() throws {
        let matchup = try #require(SampleData.scores.featuredMatchup)

        #expect(matchup.away.starters.count == 9)
        #expect(matchup.home.starters.count == 9)
        #expect(Set(matchup.away.starters.map(\.position)).isSuperset(of: ["QB", "RB", "WR", "TE"]))
        #expect(!matchup.away.bench.isEmpty)
        #expect(matchup.away.players.allSatisfy { $0.livePoints != nil })
    }

    @Test("Lineup validation notices missing starters")
    func lineupValidation() {
        let model = AppModel(repository: DemoLeagueRepository())
        let starterID = model.lineup.starters[0].id

        model.toggleStarter(starterID)

        #expect(model.lineupValidationMessage == "Choose 1 more starter")
    }

    @Test("Fixed-position replacement picker includes eligible bench players and starters",
          arguments: ["QB", "RB", "WR", "TE"])
    func replacementPositions(position: String) throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let starter = try #require(model.lineup.starters.first { $0.position == position })
        let request = try #require(model.replacementRequest(for: starter.id))
        let candidates = model.replacementCandidates(for: request)
        #expect(!candidates.isEmpty)
        #expect(candidates.allSatisfy { $0.position == position && !$0.isLocked && $0.injuryStatus != .injuredReserve })
        #expect(!candidates.contains { $0.id == starter.id })
        #expect(model.lineup == SampleData.lineup) // Opening/canceling does not edit.
    }

    @Test("A replacement swaps both players atomically, preserves positions and clears a promoted tiebreaker")
    func replacementSwap() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let original = model.lineup
        let request = try #require(model.replacementRequest(for: "12620"))
        #expect(!model.replaceStarter(request, with: "15712")) // RB cannot replace QB.
        #expect(model.lineup == original)
        #expect(model.replaceStarter(request, with: "14056"))
        #expect(model.lineup.starters.count == original.starters.count)
        #expect(model.lineup.starters.map(\.position).sorted() == original.starters.map(\.position).sorted())
        #expect(model.lineup.starters.contains { $0.id == "14056" })
        #expect(model.lineup.bench.contains { $0.id == "12620" })
        #expect(model.lineup.serverStarterPlayerIDs == original.serverStarterPlayerIDs)
        #expect(model.lineup.tiebreakerPlayerIDs.isEmpty)
        #expect(model.starterValidationMessage == nil)
        #expect(model.lineupValidationMessage?.contains("tiebreaker") == true)
        #expect(model.hasLineupChanges)
        #expect(!model.replaceStarter(request, with: "14056")) // Stale/double tap.
    }

    @Test("Locked and reserve replacements are excluded, and missing projections do not hide eligible players")
    func replacementEligibility() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let request = try #require(model.replacementRequest(for: "14073"))
        let lockedIndex = try #require(model.lineup.players.firstIndex { $0.id == "15712" })
        model.lineup.players[lockedIndex].isLocked = true
        let missingIndex = try #require(model.lineup.players.firstIndex { $0.id == "16596" })
        model.lineup.players[missingIndex].projectedPoints = nil
        #expect(model.replacementCandidates(for: request).filter { !$0.isStarter }.map(\.id) == ["17047", "16596"])
        #expect(!model.replaceStarter(request, with: "15712"))
        #expect(!model.replaceStarter(request, with: "16222"))
        let otherStarter = try #require(model.lineup.players.first { $0.id == "13319" })
        #expect(model.replacementCandidates(for: request).contains { $0.id == otherStarter.id })
        // A kickoff while the picker is open must invalidate the outgoing player too.
        model.lineup.players[1].isLocked = true
        #expect(model.replacementCandidates(for: request).isEmpty)
        #expect(!model.replaceStarter(request, with: "17047"))
        #expect(model.replacementRequest(for: "14073") == nil)
    }

    @Test("Replacement actions recheck loading, conflicts, week, and edit access at selection time")
    func replacementStaleness() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let request = try #require(model.replacementRequest(for: "12620"))
        let original = model.lineup
        model.isLoadingLineup = true
        #expect(!model.replaceStarter(request, with: "14056"))
        model.isLoadingLineup = false
        model.isBusy = true
        #expect(!model.replaceStarter(request, with: "14056"))
        model.isBusy = false
        model.lineupConflict = "Updated on MFL"
        #expect(!model.replaceStarter(request, with: "14056"))
        model.lineupConflict = nil
        model.selectedWeek = 2
        model.lineup.week = 2
        #expect(!model.replaceStarter(request, with: "14056"))
        model.selectedWeek = 1
        model.lineup = original
        model.isDemo = false
        model.lineup.editState = .unavailable("Readback incomplete")
        #expect(!model.replaceStarter(request, with: "14056"))
        #expect(model.lineup.starters.map(\.id) == original.starters.map(\.id))
    }

    @Test("No eligible bench players leaves the starter unchanged")
    func noReplacements() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let request = try #require(model.replacementRequest(for: "12620"))
        model.lineup.players.removeAll { $0.id == "14056" }
        let original = model.lineup
        #expect(model.replacementCandidates(for: request).isEmpty)
        #expect(!model.replaceStarter(request, with: "14056"))
        #expect(model.lineup == original)
    }

    @Test("Connected lineup editing requires a complete MFL readback")
    func connectedLineupEditingGate() {
        let model = AppModel(repository: LiveMFLRepository())
        var lineup = SampleData.lineup
        lineup.editState = .unavailable("Incomplete lineup")
        model.lineup = lineup
        let starterID = lineup.starters[0].id

        model.toggleStarter(starterID)

        #expect(!model.canEditLineup)
        #expect(model.lineup.players.first(where: { $0.id == starterID })?.isStarter == true)

        model.lineup.editState = .editable
        model.toggleStarter(starterID)

        #expect(model.canEditLineup)
        #expect(model.lineup.players.first(where: { $0.id == starterID })?.isStarter == false)
    }

    @Test("Waiver alternatives reorder only inside their acquisition round")
    func waiverQueueOrdering() {
        let model = AppModel(repository: DemoLeagueRepository())
        let first = WaiverClaim(
            player: SampleData.waiverCandidates[0],
            bid: 14,
            dropPlayerID: "17080",
            dropPlayerName: "Jaylin Noel",
            round: 1,
            priority: 1
        )
        let fallback = WaiverClaim(
            player: SampleData.waiverCandidates[1],
            bid: 5,
            dropPlayerID: nil,
            dropPlayerName: nil,
            round: 1,
            priority: 2
        )
        let nextAcquisition = WaiverClaim(
            player: SampleData.waiverCandidates[2],
            bid: 3,
            dropPlayerID: nil,
            dropPlayerName: nil,
            round: 2,
            priority: 1
        )
        model.waivers.claims = [first, fallback, nextAcquisition]

        model.moveClaims(inRound: 1, from: IndexSet(integer: 1), to: 0)

        let firstRound = model.waivers.claims.filter { $0.round == 1 }
        #expect(firstRound.map(\.priority) == [1, 2])
        #expect(firstRound.first?.player.id == fallback.player.id)
        #expect(model.waivers.claims.last?.round == 2)
    }

    @Test("Only MFL's narrow preseason API error is tolerated")
    func preseasonLiveScoringErrorClassification() {
        let message = "Live scoring is not available until the season starts"

        #expect(LiveMFLRepository.isPreseasonLiveScoringError(MFLCoreError.api(message)))
        #expect(!LiveMFLRepository.isPreseasonLiveScoringError(MFLCoreError.unauthorized(message)))
        #expect(!LiveMFLRepository.isPreseasonLiveScoringError(MFLCoreError.transport(message)))
        #expect(!LiveMFLRepository.isPreseasonLiveScoringError(
            MFLCoreError.api("Live scoring is not available for this request")
        ))
    }

    @Test("Lineup readback rejects missing, duplicate, and ambiguous assignments")
    func lineupReadbackVerification() throws {
        let valid = try rosterStatuses(
            #"[{"id":"1","roster_franchise":{"franchise_id":"0001","status":"S"}},{"id":"2","roster_franchise":{"franchise_id":"0001","status":"NS"}}]"#
        )
        let starters = try LiveMFLRepository.verifiedStarterIDs(
            from: valid,
            rosterPlayerIDs: ["1", "2"],
            franchiseID: "0001"
        )
        #expect(starters == ["1"])

        let invalidPayloads = [
            #"[{"id":"1","roster_franchise":{"franchise_id":"0001","status":"S"}}]"#,
            #"[{"id":"1","roster_franchise":{"franchise_id":"0001","status":"S"}},{"id":"1","roster_franchise":{"franchise_id":"0001","status":"S"}},{"id":"2","roster_franchise":{"franchise_id":"0001","status":"NS"}}]"#,
            #"[{"id":"1","roster_franchise":{"franchise_id":"0001","status":"S"}},{"id":"2","roster_franchise":{"franchise_id":"0001","status":"R"}}]"#,
        ]

        var rejectionCount = 0
        for payload in invalidPayloads {
            do {
                _ = try LiveMFLRepository.verifiedStarterIDs(
                    from: rosterStatuses(payload),
                    rosterPlayerIDs: ["1", "2"],
                    franchiseID: "0001"
                )
                Issue.record("Expected unsafe lineup readback to be rejected")
            } catch {
                rejectionCount += 1
            }
        }
        #expect(rejectionCount == invalidPayloads.count)
    }

    private func rosterStatuses(_ playerStatusJSON: String) throws -> MFLPlayerRosterStatusCollection {
        let data = Data(
            "{\"playerRosterStatuses\":{\"playerStatus\":\(playerStatusJSON)}}".utf8
        )
        return try JSONDecoder()
            .decode(MFLPlayerRosterStatusesResponse.self, from: data)
            .playerRosterStatuses
    }
}
