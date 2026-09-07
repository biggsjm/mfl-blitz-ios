import Foundation
import MFLCore
import Testing
@testable import MFLBlitz

struct LeagueExtrasSafetyTests {
    @Test("Two synthetic weeks: block publication, a later conflict, ownership changes and recovery")
    func twoWeekBlockJourney() async throws {
        let server = BlockFixtureTransport()
        let repository = try await connected(server)
        let weekOne = TradingBlockDraft(codes: ["201"], lookingFor: "RB & picks")
        let receipt = try await repository.publishTradingBlock(weekOne)
        #expect(receipt.confirmed)
        #expect(try await repository.pendingTradingBlock() == nil)
        let first = try #require(receipt.snapshot?.listings.first)
        await server.setListing(.init(id: "0001", codes: ["201"], lookingFor: "Different note on another device"))
        let weekTwo = TradingBlockDraft(codes: ["201"], lookingFor: "TE", baseline: first)
        await #expect(throws: (any Error).self) { try await repository.publishTradingBlock(weekTwo) }
        #expect(await server.posts == 1)
        await server.setListing(nil)
        await server.base.moveTradePlayer()
        await #expect(throws: (any Error).self) { try await repository.publishTradingBlock(weekOne) }
        #expect(await server.posts == 1)
    }

    @Test("Timeout keeps a durable marker; a second publish cannot replay it")
    func ambiguousPublication() async throws {
        let server = BlockFixtureTransport()
        let store = MemoryPrivateStore()
        let repository = try await connected(server, store: store)
        await server.enableTimeout()
        let draft = TradingBlockDraft(codes: ["201"], lookingFor: "Picks")
        #expect(try await !repository.publishTradingBlock(draft).confirmed)
        #expect(try await repository.pendingTradingBlock() != nil)
        await #expect(throws: (any Error).self) { try await repository.publishTradingBlock(draft) }
        #expect(await server.posts == 1)
        let restored = try await connected(server, store: store)
        #expect(try await restored.reconcileTradingBlock().confirmed)
        #expect(try await restored.pendingTradingBlock() == nil)
        #expect(await server.posts == 1)
    }

    @Test("Missing capabilities and unknown existing assets prevent publication")
    func blockedPublication() async throws {
        let server = BlockFixtureTransport()
        let repository = try await connected(server)
        await server.denyTrading()
        await #expect(throws: (any Error).self) { try await repository.publishTradingBlock(TradingBlockDraft(codes: ["201"])) }
        #expect(await server.posts == 0)
        var snapshot = try await repository.loadTradingBlock(refresh: true)
        let baseline = MFLTradingBlockListing(id: "0001", codes: ["UNKNOWN_CODE"], lookingFor: "")
        snapshot.listings = [baseline]
        let draft = TradingBlockDraft(codes: ["201"], baseline: baseline)
        #expect(throws: (any Error).self) { try TradingBlockPolicy.validate(draft, fresh: snapshot, ownerID: "0001") }
    }

    @Test("Empty, unchanged and overlong drafts cannot publish")
    func draftValidation() {
        #expect(!TradingBlockDraft().canPublish)
        let baseline = MFLTradingBlockListing(id: "0001", codes: ["101"], lookingFor: "RB")
        #expect(!TradingBlockDraft(codes: ["101"], lookingFor: "RB", baseline: baseline).canPublish)
        #expect(!TradingBlockDraft(codes: ["101"], lookingFor: String(repeating: "x", count: 257)).canPublish)
        #expect(TradingBlockDraft(codes: ["101"], lookingFor: "RB").canPublish)
        let removal = TradingBlockDraft(baseline: baseline)
        #expect(removal.canPublish && removal.isRemoval && removal.hasContent)
        #expect(!TradingBlockDraft(lookingFor: "Only a note").canPublish)
    }

