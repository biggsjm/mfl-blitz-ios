import Foundation
import Testing
import UserNotifications
@testable import MFLBlitz

@MainActor private final class AlertNotificationStub: LineupNotificationAccess {
    var token: String? = String(repeating: "a", count: 64)
    var failed = false
    var status: UNAuthorizationStatus = .notDetermined
    var permissionRequests = 0
    var registrations = 0
    var permissionFailure = false
    func authorization() async -> UNAuthorizationStatus { status }
    func requestPermission() async throws {
        permissionRequests += 1
        if permissionFailure { throw URLError(.unknown) }
        status = .authorized
    }
    func register() { registrations += 1 }
}

private actor AlertTransportStub {
    struct Request: Sendable { var path: String; var method: String; var body: Data? }
    var requests: [Request] = []
    var failing = false
    func setFailure(_ value: Bool) { failing = value }
    func send(_ address: String, _ path: String, _ method: String, _ secret: String, _ body: Data?) throws -> Data {
        requests.append(.init(path: path, method: method, body: body))
        if failing { throw URLError(.notConnectedToInternet) }
        return try JSONSerialization.data(withJSONObject: ["registered": true, "pushReady": true, "expiresAt": Date().addingTimeInterval(8*86400).timeIntervalSince1970])
    }
}

@MainActor struct LineupAlertControllerTests {
    private func model() -> AppModel {
        let model = AppModel(repository: ReliabilityRepository(), privateStore: MemoryPrivateStore())
        model.workspace = SampleData.workspace; model.lineup = SampleData.lineup; model.currentWeek = model.lineup.week
        return model
    }
    private func controller(_ store: MemoryPrivateStore, _ access: AlertNotificationStub, _ transport: AlertTransportStub) -> LineupAlertController {
        LineupAlertController(store: store, notifications: access, send: { try await transport.send($0, $1, $2, $3, $4) })
    }

    @Test func enableAndRelaunchRegisterWithoutExclusivityCrash() async throws {
        let store = MemoryPrivateStore(), access = AlertNotificationStub(), transport = AlertTransportStub(), model = model()
        let first = controller(store, access, transport)
        await first.set(.init(reminder: true, unavailable: false, incomplete: true), model: model)
        #expect(first.message.hasPrefix("Connected for Week")); #expect(!first.busy)
        #expect(first.coverageTitle(week: model.currentWeek) == "Alerts connected · Week \(model.currentWeek)")
        #expect(!first.coverageTitle(week: model.currentWeek + 1).contains("connected"))
        #expect(!first.coverageTitle(week: model.currentWeek, now: Date().addingTimeInterval(9*86400)).contains("connected"))
        #expect(access.permissionRequests == 1)
        let saved = try #require(try store.decode(LineupAlertController.Saved.self, key: "lineup-alerts.v1"))
        let firstRegistration = try #require(saved.current)
        #expect(saved.revision > 0)
        let restarted = controller(store, access, transport)
        await restarted.reconcile(model: model)
        let resumed = try #require(try store.decode(LineupAlertController.Saved.self, key: "lineup-alerts.v1"))
        #expect(restarted.message.hasPrefix("Connected for Week")); #expect(!restarted.busy)
        #expect(resumed.current?.id == firstRegistration.id); #expect(resumed.revision > saved.revision)
        #expect(access.permissionRequests == 1)
        let requests = await transport.requests
        #expect(requests.map(\.method) == ["PUT", "PUT"])
        let data = try #require(requests.last?.body)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((body["options"] as? [String: Bool])?["incomplete"] == true)
        #expect((body["revision"] as? NSNumber)?.int64Value == resumed.revision)
        await restarted.reconcile(model: model)
        #expect(await transport.requests.count == 2) // Ordinary rereads coalesce.
    }

