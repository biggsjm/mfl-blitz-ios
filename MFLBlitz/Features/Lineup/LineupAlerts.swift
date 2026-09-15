import SwiftUI
import UserNotifications
import Security

struct LineupAlertOptions: Codable, Equatable, Sendable {
    var reminder = false
    var unavailable = false
    var incomplete = false
    var enabled: Bool { reminder || unavailable || incomplete }
}

@MainActor @Observable
final class LineupPushToken {
    static let shared = LineupPushToken()
    var token: String?
    var failed = false
}

final class BlitzNotificationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        LineupPushToken.shared.token = deviceToken.map { String(format: "%02x", $0) }.joined()
        LineupPushToken.shared.failed = false
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        LineupPushToken.shared.failed = true
    }
}

@MainActor
protocol LineupNotificationAccess {
    var token: String? { get }
    var failed: Bool { get }
    func authorization() async -> UNAuthorizationStatus
    func requestPermission() async throws
    func register()
}

private struct SystemLineupNotificationAccess: LineupNotificationAccess {
    var token: String? { LineupPushToken.shared.token }
    var failed: Bool { LineupPushToken.shared.failed }
    func authorization() async -> UNAuthorizationStatus { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    func requestPermission() async throws { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
    func register() { UIApplication.shared.registerForRemoteNotifications() }
}

@MainActor @Observable
final class LineupAlertController {
    typealias Sender = @Sendable (_ address: String, _ path: String, _ method: String, _ secret: String, _ body: Data?) async throws -> Data
    struct Registration: Codable, Equatable {
        var id: String
        var scope: String
        var address: String
        var expires: Double
        var token: String? = nil
    }
    struct Saved: Codable {
        var secret: String
        var options: [String: LineupAlertOptions] = [:]
        var current: Registration?
        var pending: [Registration] = []
        var revision: Int64 = 0
    }
    private let store: any PrivateStore
    private let notifications: any LineupNotificationAccess
    private let send: Sender
    private var saved: Saved?
    private var scope: String?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var lastFingerprint: Data?
    private var lastSent = Date.distantPast
    private(set) var options = LineupAlertOptions()
    private(set) var message = "Off"
    private(set) var busy = false
    private(set) var permissionRequired = false
    private(set) var needsCurrentLineup = false
    private(set) var acknowledgedWeek: Int?
    private(set) var acknowledgedUntil: Date?
    func coverageTitle(week: Int, now: Date = Date()) -> String {
        if saved?.pending.isEmpty == false && !options.enabled { return "Alerts turning off…" }
        guard options.enabled else { return "Lineup alerts off" }
        if permissionRequired { return "Alerts need notification permission" }
        if acknowledgedWeek == week, let until = acknowledgedUntil, until > now {
            return "Alerts connected · Week \(week)"
        }
        return busy ? "Connecting lineup alerts…" : "Alerts need attention · Week \(week)"
    }
    init(store: any PrivateStore = KeychainPrivateStore(), notifications: (any LineupNotificationAccess)? = nil,
         send: @escaping Sender = { address, path, method, secret, body in
             try await MatchupSyncClient(address: address).send(path: path, method: method, secret: secret, body: body)
         }) {
        self.store = store; self.notifications = notifications ?? SystemLineupNotificationAccess(); self.send = send
    }
    private func load() throws {
        guard saved == nil else { return }
        if let value = try store.decode(Saved.self,key:"lineup-alerts.v1") { saved = value; return }
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else { throw StoreError.unavailable }
        saved = Saved(secret:bytes.map { String(format:"%02x",$0) }.joined())
    }
    private func persist() throws {
        saved?.pending.removeAll { $0.expires <= Date().timeIntervalSince1970 }
        if let saved { try store.encode(saved,key:"lineup-alerts.v1") }
    }
    func open(scope: String?, preview: Bool) {
        guard self.scope != scope || saved == nil else { return }
        self.scope = scope
        acknowledgedWeek = nil; acknowledgedUntil = nil
        if preview { options = .init(); message = "Preview · notifications stay off"; return }
        do {
            try load()
            if let current=saved?.current,current.scope != scope {
                task?.cancel(); saved?.pending.append(current); saved?.current=nil;try persist()
            }
            options = scope.flatMap { saved?.options[$0] } ?? .init(); message = options.enabled ? "Checking notification connection…" : "Off" }
        catch { options = .init(); message = "Unlock your phone to load notification settings." }
    }
    func set(_ value: LineupAlertOptions, model: AppModel) async {
        guard let scope=model.workspace?.storageScope, !model.isDemo else { return }
        open(scope:scope,preview:false)
        do {
            try load(); options=value; saved?.options[scope]=value
            acknowledgedWeek=nil; acknowledgedUntil=nil
            // Revoke the old registration before any replacement can be queued.
            task?.cancel(); lastFingerprint=nil
            if let old=saved?.current { saved?.pending.append(old); saved?.current=nil }
            try persist()
            await reconcile(model:model,requestPermission:value.enabled)
        } catch { message="Notification settings couldn’t be saved. Unlock your phone and try again." }
    }
    func reconcile(model: AppModel, requestPermission: Bool = false) async {
        guard !model.isDemo else { return }
        open(scope:model.workspace?.storageScope,preview:false)
        do { try load() } catch { return }
        guard task == nil || task?.isCancelled == true else { return }
        generation += 1
        let requestGeneration=generation
        task=Task { [weak self] in
            guard let self else { return }
            self.busy=true
            defer { if self.generation==requestGeneration { self.busy=false; self.task=nil } }
            await self.cleanup()
            guard !Task.isCancelled else { return }
            guard self.options.enabled else { self.message=self.saved?.pending.isEmpty == false ? "Off on this phone · server removal pending; reconnect Tailscale" : "Off"; return }
            var authorization=await self.notifications.authorization()
            if authorization == .notDetermined, requestPermission {
                try? await self.notifications.requestPermission()
                authorization=await self.notifications.authorization()
            }
            guard authorization == .authorized || authorization == .provisional else {
                self.permissionRequired=true; self.acknowledgedWeek=nil; self.acknowledgedUntil=nil
                if let old=self.saved?.current {
                    self.saved?.pending.append(old);self.saved?.current=nil;try? self.persist();await self.cleanup()
                }
                self.message="Allow notifications in iPhone Settings to receive lineup alerts."; return
            }
            self.permissionRequired=false
            guard let workspace=model.workspace, !model.isUsingCachedSession, model.lineup.week==model.currentWeek,
                  (1...18).contains(model.currentWeek), !model.isLoadingLineup else {
                self.needsCurrentLineup=true
                self.message="Open your current lineup to connect alerts for this week."; return
            }
            self.needsCurrentLineup=false
            guard !Task.isCancelled,workspace.storageScope==self.scope else { return }
            self.notifications.register()
            guard let token=self.notifications.token else { self.message=self.notifications.failed ? "Apple notifications couldn’t connect. Retry when online." : "Connecting Apple notifications…"; return }
            let address=model.matchupActivity.backgroundSync.address
            do {
                var profiles: [String:[String:String]]=[:]
                for player in model.lineup.players {
                    let team=NFLFeedGame.team(player.nflTeam)
                    guard (2...3).contains(team.count),team.allSatisfy(\.isASCII),team.allSatisfy(\.isLetter) else { continue }
                    profiles[player.id]=["name":String(player.name.prefix(80)),"team":team]
                }
                guard !profiles.isEmpty else { self.message="Your roster hasn’t loaded yet."; return }
                #if DEBUG
                let environment="sandbox"
                #else
                let environment="production"
                #endif
                struct Body: Encodable {
                    var season:Int; var leagueID:String; var franchiseID:String; var week:Int; var required:Int
                    var token:String; var environment:String; var options:LineupAlertOptions
                    var players:[String:[String:String]]; var revision:Int64
                }
                var body=Body(season:workspace.season,leagueID:workspace.leagueID,franchiseID:workspace.franchiseID,
                    week:model.currentWeek,required:model.lineup.requiredStarterCount,token:token,environment:environment,
                    options:self.options,players:profiles,revision:0)
                let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
                let fingerprint=try encoder.encode(body)
                if self.lastFingerprint==fingerprint,Date().timeIntervalSince(self.lastSent)<3600,
                   self.saved?.current != nil, self.acknowledgedWeek == body.week,
                   (self.acknowledgedUntil ?? .distantPast) > Date() { return }
                guard !Task.isCancelled,workspace.storageScope==self.scope else { return }
                if let old=self.saved?.current, old.address != address || old.token != token || old.expires <= Date().timeIntervalSince1970 {
                    self.saved?.pending.append(old);self.saved?.current=nil
                }
                guard (self.saved?.pending.count ?? 0)<8 else { throw SyncError.connection }
                if self.saved?.current == nil { self.saved?.current = Registration(id:UUID().uuidString,scope:workspace.storageScope,address:address,expires:Date().addingTimeInterval(8*86400).timeIntervalSince1970,token:token) }
                // Read before opening the optional's modify access. Reading
                // saved again inside saved?.revision = ... traps exclusivity.
                let previousRevision=self.saved?.revision ?? 0
                guard previousRevision < Int64.max else { throw SyncError.connection }
                let revision=max(previousRevision+1,Int64(Date().timeIntervalSince1970*1000))
                self.saved?.revision=revision
                body.revision=revision
                try self.persist()
                guard let entry=self.saved?.current,let secret=self.saved?.secret else { return }
                let data=try await self.send(address,"v1/lineup-alerts/\(entry.id)","PUT",secret,encoder.encode(body))
                let receipt=try JSONDecoder().decode(MatchupSyncClient.Receipt.self,from:data)
                guard !Task.isCancelled, self.saved?.current?.id==entry.id else { return }
                guard receipt.registered,receipt.expiresAt.isFinite,receipt.expiresAt>Date().timeIntervalSince1970 else { throw SyncError.connection }
                self.saved?.current?.expires=receipt.expiresAt
                self.lastFingerprint=fingerprint;self.lastSent=Date();try self.persist()
                self.message=receipt.pushReady ? "Connected for Week \(body.week) · checks saved starters before kickoff" : "Server connected · Apple push setup needs attention"
                self.acknowledgedWeek = receipt.pushReady ? body.week : nil
                self.acknowledgedUntil = receipt.pushReady ? Date(timeIntervalSince1970: receipt.expiresAt) : nil
                await self.cleanup()
            } catch { if !Task.isCancelled {
                self.acknowledgedWeek=nil; self.acknowledgedUntil=nil
                self.message="Alerts couldn’t connect. Check Tailscale, then retry."
            } }
        }
        await task?.value
    }
    private func cleanup() async {
        guard let state=saved else { return }
        for entry in state.pending {
            do {
                if entry.expires>Date().timeIntervalSince1970 {
                    _ = try await send(entry.address,"v1/lineup-alerts/\(entry.id)","DELETE",state.secret,nil)
                }
                saved?.pending.removeAll { $0.id==entry.id };try persist()
            } catch { message="Server removal pending. Reconnect Tailscale to finish turning alerts off." }
        }
    }
    func disconnect() async {
        task?.cancel()
        do {
            try load()
            if let scope { saved?.options[scope]=nil }
            options = .init()
            if let old=saved?.current { saved?.pending.append(old);saved?.current=nil }
            try persist();await cleanup()
        } catch { message="Server removal pending. Alerts expire automatically after eight days." }
        lastFingerprint=nil;scope=nil
        acknowledgedWeek=nil;acknowledgedUntil=nil
    }
}

struct LineupAlertSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var showInfo = false
    var body: some View {
        Form {
            Section {
                Text(model.lineupAlerts.coverageTitle(week: model.currentWeek)).font(.headline)
                if model.lineupAlerts.permissionRequired {
                    Button("Open iPhone Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                } else if model.lineupAlerts.needsCurrentLineup {
                    Button("Open current lineup") {
                        if let url = URL(string: "mflblitz://lineup?scope=\(model.workspace?.storageScope ?? "")&id=lineup&week=\(model.currentWeek)") { openURL(url) }
                    }
                } else if model.lineupAlerts.options.enabled || model.lineupAlerts.message.contains("pending") {
                    Button("Retry connection") { Task { await model.lineupAlerts.reconcile(model: model) } }
                        .disabled(model.lineupAlerts.busy || model.isDemo)
                }
            }
            Section {
                toggle("Pre-kickoff reminder",path:\.reminder)
                toggle("Unavailable starters",path:\.unavailable)
                toggle("Incomplete lineup",path:\.incomplete)
            } footer: {
                Text("Checks your saved lineup before kickoff. Open the current lineup each week to renew alerts.")
            }
            Section {
                DisclosureGroup("Connection details") {
                    Text(model.lineupAlerts.message).font(.subheadline)
                    if let expires = model.lineupAlerts.acknowledgedUntil {
                        Text("Coverage expires \(expires.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Lineup alerts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("About lineup alerts", systemImage: "info.circle") { showInfo = true }
                    .popover(isPresented: $showInfo) {
                        Text("Alerts check your saved starters in the 30 minutes before kickoff. Unavailable means MFL reports Out, IR or Inactive; its injury report isn’t live. Incomplete means too few saved starters. Turning alerts off needs a connection to finish. Delivery isn’t guaranteed.")
                            .font(.subheadline).padding().frame(idealWidth: 280).presentationCompactAdaptation(.popover)
                    }
            }
        }
        .task { model.lineupAlerts.open(scope:model.workspace?.storageScope,preview:model.isDemo);await model.lineupAlerts.reconcile(model:model) }
    }
    private func toggle(_ title:String,path:WritableKeyPath<LineupAlertOptions,Bool>) -> some View {
        Toggle(title,isOn:Binding(get:{ model.lineupAlerts.options[keyPath:path] },set:{ enabled in
            var value=model.lineupAlerts.options;value[keyPath:path]=enabled
            Task { await model.lineupAlerts.set(value,model:model) }
        })).disabled(model.lineupAlerts.busy || model.isDemo)
    }
}
