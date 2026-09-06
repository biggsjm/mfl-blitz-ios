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