    @Test func firstEnableWaitsForAppleTokenThenRegisters() async throws {
        let store = MemoryPrivateStore(), access = AlertNotificationStub(), transport = AlertTransportStub(), model = model()
        access.token = nil
        let alerts = controller(store, access, transport)
        await alerts.set(.init(unavailable: true), model: model)
        #expect(alerts.message == "Connecting Apple notifications…"); #expect(await transport.requests.isEmpty)
        #expect(!alerts.coverageTitle(week: model.currentWeek).contains("connected"))
        access.token = String(repeating: "b", count: 64)
        await alerts.reconcile(model: model)
        #expect(alerts.message.hasPrefix("Connected for Week")); #expect(await transport.requests.count == 1)
    }

    @Test func failedRegistrationSurvivesRelaunchAndRetry() async throws {
        let store = MemoryPrivateStore(), access = AlertNotificationStub(), transport = AlertTransportStub(), model = model()
        await transport.setFailure(true)
        let first = controller(store, access, transport)
        await first.set(.init(incomplete: true), model: model)
        let saved = try #require(try store.decode(LineupAlertController.Saved.self, key: "lineup-alerts.v1"))
        #expect(first.message.contains("couldn’t connect")); #expect(!first.busy)
        await transport.setFailure(false)
        let restarted = controller(store, access, transport)
        await restarted.reconcile(model: model)
        let resumed = try #require(try store.decode(LineupAlertController.Saved.self, key: "lineup-alerts.v1"))
        #expect(resumed.current?.id == saved.current?.id); #expect(resumed.revision > saved.revision)
        #expect(restarted.message.hasPrefix("Connected for Week"))
    }

    @Test func deniedPermissionAndOptOutDoNotRegister() async throws {
        let store = MemoryPrivateStore(), access = AlertNotificationStub(), transport = AlertTransportStub(), model = model()
        access.status = .denied
        let alerts = controller(store, access, transport)
        await alerts.set(.init(incomplete: true), model: model)
        #expect(alerts.message.contains("Allow notifications")); #expect(await transport.requests.isEmpty)
        #expect(alerts.coverageTitle(week: model.currentWeek).contains("permission"))
        #expect(access.permissionRequests == 0)
        #expect(!alerts.canRequestPermission)
        access.status = .authorized
        await alerts.reconcile(model: model)
        await alerts.set(.init(), model: model)
        #expect(alerts.message == "Off"); #expect(!alerts.options.enabled)
        #expect(await transport.requests.map(\.method) == ["PUT", "DELETE"])
        let saved = try #require(try store.decode(LineupAlertController.Saved.self, key: "lineup-alerts.v1"))
        #expect(saved.current == nil); #expect(saved.pending.isEmpty)
    }

    @Test func restoredOptInWithUndeterminedPermissionOffersPromptAndRecovers() async throws {
        let store = MemoryPrivateStore(), access = AlertNotificationStub(), transport = AlertTransportStub(), model = model()
        let state = LineupAlertController.Saved(secret: String(repeating: "a", count: 64),
            options: [SampleData.workspace.storageScope: .init(incomplete: true)])
        try store.encode(state, key: "lineup-alerts.v1")
        let alerts = controller(store, access, transport)
        await alerts.reconcile(model: model)
        #expect(alerts.canRequestPermission)
        #expect(access.permissionRequests == 0)
        #expect(await transport.requests.isEmpty)
        await alerts.reconcile(model: model, requestPermission: true)
        #expect(access.permissionRequests == 1)
        #expect(!alerts.permissionRequired && !alerts.canRequestPermission)
        #expect(alerts.message.hasPrefix("Connected for Week"))
    }

    @Test func failedPermissionPromptRemainsRetryableWithoutSettingsDetour() async throws {
        let store = MemoryPrivateStore(), access = AlertNotificationStub(), transport = AlertTransportStub(), model = model()
        access.permissionFailure = true
        let alerts = controller(store, access, transport)
        await alerts.set(.init(incomplete: true), model: model)
        #expect(alerts.canRequestPermission)
        #expect(alerts.message.contains("prompt couldn’t open"))
        #expect(await transport.requests.isEmpty)
        access.permissionFailure = false
        await alerts.reconcile(model: model, requestPermission: true)
        #expect(access.permissionRequests == 2)
        #expect(alerts.message.hasPrefix("Connected for Week"))
    }
}
