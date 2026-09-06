import Foundation
import Testing
@testable import MFLBlitz

@MainActor
struct StarterSlotSwapTests {
    @Test("RB, WR and TE slots offer same-position FLEX starters and bench players", arguments: ["RB", "WR", "TE"])
    func fixedSlots(position: String) throws {
        let model = AppModel(repository: DemoLeagueRepository())
        if position == "TE" {
            let flex = try #require(model.replacementRequest(for: "15256"))
            #expect(model.replaceStarter(flex, with: "16269"))
        }
        let fixed = try #require(model.lineup.startingSlots.first { !$0.isFlex && $0.player.position == position })
        let flex = try #require(model.lineup.startingSlots.first { $0.isFlex && $0.player.position == position })
        let request = try #require(model.replacementRequest(for: fixed.id))
        let original = model.lineup
        let candidates = model.replacementCandidates(for: request)
        #expect(candidates.contains { $0.id == flex.id })
        #expect(candidates.allSatisfy { $0.position == position && $0.id != fixed.id })
        #expect(!model.replacementNeedsFollowUp(for: request, with: flex.id))
        #expect(model.replaceStarter(request, with: flex.id))
        #expect(model.lineup.startingSlots.first { $0.id == flex.id }?.label == position)
        #expect(model.lineup.startingSlots.first { $0.id == fixed.id }?.label == "FLEX")
        #expect(model.lineup.starters == original.starters)
        #expect(model.lineup.tiebreakerPlayerIDs == original.tiebreakerPlayerIDs)
        #expect(model.lineup.serverStarterPlayerIDs == original.serverStarterPlayerIDs)
        #expect(model.starterValidationMessage == nil)
        #expect(!model.replaceStarter(request, with: flex.id)) // Old/double tap cannot reverse it.
        let reverse = try #require(model.replacementRequest(for: fixed.id))
        #expect(model.replaceStarter(reverse, with: flex.id))
        #expect(model.lineup.startingAssignments == original.startingAssignments)
    }

