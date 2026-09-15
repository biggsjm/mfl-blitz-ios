import Foundation
import Testing
@testable import MFLBlitz

@MainActor
struct LineupBenchFlowTests {
    @Test("Starting a bench player cannot overfill an already complete lineup")
    func fullLineupCannotBeOverfilled() {
        let model = AppModel(repository: DemoLeagueRepository())
        let original = model.lineup
        model.toggleStarter("15757")
        #expect(model.lineup == original)
        #expect(model.starterValidationMessage == nil)
        #expect(!model.hasLineupChanges)
    }

    @Test("Start offers legal fixed and FLEX swaps without editing until a starter is selected")
    func startFromBench() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        model.setTiebreaker("15757")
        let original = model.lineup
        let request = try #require(model.startRequest(for: "15757"))
        let candidates = model.startCandidates(for: request)
        #expect(Set(candidates.map { $0.starter.id }) == ["15284", "15761", "14842", "16080", "15256"])
        #expect(model.lineup == original) // Opening or canceling makes no partial edit.
        #expect(!model.startPlayer(request, replacing: "12620"))
        #expect(model.lineup == original)
        #expect(model.startPlayer(request, replacing: "15256"))
        #expect(model.lineup.starters.count == 9)
        #expect(model.lineup.hasValidStarterPositions)
        #expect(model.lineup.startingSlots.first { $0.id == "15757" }?.label == "FLEX")
        #expect(model.lineup.bench.contains { $0.id == "15256" })
        #expect(model.lineup.tiebreakerPlayerIDs.isEmpty)
        #expect(model.lineup.serverStarterPlayerIDs == original.serverStarterPlayerIDs)
        #expect(!model.startPlayer(request, replacing: "15256"))
    }

    @Test("Starting from the bench respects position caps and league superflex eligibility")
    func startRespectsLeagueRules() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let qb = try #require(model.startRequest(for: "14056"))
        #expect(model.startCandidates(for: qb).map { $0.starter.id } == ["12620"])
        model.lineup.positionRequirements[0].maximum = 2
        #expect(model.startCandidates(for: qb).isEmpty)
        let superflex = try #require(model.startRequest(for: "14056"))
        #expect(Set(model.startCandidates(for: superflex).map { $0.starter.id }) == ["12620", "15256", "16080"])
        model.lineup.positionRequirements[3].maximum = 1
        let te = try #require(model.startRequest(for: "16269"))
        #expect(model.startCandidates(for: te).map { $0.slotLabel } == ["TE"])
    }

    @Test("Pending starts recheck locks, roster identity, week, rules and edit availability",
          arguments: ["incoming lock", "outgoing lock", "IR", "duplicate", "position", "week", "rules", "busy", "conflict", "refresh"])
    func unsafeStarts(change: String) throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let request = try #require(model.startRequest(for: "15757"))
        let incoming = try #require(model.lineup.players.firstIndex { $0.id == "15757" })
        let outgoing = try #require(model.lineup.players.firstIndex { $0.id == "15256" })
        switch change {
        case "incoming lock": model.lineup.players[incoming].isLocked = true
        case "outgoing lock": model.lineup.players[outgoing].isLocked = true
        case "IR": model.lineup.players[incoming].injuryStatus = .injuredReserve
        case "duplicate": model.lineup.players.append(model.lineup.players[incoming])
        case "position": model.lineup.players[incoming].position = "TE"
        case "week": model.lineup.week = 2; model.selectedWeek = 2
        case "rules": model.lineup.positionRequirements[2].maximum = 4
        case "busy": model.isBusy = true
        case "conflict": model.lineupConflict = "Saved starters changed"
        default: model.isLoadingLineup = true
        }
        let original = model.lineup
        #expect(!model.startPlayer(request, replacing: "15256"))
        #expect(model.lineup == original)
    }

    @Test("Move to bench recovers an overfilled draft even when FLEX offers no replacements")
    func recoverOverfilledDraft() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let incoming = try #require(model.lineup.players.firstIndex { $0.id == "15757" })
        model.lineup.players[incoming].isStarter = true // A draft saved by the previous build.
        let baseline = model.lineup.serverStarterPlayerIDs
        #expect(model.starterValidationMessage == "Move 1 player to the bench")
        let request = try #require(model.replacementRequest(for: "15256"))
        #expect(request.slotLabel == "FLEX")
        #expect(model.replacementCandidates(for: request).isEmpty)
        #expect(model.canBenchStarter(request))
        #expect(model.benchStarter(request))
        #expect(model.lineup.starters.count == 9)
        #expect(model.starterValidationMessage == nil)
        #expect(model.lineup.starters.contains { $0.id == "15757" })
        #expect(model.lineup.bench.contains { $0.id == "15256" })
        #expect(model.lineup.serverStarterPlayerIDs == baseline)
        #expect(!model.benchStarter(request))
    }

    @Test("Bench actions reject stale requests and newly locked players")
    func unsafeBenchActions() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let request = try #require(model.replacementRequest(for: "15256"))
        let outgoing = try #require(model.lineup.players.firstIndex { $0.id == "15256" })
        model.lineup.players[outgoing].isLocked = true
        let locked = model.lineup
        #expect(!model.canBenchStarter(request))
        #expect(!model.benchStarter(request))
        #expect(model.lineup == locked)
        model.lineup.players[outgoing].isLocked = false
        #expect(model.replaceStarter(request, with: "15757"))
        let swapped = model.lineup
        #expect(!model.benchStarter(request))
        #expect(model.lineup == swapped)
    }

    @Test("An open slot survives relaunch and can be filled before reviewed in-memory submission")
    func benchThenFillPersistence() async throws {
        let repository = ReliabilityRepository()
        let store = MemoryPrivateStore()
        let model = AppModel(repository: repository, privateStore: store)
        await model.signIn(credentials: LoginCredentials())
        let baseline = model.lineup.serverStarterPlayerIDs
        let request = try #require(model.replacementRequest(for: "15256"))
        #expect(model.benchStarter(request))
        #expect(model.starterValidationMessage == "Choose 1 more starter")
        #expect(await model.submitLineup() == nil)
        let restored = AppModel(repository: repository, privateStore: store)
        await restored.restoreSession()
        #expect(restored.lineup.starters.count == 8)
        #expect(restored.lineup.bench.contains { $0.id == "15256" })
        #expect(restored.startRequest(for: "16269") == nil)
        restored.toggleStarter("16269")
        #expect(restored.lineup.starters.count == 9)
        #expect(restored.starterValidationMessage == nil)
        #expect(restored.lineup.serverStarterPlayerIDs == baseline)
        #expect(await repository.testLineup.serverStarterPlayerIDs == baseline)
        restored.setTiebreaker("14056")
        #expect(await restored.submitLineup(reviewing: restored.lineup) != nil)
        #expect(!restored.hasLineupChanges)
        #expect(await repository.testLineup.starters.contains { $0.id == "16269" })
    }
}
