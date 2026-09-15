import Foundation
import Testing
@testable import MFLBlitz

@MainActor struct ScoringRefreshTests {
    func model(_ repository: ReliabilityRepository) -> AppModel {
        let value = AppModel(repository: repository, privateStore: MemoryPrivateStore())
        value.workspace = SampleData.workspace; value.phase = .signedIn; value.scores = SampleData.scores
        return value
    }

    @Test func entryWaitsForStartupAndThenRefreshes() async throws {
        let repository = ReliabilityRepository(), model = model(repository)
        model.isLoadingScores = true
        let entry = Task { await model.refreshScoresOnEntry() }
        try await Task.sleep(for: .milliseconds(120))
        #expect(await repository.scoreLoads == 0)
        model.isLoadingScores = false
        await entry.value
        #expect(await repository.scoreLoads == 1)
    }

    @Test func entryDoesNotRefreshAWeekChangedDuringStartup() async throws {
        let repository = ReliabilityRepository(), model = model(repository)
        model.isLoadingScores = true
        let entry = Task { await model.refreshScoresOnEntry() }
        try await Task.sleep(for: .milliseconds(120))
        model.selectedWeek = 2; model.isLoadingScores = false
        await entry.value
        #expect(await repository.scoreLoads == 0)
    }

    @Test func nflReadsCoalesceAndDoNotBlockFantasyScores() async throws {
        let repository = ReliabilityRepository(), model = model(repository), gate = TestGate()
        await repository.configureScoringGames(gate: gate)
        let pending = Task { await model.refreshScoringGames(week: 1) }
        while await repository.scoringGameLoads == 0 { await Task.yield() }
        await model.refreshScoringGames(week: 1)
        await model.refreshScores(silent: true)
        #expect(await repository.scoreLoads == 1)
        #expect(await repository.scoringGameLoads == 1)
        #expect(model.scoringGames[1] == nil)
        await gate.open(); await pending.value
        let first = try #require(model.scoringGames[1])
        await model.refreshScoringGames(week: 1)
        #expect(await repository.scoringGameLoads == 1)
        await repository.configureScoringGames(failed: true)
        await model.refreshScoringGames(week: 1, force: true)
        #expect(model.scoringGames[1]?.checkedAt == first.checkedAt && model.scoringGames[1]?.failed == true)
    }

    @Test func nflResponseCannotCrossLeagueScope() async {
        let repository = ReliabilityRepository(), model = model(repository), gate = TestGate()
        await repository.configureScoringGames(gate: gate)
        let pending = Task { await model.refreshScoringGames(week: 1) }
        while await repository.scoringGameLoads == 0 { await Task.yield() }
        model.workspace = nil
        await gate.open(); await pending.value
        #expect(model.scoringGames.isEmpty)
    }
}