    @Test("Removing the last asset confirms absent or explicitly empty readback", arguments: [false, true])
    func removeLastAsset(emptyRow: Bool) async throws {
        let server = BlockFixtureTransport()
        await server.keepEmptyRow(emptyRow)
        let baseline = MFLTradingBlockListing(id: "0001", codes: ["201"], lookingFor: "RB wanted")
        await server.setListing(baseline)
        let repository = try await connected(server)
        let before = try await repository.loadTradingBlock(refresh: true)
        let receipt = try await repository.publishTradingBlock(TradingBlockDraft(lookingFor: baseline.lookingFor, baseline: baseline))
        #expect(receipt.confirmed && receipt.removed)
        #expect(receipt.snapshot?.listing(for: "0001") == nil)
        #expect(receipt.snapshot?.teams == before.teams, "Listing removal never changes player/pick ownership")
        #expect(try await repository.pendingTradingBlock() == nil)
        #expect(await server.posts == 1)
        // An empty owner row must not prevent making a subsequent new listing.
        #expect(try await repository.publishTradingBlock(TradingBlockDraft(codes: ["201"])).confirmed)
    }

    @Test("Removal timeout survives relaunch and is reconciled without replay")
    func ambiguousRemoval() async throws {
        let server = BlockFixtureTransport()
        let baseline = MFLTradingBlockListing(id: "0001", codes: ["201"], lookingFor: "Picks")
        await server.setListing(baseline)
        let store = MemoryPrivateStore()
        let repository = try await connected(server, store: store)
        await server.enableTimeout()
        let draft = TradingBlockDraft(baseline: baseline)
        #expect(try await !repository.publishTradingBlock(draft).confirmed)
        #expect(try await repository.pendingTradingBlock()?.intended.codes.isEmpty == true)
        await #expect(throws: (any Error).self) { try await repository.publishTradingBlock(draft) }
        let restored = try await connected(server, store: store)
        let receipt = try await restored.reconcileTradingBlock()
        #expect(receipt.confirmed && receipt.removed)
        #expect(await server.posts == 1)
    }

    @Test("An unchanged listing or a failed export never falsely confirms removal", arguments: [false, true])
    func unconfirmedRemoval(failedExport: Bool) async throws {
        let server = BlockFixtureTransport()
        let baseline = MFLTradingBlockListing(id: "0001", codes: ["201"], lookingFor: "")
        await server.setListing(baseline)
        await server.ignoreRemoval(failRead: failedExport)
        let repository = try await connected(server)
        #expect(try await !repository.publishTradingBlock(TradingBlockDraft(baseline: baseline)).confirmed)
        #expect(try await repository.pendingTradingBlock() != nil)
        #expect(await server.posts == 1)
    }

    @Test("Removal still requires current permission and an unchanged baseline")
    func removalPreflight() async throws {
        let server = BlockFixtureTransport()
        let baseline = MFLTradingBlockListing(id: "0001", codes: ["201"], lookingFor: "")
        await server.setListing(baseline)
        let repository = try await connected(server)
        let draft = TradingBlockDraft(baseline: baseline)
        await server.setListing(.init(id: "0001", codes: ["201"], lookingFor: "Changed elsewhere"))
        await #expect(throws: (any Error).self) { try await repository.publishTradingBlock(draft) }
        await server.setListing(baseline)
        await server.denyTrading()
        await #expect(throws: (any Error).self) { try await repository.publishTradingBlock(draft) }
        #expect(await server.posts == 0)
    }

    @Test("An empty removal draft can be saved, restored and submitted")
    @MainActor func removalDraftRecovery() async throws {
        let repository = DemoLeagueRepository()
        let store = ProtectedFeedStore(MemoryPrivateStore())
        let model = TradingBlockModel(repository: repository, workspace: SampleData.workspace, store: store)
        await model.refresh()
        #expect(await model.publish(TradingBlockDraft(codes: ["12620"])))
        let baseline = try #require(model.listing)
        #expect(await model.saveDraft(TradingBlockDraft(baseline: baseline)))
        let restored = TradingBlockModel(repository: repository, workspace: SampleData.workspace, store: store)
        await restored.refresh()
        #expect(restored.draft?.isRemoval == true)
        #expect(await restored.publish(restored.initialDraft))
        #expect(restored.notice == "Trading block removed.")
        #expect(restored.listing == nil && restored.draft == nil)
        #expect(!restored.initialDraft.canPublish)
    }

