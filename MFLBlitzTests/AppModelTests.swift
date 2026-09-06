import Foundation
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

    @Test("Lineup validation notices missing starters")
    func lineupValidation() {
        let model = AppModel(repository: DemoLeagueRepository())
        let starterID = model.lineup.starters[0].id

        model.toggleStarter(starterID)

        #expect(model.lineupValidationMessage == "Choose 1 more starter")
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
}