    @Test("FLEX includes all league-eligible starters and bench players, not the selected or locked players")
    func flexIncludesStarters() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let request = try #require(model.replacementRequest(for: "15256"))
        let candidates = model.replacementCandidates(for: request)
        #expect(Set(candidates.filter(\.isStarter).map(\.id)) == ["14073", "13319", "15284", "15761", "14842", "15889", "16080"])
        #expect(!candidates.contains { $0.id == "15256" || $0.position == "QB" || $0.injuryStatus == .injuredReserve })
        let rb = try #require(model.lineup.players.firstIndex { $0.id == "14073" })
        model.lineup.players[rb].isLocked = true
        #expect(!model.replacementCandidates(for: request).contains { $0.id == "14073" })
        #expect(!model.replaceStarter(request, with: "14073"))
    }

    @Test("Two differently positioned FLEX starters can exchange slots without benching anyone")
    func flexToFlex() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let original = model.lineup
        let request = try #require(model.replacementRequest(for: "15256"))
        #expect(model.replaceStarter(request, with: "16080"))
        #expect(model.lineup.startingSlots.filter(\.isFlex).map(\.id) == ["15256", "16080"])
        #expect(model.lineup.starters == original.starters)
        #expect(!model.hasLineupChanges) // Only local placement changed; nothing to send.
        #expect(!model.replaceStarter(request, with: "16080"))
    }

    @Test("Moving a fixed WR into an RB FLEX requires a valid follow-up and applies both moves atomically")
    func crossPositionMove() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let request = try #require(model.replacementRequest(for: "15256"))
        let original = model.lineup
        #expect(model.replacementNeedsFollowUp(for: request, with: "15284"))
        let fills = model.replacementFollowUpCandidates(for: request, with: "15284")
        #expect(Set(fills.map(\.id)) == ["15757", "17080", "14860", "16080"])
        #expect(fills.allSatisfy { $0.position == "WR" })
        #expect(!model.replaceStarter(request, with: "15284"))
        #expect(!model.replaceStarter(request, with: "15284", fillingVacatedSlotWith: "15712"))
        #expect(!model.replaceStarter(request, with: "15284", fillingVacatedSlotWith: "15761"))
        #expect(model.lineup == original) // Opening, canceling, and invalid fills never partially edit.
        model.setTiebreaker("15757")
        #expect(model.replaceStarter(request, with: "15284", fillingVacatedSlotWith: "15757"))
        #expect(model.lineup.startingSlots.first { $0.id == "15284" }?.label == "FLEX")
        #expect(model.lineup.startingSlots.first { $0.id == "15757" }?.label == "WR")
        #expect(model.lineup.bench.contains { $0.id == "15256" })
        #expect(model.lineup.starters.count == 9)
        #expect(model.starterValidationMessage == nil)
        #expect(model.lineup.tiebreakerPlayerIDs.isEmpty)
        #expect(model.hasLineupChanges)
        #expect(model.lineup.serverStarterPlayerIDs == original.serverStarterPlayerIDs)
        #expect(!model.replaceStarter(request, with: "15284", fillingVacatedSlotWith: "15757"))
    }

    @Test("A third starter in FLEX can fill the vacated fixed slot without changing starter membership")
    func threeStarterRotation() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let original = model.lineup
        let request = try #require(model.replacementRequest(for: "15256"))
        #expect(model.replaceStarter(request, with: "15284", fillingVacatedSlotWith: "16080"))
        #expect(model.lineup.startingSlots.first { $0.id == "15284" }?.label == "FLEX")
        #expect(model.lineup.startingSlots.first { $0.id == "16080" }?.label == "WR")
        #expect(model.lineup.startingSlots.first { $0.id == "15256" }?.label == "FLEX")
        #expect(model.lineup.starters == original.starters)
        #expect(model.lineup.tiebreakerPlayerIDs == original.tiebreakerPlayerIDs)
        #expect(!model.hasLineupChanges)
        #expect(model.starterValidationMessage == nil)
    }

    @Test("Follow-up moves recheck candidate locks, roster duplicates, league limits and stale requests")
    func unsafeFollowUps() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let request = try #require(model.replacementRequest(for: "15256"))
        let fill = try #require(model.lineup.players.firstIndex { $0.id == "15757" })
        model.lineup.players[fill].isLocked = true
        #expect(!model.replaceStarter(request, with: "15284", fillingVacatedSlotWith: "15757"))
        model.lineup.players[fill].isLocked = false
        model.lineup.players.append(model.lineup.players[fill])
        #expect(!model.replaceStarter(request, with: "15284", fillingVacatedSlotWith: "15757"))
        model.lineup.players.removeLast()
        let moving = try #require(model.lineup.players.firstIndex { $0.id == "15284" })
        model.lineup.players[moving].isLocked = true
        #expect(model.replacementFollowUpCandidates(for: request, with: "15284").isEmpty)
        #expect(!model.replaceStarter(request, with: "15284", fillingVacatedSlotWith: "15757"))
        model.lineup.players[moving].isLocked = false
        model.lineup.positionRequirements[2].maximum = 4
        #expect(model.replacementCandidates(for: request).isEmpty) // Old rules invalidate the picker.
        let capped = try #require(model.replacementRequest(for: "15256"))
        #expect(model.replacementFollowUpCandidates(for: capped, with: "15284").map(\.id) == ["16080"])
        #expect(!model.replaceStarter(capped, with: "15284", fillingVacatedSlotWith: "15757"))
    }

    @Test("Slot placement persists through refresh and relaunch even when starter membership is unchanged")
    func localPlacementPersistence() async throws {
        let repository = ReliabilityRepository()
        let store = MemoryPrivateStore()
        let model = AppModel(repository: repository, privateStore: store)
        await model.signIn(credentials: LoginCredentials())
        let original = model.lineup
        let request = try #require(model.replacementRequest(for: "14073"))
        #expect(model.replaceStarter(request, with: "15256"))
        let chosen = model.lineup.startingAssignments
        #expect(!model.hasLineupChanges)
        await model.refreshAll()
        #expect(model.lineup.startingAssignments == chosen)
        let restored = AppModel(repository: repository, privateStore: store)
        await restored.restoreSession()
        #expect(restored.lineup.startingAssignments == chosen)
        #expect(!restored.hasLineupChanges)
        #expect(await repository.testLineup.startingAssignments == original.startingAssignments)
        let benchRequest = try #require(restored.replacementRequest(for: "15256"))
        #expect(restored.replaceStarter(benchRequest, with: "15712"))
        #expect(restored.lineup.startingSlots.first { $0.id == "15712" }?.label == "RB")
        #expect(restored.lineup.startingSlots.first { $0.id == "14073" }?.label == "FLEX")
        let dirtyRestored = AppModel(repository: repository, privateStore: store)
        await dirtyRestored.restoreSession()
        #expect(dirtyRestored.lineup.startingAssignments == restored.lineup.startingAssignments)
        #expect(dirtyRestored.hasLineupChanges)
        dirtyRestored.setTiebreaker("14056")
        #expect(await dirtyRestored.submitLineup() != nil) // In-memory test repository only.
        let submittedRestored = AppModel(repository: repository, privateStore: store)
        await submittedRestored.restoreSession()
        #expect(submittedRestored.lineup.startingAssignments == dirtyRestored.lineup.startingAssignments)
        #expect(!submittedRestored.hasLineupChanges)
    }

    @Test("Old drafts decode without placement and stale or invalid placements fall back to league rules")
    func migrationAndFallback() throws {
        let old = Data(#"{"baseline":[],"starters":[],"tiebreakers":[],"submittedTiebreakers":[]}"#.utf8)
        #expect(try JSONDecoder().decode(LineupDraft.self, from: old).startingAssignments == nil)
        var lineup = SampleData.lineup
        let original = lineup.startingAssignments
        lineup.preferredStartingAssignments = original
        lineup.preferredStartingAssignments?[0].playerID = "15256" // Duplicate and RB in QB.
        #expect(lineup.startingAssignments == original)
        lineup.preferredStartingAssignments = original
        lineup.positionRequirements[0].maximum = 2
        lineup.positionRequirements[1].minimum = 3
        #expect(lineup.startingSlots.filter(\.isFlex).count == 1)
        #expect(lineup.startingSlots.first { $0.id == "15256" }?.label == "RB")
    }
}