    @Test("Reminder plans span two weeks, respect overrides, and exclude past dates")
    func reminderPlan() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = calendar(now: now)
        var prefs = DeadlinePreferences(categories: [.waivers: .hour, .trades: .day])
        let weekOne = DeadlineReminderPolicy.plan(snapshot: snapshot, preferences: prefs, now: now)
        #expect(weekOne.count == 2)
        #expect(Set(weekOne.map(\.id)).count == 2)
        let event = snapshot.events[0]
        prefs.events[event.id] = .off
        #expect(DeadlineReminderPolicy.plan(snapshot: snapshot, preferences: prefs, now: now).count == 1)
        prefs.events[event.id] = .before(.minutes15)
        #expect(DeadlineReminderPolicy.plan(snapshot: snapshot, preferences: prefs, now: now).first?.fireDate == event.start.addingTimeInterval(-900))
        var next = snapshot
        next.fetchedAt = now.addingTimeInterval(7 * 86_400)
        let weekTwo = DeadlineReminderPolicy.plan(snapshot: next, preferences: prefs, now: next.fetchedAt)
        #expect(weekTwo.count == 1)
        #expect(weekTwo[0].eventID == "trade:0")
        #expect(DeadlineReminderPolicy.plan(snapshot: snapshot, preferences: prefs, now: next.fetchedAt).isEmpty, "Old cache never schedules new reminders")
    }

    @Test("Reminder IDs are scoped and stable after an event moves")
    func reminderIdentity() {
        let now = Date()
        var snapshot = calendar(now: now)
        let preferences = DeadlinePreferences(categories: [.waivers: .hour])
        let first = DeadlineReminderPolicy.plan(snapshot: snapshot, preferences: preferences, now: now)
        snapshot.source.events[0].start += 7200
        let moved = DeadlineReminderPolicy.plan(snapshot: snapshot, preferences: preferences, now: now)
        #expect(first[0].id == moved[0].id)
        #expect(first[0].fireDate != moved[0].fireDate)
        snapshot.scope = "2026.other.other"
        #expect(DeadlineReminderPolicy.plan(snapshot: snapshot, preferences: preferences, now: now)[0].id != first[0].id)
        #expect(DeadlineReminderPolicy.identifier(scope: "a", eventID: "b") != DeadlineReminderPolicy.identifier(scope: "b", eventID: "a"))
    }

    @Test("Live Activity needs an actively playing starter in the owner's current matchup")
    func activityEligibility() throws {
        var scores = SampleData.scores
        scores.lastUpdated = Date()
        let workspace = SampleData.workspace
        let now = scores.lastUpdated
        let index = try #require(scores.matchups.firstIndex { $0.isUserMatchup })
        for match in scores.matchups.indices {
            for team in [true, false] {
                if team { scores.matchups[match].away.clearDisplayClocks() }
                else { scores.matchups[match].home.clearDisplayClocks() }
            }
        }
        #expect(MatchupActivityPolicy.matchup(in: scores, workspace: workspace, currentWeek: scores.week, now: now) == nil)
        scores.matchups[index].away.starters[0].gameSecondsRemaining = 1800
        #expect(MatchupActivityPolicy.matchup(in: scores, workspace: workspace, currentWeek: scores.week, now: now) != nil)
        #expect(MatchupActivityPolicy.matchup(in: scores, workspace: workspace, currentWeek: scores.week + 1, now: now) == nil)
        #expect(MatchupActivityPolicy.matchup(in: scores, workspace: workspace, currentWeek: scores.week, now: now.addingTimeInterval(121)) == nil)
        scores.matchups[index].away.starters[0].gameSecondsRemaining = 3600
        #expect(MatchupActivityPolicy.matchup(in: scores, workspace: workspace, currentWeek: scores.week, now: now) == nil)
        scores.matchups[index].away.bench[0].gameSecondsRemaining = 1800
        #expect(MatchupActivityPolicy.matchup(in: scores, workspace: workspace, currentWeek: scores.week, now: now) == nil)
    }

    @Test("Deep links carry only display scope and reject ambiguous parameters")
    func deepLinks() {
        #expect(LeagueDeepLink(URL(string: "mflblitz://calendar?scope=2026.12345.0001&id=1%3A0")!)?.scope == "2026.12345.0001")
        #expect(LeagueDeepLink(URL(string: "mflblitz://calendar?scope=a&scope=b&id=1")!) == nil)
        #expect(LeagueDeepLink(URL(string: "mflblitz://matchup?scope=a&id=1&week=-1")!) == nil)
        #expect(LeagueDeepLink(URL(string: "https://calendar?scope=a&id=1")!) == nil)
    }

    @Test("Optional feeds restore a protected snapshot before a failed refresh and preserve its original age")
    @MainActor func cachedFeed() async throws {
        let memory = MemoryPrivateStore()
        let store = ProtectedFeedStore(memory)
        let value = calendar(now: Date().addingTimeInterval(-3600))
        try await store.save(value, key: "calendar.snapshot.\(value.scope)")
        let feed = OptionalLeagueFeed<LeagueCalendarSnapshot>(scope: value.scope, key: "calendar.snapshot", ttl: 900, store: store) { _ in
            throw URLError(.notConnectedToInternet)
        }
        await feed.refresh()
        #expect(feed.snapshot?.fetchedAt == value.fetchedAt)
        #expect(feed.errorMessage != nil)
        let other = OptionalLeagueFeed<LeagueCalendarSnapshot>(scope: "other", key: "calendar.snapshot", ttl: 900, store: store) { _ in value }
        await other.refresh()
        #expect(other.snapshot == nil)
    }

    private func calendar(now: Date) -> LeagueCalendarSnapshot {
        let source = MFLLeagueCalendar(events: [
            .init(id: "waiver", type: "WAIVER_BBID", start: now.addingTimeInterval(2 * 86_400)),
            .init(id: "trade", type: "TRADE", start: now.addingTimeInterval(9 * 86_400)),
            .init(id: "later", type: "TRADE", start: now.addingTimeInterval(40 * 86_400))
        ])
        return LeagueCalendarSnapshot(scope: "2026.12345.0001", source: MFLCalendarOccurrences(calendar: source, ics: nil), fetchedAt: now)
    }

    @Test("Denied notification permission never saves an enabled reminder or asks again")
    @MainActor func deniedReminders() async {
        let notifications = RecordingDeadlineNotifications(permission: .denied)
        let model = LeagueCalendarModel(repository: DemoLeagueRepository(), workspace: SampleData.workspace,
            store: ProtectedFeedStore(MemoryPrivateStore()), notifications: notifications)
        await model.setCategory(.waivers, lead: .hour)
        #expect(!model.preferences.hasEnabledReminders)
        #expect(model.notice != nil)
        #expect(await notifications.permissionRequests == 0)
        #expect(await notifications.reconciliations == 0)
    }

    @Test("A failed preference restore preserves alerts and can recover on the next open")
    @MainActor func reminderRestoreRecovery() async throws {
        let privateStore = RecoverableReminderStore()
        let saved = DeadlinePreferences(categories: [.waivers: .hour])
        try privateStore.encode(saved, key: "calendar.reminders.\(SampleData.workspace.storageScope)")
        let notifications = RecordingDeadlineNotifications(permission: .allowed)
        let model = LeagueCalendarModel(repository: DemoLeagueRepository(), workspace: SampleData.workspace,
            store: ProtectedFeedStore(privateStore), notifications: notifications)
        await model.refresh()
        #expect(await notifications.reconciliations == 0)
        #expect(await notifications.clears == 0)
        #expect(model.notice != nil)
        privateStore.allowReads()
        await model.refresh()
        #expect(model.preferences.categories[.waivers] == .hour)
        #expect(await notifications.reconciliations == 1)
        await model.setCategory(.waivers, lead: nil)
        #expect(!model.preferences.hasEnabledReminders)
        #expect(await notifications.optOuts == 1)
        #expect(await notifications.clears == 1)
        await model.disconnect()
        await model.refresh()
        #expect(await notifications.reconciliations == 1)
        #expect(await notifications.clears == 2)
    }
    private func connected(_ transport: BlockFixtureTransport, store: MemoryPrivateStore = MemoryPrivateStore()) async throws -> LiveMFLRepository {
        try store.encode(SavedSession(cookie: "synthetic-cookie", season: 2026, leagueID: "41333", franchiseID: "0001"), key: "session")
        let repository = LiveMFLRepository(privateStore: store, transport: transport, requestInterval: .zero)
        _ = try await repository.restoreSession()
        return repository
    }
}

