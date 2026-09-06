import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

@Suite("Schedule normalization and shared loading")
struct SchedulePresentationTests {
    @Test("Schedule freshness uses one whole unit, never seconds")
    func conciseFreshness() {
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let cases: [(TimeInterval, String)] = [
            (-30, "Updated just now"), (0, "Updated just now"), (59, "Updated just now"),
            (60, "Updated 1 min ago"), (138, "Updated 2 min ago"), (3_599, "Updated 59 min ago"),
            (3_600, "Updated 1 hr ago"), (86_399, "Updated 23 hr ago"),
            (86_400, "Updated 1 day ago"), (172_800, "Updated 2 days ago")
        ]
        for (age, expected) in cases {
            #expect(ScheduleFreshness.label(updatedAt: updatedAt,
                now: updatedAt.addingTimeInterval(age)) == expected)
        }
    }

    @Test("Upcoming T placeholders do not become final ties or zero scores")
    func futurePlaceholder() {
        let value = schedule(current: 3, completed: 2)
        let game = value.weeks.first(where: { $0.week == 4 })!.matchups[0]
        #expect(game.state == .scheduled)
        #expect(game.participants.allSatisfy { $0.score == nil })
        #expect(game.result(for: "0001") == nil)
        #expect(value.firstUpcomingWeek == 3)
    }

    @Test("Reported zero can be a completed result; omitted scores cannot")
    func completedScores() {
        let zero = makeGame(score: 0, opponentScore: 12, result: "L")
        let absent = makeGame(result: "T")
        let value = SeasonScheduleSnapshot(source: MFLSchedule(weeks: [
            MFLScheduleWeek(week: 1, matchups: [zero, absent])
        ]), season: 2026, leagueID: "sample", currentWeek: 2, completedWeek: 1)
        #expect(value.weeks[0].matchups[0].result(for: "0001") == .loss)
        #expect(value.weeks[0].matchups[1].result(for: "0001") == nil)
        #expect(value.weeks[0].matchups[0].participants[0].score == .zero)
    }

    @Test("Multiple games and repeated pairs survive filtering with stable unique identities")
    func duplicateMatchups() {
        let pair = makeGame()
        let other = MFLScheduleMatchup(franchises: [
            MFLScheduleFranchise(franchiseID: "0001", isHome: true),
            MFLScheduleFranchise(franchiseID: "0003", isHome: false)
        ])
        func normalized(_ games: [MFLScheduleMatchup]) -> SeasonScheduleSnapshot {
            SeasonScheduleSnapshot(source: MFLSchedule(weeks: [MFLScheduleWeek(week: 4, matchups: games)]),
                season: 2026, leagueID: "sample")
        }
        let first = normalized([pair, other, pair])
        let reordered = normalized([other, pair, pair])
        let games = first.filteredWeeks(franchiseID: "0001")[0].matchups
        #expect(games.count == 3)
        #expect(Set(games.map(\.id)).count == 3)
        #expect(Set(games.map(\.id)) == Set(reordered.weeks[0].matchups.map(\.id)))
        #expect(first.filteredWeeks(franchiseID: "0003")[0].matchups.count == 1)
        #expect(first.filteredWeeks(franchiseID: "missing")[0].matchups.isEmpty)
    }

    @Test("Empty and partially returned weeks are not byes; explicit BYE stays explicit")
    func emptyWeeksAndBye() {
        let source = MFLSchedule(weeks: [
            MFLScheduleWeek(week: 1, matchups: [MFLScheduleMatchup(franchises: [
                MFLScheduleFranchise(franchiseID: "0001"), MFLScheduleFranchise(franchiseID: "BYE")
            ])]),
            MFLScheduleWeek(week: 2, matchups: []),
            MFLScheduleWeek(week: 3, matchups: [MFLScheduleMatchup(franchises: [
                MFLScheduleFranchise(franchiseID: "0001"), MFLScheduleFranchise(franchiseID: "0000")
            ])])
        ])
        let value = SeasonScheduleSnapshot(source: source, season: 2026, leagueID: "sample",
            startWeek: 1, endWeek: 4, lastRegularSeasonWeek: 3)
        #expect(value.weeks.count == 4)
        #expect(value.weeks[0].matchups[0].isExplicitBye)
        #expect(!value.weeks[0].matchups[0].canOpenMatchup)
        #expect(value.weeks[1].matchups.isEmpty)
        #expect(!value.weeks[2].matchups[0].isExplicitBye)
        #expect(value.weeks[3].isPlayoff && value.weeks[3].matchups.isEmpty)
    }

    @Test("Configured season bounds win over extra NFL weeks and no clock means no final inference")
    func boundsAndConfidence() {
        let source = MFLSchedule(weeks: [MFLScheduleWeek(week: 1, matchups: [makeGame(score: 2, opponentScore: 2)]),
                                        MFLScheduleWeek(week: 18, matchups: [])])
        let value = SeasonScheduleSnapshot(source: source, season: 2026, leagueID: "sample",
            startWeek: 1, endWeek: 14, lastRegularSeasonWeek: 12)
        #expect(value.weeks.map(\.week) == Array(1...14))
        #expect(value.weeks[0].matchups[0].state == .unknown)
        #expect(value.weeks[0].matchups[0].result(for: "0001") == nil)
        #expect(!value.weekIsConfirmed)
        let empty = SeasonScheduleSnapshot(source: MFLSchedule(weeks: []), season: 2026, leagueID: "sample")
        #expect(empty.weeks.isEmpty)
        let finished = schedule(current: 6, completed: 5)
        #expect(!finished.hasRemainingWeeks && finished.firstUpcomingWeek == nil)
    }

    @Test("One shared snapshot is reused until expiry; force refresh bypasses its age")
    @MainActor
    func freshness() async {
        let clock = ScheduleTestClock()
        var calls = 0
        let model = SeasonScheduleModel(timeToLive: 900, now: { clock.date }) {
            calls += 1
            return schedule(date: clock.date)
        }
        await model.loadIfNeeded()
        clock.date.addTimeInterval(899)
        await model.loadIfNeeded()
        #expect(calls == 1)
        clock.date.addTimeInterval(1)
        await model.loadIfNeeded()
        #expect(calls == 2)
        await model.refresh()
        #expect(calls == 3)
        #expect(model.snapshot?.fetchedAt == clock.date)
    }

    @Test("Concurrent callers join one request even when the first view goes away")
    @MainActor
    func sharedRequest() async {
        let gate = ScheduleTestGate()
        let model = SeasonScheduleModel(loader: { try await gate.load() })
        let first = Task { await model.loadIfNeeded() }
        while gate.calls == 0 { await Task.yield() }
        let second = Task { await model.loadIfNeeded() }
        await Task.yield()
        first.cancel()
        gate.complete(schedule())
        await first.value
        await second.value
        #expect(gate.calls == 1)
        #expect(model.snapshot != nil && !model.isLoading && model.errorMessage == nil)
    }

    @Test("Session invalidation discards a late successful response and prevents further loads")
    @MainActor
    func sessionInvalidation() async {
        let gate = ScheduleTestGate()
        let model = SeasonScheduleModel(loader: { try await gate.load() })
        let request = Task { await model.loadIfNeeded() }
        while gate.calls == 0 { await Task.yield() }
        model.invalidateSession()
        gate.complete(schedule()) // Deliberately ignores cancellation to reproduce a late transport.
        await request.value
        await model.refresh()
        #expect(model.snapshot == nil && !model.isLoading && model.errorMessage == nil)
        #expect(gate.calls == 1)
    }

    @Test("Failed refresh retains the saved schedule and avoids repeated automatic requests")
    @MainActor
    func staleOnFailure() async {
        let clock = ScheduleTestClock()
        var calls = 0
        let model = SeasonScheduleModel(timeToLive: 900, now: { clock.date }) {
            calls += 1
            if calls > 1 { throw RepositoryError.server("Synthetic connection failure") }
            return schedule(date: clock.date)
        }
        await model.loadIfNeeded()
        let saved = model.snapshot
        clock.date.addTimeInterval(901)
        await model.loadIfNeeded()
        await model.loadIfNeeded()
        #expect(calls == 2)
        #expect(model.snapshot == saved)
        #expect(model.errorMessage != nil && !model.isLoading)
    }

    #if canImport(UIKit)
    @Test("Loading and filtering schedules preserve the active lineup week and draft")
    @MainActor
    func lineupIsolation() async throws {
        let app = AppModel(repository: DemoLeagueRepository(), privateStore: MemoryPrivateStore())
        let starter = try #require(app.lineup.starters.first)
        app.toggleStarter(starter.id)
        let draft = app.lineup
        let activeWeek = app.selectedWeek
        await app.seasonSchedule.loadIfNeeded()
        let loaded = try #require(app.seasonSchedule.snapshot)
        if let featured = app.scores.featuredMatchup {
            let featuredIDs = Set([featured.away.id, featured.home.id])
            #expect(loaded.weeks.first(where: { $0.week == app.currentWeek })?.matchups.contains {
                Set($0.participants.map(\.franchiseID)) == featuredIDs
            } == true)
        }
        _ = loaded.filteredWeeks(franchiseID: "0002")
        _ = loaded.matchup(id: "not-a-matchup", week: 13)
        await app.seasonSchedule.loadIfNeeded()
        #expect(app.selectedWeek == activeWeek)
        #expect(app.lineup == draft)
    }
    #endif

    private func makeGame(score: Decimal? = nil, opponentScore: Decimal? = nil,
                          result: String = "T") -> MFLScheduleMatchup {
        MFLScheduleMatchup(franchises: [
            MFLScheduleFranchise(franchiseID: "0001", score: score, isHome: false, result: result),
            MFLScheduleFranchise(franchiseID: "0002", score: opponentScore, isHome: true, result: "T")
        ])
    }

    private func schedule(current: Int = 1, completed: Int = 0, date: Date = Date()) -> SeasonScheduleSnapshot {
        SeasonScheduleSnapshot(source: MFLSchedule(weeks: (1...5).map {
            MFLScheduleWeek(week: $0, matchups: [makeGame()])
        }), season: 2026, leagueID: "sample", startWeek: 1, endWeek: 5,
            currentWeek: current, completedWeek: completed, fetchedAt: date)
    }
}

@MainActor
private final class ScheduleTestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
private final class ScheduleTestGate {
    private var continuation: CheckedContinuation<SeasonScheduleSnapshot, any Error>?
    private(set) var calls = 0

    func load() async throws -> SeasonScheduleSnapshot {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func complete(_ value: SeasonScheduleSnapshot) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
