import Foundation
import Testing
@testable import MFLBlitz

@MainActor
struct FlexReplacementTests {
    @Test("A changed lineup cannot be submitted from an old review modal")
    func staleReview() async {
        let model = AppModel(repository: DemoLeagueRepository())
        let review = model.lineup
        #expect(model.lineupMatchesReview(review))
        model.toggleStarter("15256")
        model.toggleStarter("16269")
        #expect(!model.lineupMatchesReview(review))
        #expect(await model.submitLineup(reviewing: review) == nil)
        #expect(model.hasLineupChanges)
    }

    @Test("League minimums reserve seven position starters and identify both FLEX slots")
    func slots() {
        let lineup = SampleData.lineup
        #expect(lineup.startingSlots.count == 9)
        #expect(lineup.startingSlots.filter(\.isFlex).map(\.id) == ["16080", "15256"])
        #expect(lineup.startingSlots.filter { !$0.isFlex }.count == 7)
        #expect(lineup.flexPositions == ["RB", "WR", "TE"])
    }

    @Test("RB and WR starters in FLEX offer all league-qualified bench positions", arguments: ["15256", "16080"])
    func flexCandidates(starter: String) throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let request = try #require(model.replacementRequest(for: starter))
        #expect(request.slotLabel == "FLEX")
        #expect(Set(model.replacementCandidates(for: request).map(\.position)) == ["RB", "WR", "TE"])
        #expect(!model.replacementCandidates(for: request).contains { $0.position == "QB" || $0.injuryStatus == .injuredReserve })
    }

    @Test("Cross-position FLEX swaps preserve the starter total and every league limit", arguments: ["15757", "16269"])
    func validSwap(incoming: String) throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let baseline = model.lineup.serverStarterPlayerIDs
        let request = try #require(model.replacementRequest(for: "15256"))
        #expect(model.replaceStarter(request, with: incoming))
        #expect(model.lineup.starters.count == 9)
        #expect(model.starterValidationMessage == nil)
        #expect(model.lineup.starters.contains { $0.id == incoming })
        #expect(model.lineup.bench.contains { $0.id == "15256" })
        #expect(model.lineup.serverStarterPlayerIDs == baseline)
        #expect(model.hasLineupChanges)
        #expect(!model.replaceStarter(request, with: incoming))
    }

    @Test("FLEX respects maximum counts and does not invent position eligibility")
    func positionCaps() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        model.lineup.positionRequirements[1].maximum = 3 // Already starting three RBs.
        model.lineup.positionRequirements[3].maximum = 1 // This league does not allow flex TEs.
        let request = try #require(model.replacementRequest(for: "16080"))
        #expect(model.replacementPositions(for: request) == ["WR"])
        #expect(!model.replaceStarter(request, with: "15712"))
        #expect(!model.replaceStarter(request, with: "16269"))
        #expect(!model.replaceStarter(request, with: "14056"))
    }

    @Test("An additional QB is eligible only when the league explicitly allows it")
    func superflex() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        model.lineup.positionRequirements[0].maximum = 2
        let request = try #require(model.replacementRequest(for: "15256"))
        #expect(model.replacementCandidates(for: request).contains { $0.id == "14056" })
        #expect(model.replaceStarter(request, with: "14056"))
        #expect(model.starterValidationMessage == nil)
        #expect(model.lineup.tiebreakerPlayerIDs.isEmpty)
    }

    @Test("A slot that becomes required while its picker is open cannot use stale FLEX eligibility")
    func staleSlot() throws {
        let model = AppModel(repository: DemoLeagueRepository())
        let request = try #require(model.replacementRequest(for: "15256"))
        model.toggleStarter("14073")
        model.toggleStarter("15757")
        #expect(model.lineup.startingSlots.first { $0.id == "15256" }?.isFlex == false)
        #expect(model.replacementCandidates(for: request).isEmpty)
        #expect(!model.replaceStarter(request, with: "16269"))
    }

    @Test("A cross-position FLEX draft survives reconnection without submitting")
    func persistence() async throws {
        let repository = ReliabilityRepository()
        let store = MemoryPrivateStore()
        let model = AppModel(repository: repository, privateStore: store)
        await model.signIn(credentials: LoginCredentials())
        let request = try #require(model.replacementRequest(for: "15256"))
        #expect(model.replaceStarter(request, with: "16269"))
        let restored = AppModel(repository: repository, privateStore: store)
        await restored.restoreSession()
        #expect(restored.lineup.starters.contains { $0.id == "16269" })
        #expect(restored.starterValidationMessage == nil)
        #expect(await repository.testLineup.starters.contains { $0.id == "15256" })
    }
}