private actor RecordingDeadlineNotifications: DeadlineNotificationService {
    let permission: DeadlineAuthorization
    var permissionRequests = 0
    var reconciliations = 0
    var clears = 0
    var optOuts = 0
    init(permission: DeadlineAuthorization) { self.permission = permission }
    func authorization() -> DeadlineAuthorization { permission }
    func requestPermission() -> Bool { permissionRequests += 1; return false }
    func reconcile(_ reminders: [PlannedDeadlineReminder], scope: String, complete: Bool) { reconciliations += 1 }
    func remove(eventID: String, scope: String) {}
    func applyOptOuts(_ preferences: DeadlinePreferences, scope: String) { optOuts += 1 }
    func clear() { clears += 1 }
}

private final class RecoverableReminderStore: PrivateStore, @unchecked Sendable {
    private let lock = NSLock()
    private let memory = MemoryPrivateStore()
    private var readsAllowed = false
    func allowReads() { lock.withLock { readsAllowed = true } }
    func read(_ key: String) throws -> Data? {
        try lock.withLock {
            if !readsAllowed && key.hasPrefix("calendar.reminders.") { throw StoreError.unavailable }
            return memory.read(key)
        }
    }
    func write(_ data: Data, key: String) { memory.write(data, key: key) }
    func remove(_ key: String) { memory.remove(key) }
}

private actor BlockFixtureTransport: MFLHTTPTransport {
    let base = MutationFixtureTransport()
    var listing: MFLTradingBlockListing?
    var posts = 0
    var timeout = false
    var allowed = true
    var retainsEmptyRow = false
    var ignoresRemoval = false
    var failsReadAfterRemoval = false
    var removalAttempted = false
    func setListing(_ listing: MFLTradingBlockListing?) { self.listing = listing }
    func enableTimeout() { timeout = true }
    func denyTrading() { allowed = false }
    func keepEmptyRow(_ value: Bool) { retainsEmptyRow = value }
    func ignoreRemoval(failRead: Bool) { ignoresRemoval = true; failsReadAfterRemoval = failRead }
    func send(_ request: URLRequest) async throws -> MFLHTTPResponse {
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let type = query.first { $0.name == "TYPE" }?.value
        if type == "abilities" {
            let json = "{\"abilities\":{\"franchise\":{\"id\":\"0001\",\"ability\":[{\"id\":\"TRADES\",\"value\":\"\(allowed ? 1 : 0)\"},{\"id\":\"FDP_TRADES\",\"value\":\"1\"}]}}}"
            return MFLHTTPResponse(data: Data(json.utf8), statusCode: 200, url: request.url)
        }
        if type == "tradeBait" {
            if request.httpMethod == "POST" {
                posts += 1
                var parts = URLComponents()
                parts.percentEncodedQuery = String(data: request.httpBody ?? Data(), encoding: .utf8)?.replacingOccurrences(of: "+", with: "%20")
                let fields = parts.queryItems ?? []
                let next = MFLTradingBlockListing(id: "0001", codes: Set((fields.first { $0.name == "WILL_GIVE_UP" }?.value ?? "").split(separator: ",").map(String.init)),
                    lookingFor: fields.first { $0.name == "IN_EXCHANGE_FOR" }?.value ?? "")
                removalAttempted = next.codes.isEmpty
                if !removalAttempted || !ignoresRemoval {
                    listing = removalAttempted && !retainsEmptyRow ? nil : next
                }
                if timeout { throw URLError(.timedOut) }
                return MFLHTTPResponse(data: Data(#"{"status":"OK"}"#.utf8), statusCode: 200, url: request.url)
            }
            if removalAttempted && failsReadAfterRemoval { throw URLError(.notConnectedToInternet) }
            struct Envelope: Encodable { let tradeBaits: MFLTradingBlock }
            let data = try JSONEncoder().encode(Envelope(tradeBaits: MFLTradingBlock(listings: listing.map { [$0] } ?? [])))
            return MFLHTTPResponse(data: data, statusCode: 200, url: request.url)
        }
        return try await base.send(request)
    }
}
