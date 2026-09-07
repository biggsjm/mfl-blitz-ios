import CryptoKit
import Foundation

/// Presentation only. Never a source of permissions, preflight or readback.
struct CachedDisplayValue<Value: Codable & Sendable>: Codable, Sendable {
    var value: Value
    var savedAt: Date
    func isUsable(now: Date) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return age >= 0 && age < 7 * 86_400
    }
}

struct LeagueDisplaySnapshot: Codable, Sendable {
    var version = 1
    var identity: String
    var workspace: LeagueWorkspace
    var savedAt: Date
    var scores: CachedDisplayValue<ScoresSnapshot>?
    var lineup: CachedDisplayValue<LineupSnapshot>?
    var standings: CachedDisplayValue<[StandingRow]>?
    var teams: CachedDisplayValue<[TeamSummary]>?
    var roster: CachedDisplayValue<TeamRosterSnapshot>?
    var board: CachedDisplayValue<[BoardThread]>?
}

enum LeagueDisplayUpdate: Sendable {
    case scores(ScoresSnapshot), lineup(LineupSnapshot), standings([StandingRow])
    case teams([TeamSummary]), roster(TeamRosterSnapshot), board([BoardThread])
}

/// All encoding and file IO stay off the main actor. One bounded, protected,
/// non-backed-up file is bound to the exact saved session, season and franchise.
actor LeagueDisplayCache {
    private let fileURL: URL
    private let privateStore: any PrivateStore
    private var memory: LeagueDisplaySnapshot?
    static let maximumBytes = 4 * 1_024 * 1_024

    init(fileURL: URL, privateStore: any PrivateStore) {
        self.fileURL = fileURL
        self.privateStore = privateStore
    }

    static func identity(for session: SavedSession) -> String {
        let value = "\(session.season)|\(session.leagueID)|\(session.franchiseID)|\(session.cookie)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func identity(for workspace: LeagueWorkspace) -> String? {
        guard let session = try? privateStore.decode(SavedSession.self, key: "session"),
              session.season == workspace.season, session.leagueID == workspace.leagueID,
              session.franchiseID == workspace.franchiseID else { return nil }
        return Self.identity(for: session)
    }

    func load(now: Date = Date()) -> LeagueDisplaySnapshot? {
        guard let session = try? privateStore.decode(SavedSession.self, key: "session"),
              let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumBytes,
              let data = try? Data(contentsOf: fileURL),
              var snapshot = try? JSONDecoder().decode(LeagueDisplaySnapshot.self, from: data),
              snapshot.version == 1, snapshot.identity == Self.identity(for: session),
              snapshot.workspace.season == session.season,
              snapshot.workspace.leagueID == session.leagueID,
              snapshot.workspace.franchiseID == session.franchiseID,
              snapshot.savedAt <= now, now.timeIntervalSince(snapshot.savedAt) < 7 * 86_400 else { return nil }
        if snapshot.scores?.isUsable(now: now) != true { snapshot.scores = nil }
        if snapshot.lineup?.isUsable(now: now) != true { snapshot.lineup = nil }
        if snapshot.standings?.isUsable(now: now) != true { snapshot.standings = nil }
        if snapshot.teams?.isUsable(now: now) != true { snapshot.teams = nil }
        if snapshot.roster?.isUsable(now: now) != true { snapshot.roster = nil }
        if snapshot.board?.isUsable(now: now) != true { snapshot.board = nil }
        memory = snapshot
        return snapshot
    }

    func save(workspace: LeagueWorkspace, identity expected: String,
              update: LeagueDisplayUpdate, now: Date = Date()) {
        // A suspended read from a signed-out/replaced account must not recreate its cache.
        guard identity(for: workspace) == expected else { return }
        var snapshot = memory.flatMap { $0.identity == expected ? $0 : nil }
            ?? LeagueDisplaySnapshot(identity: expected, workspace: workspace, savedAt: now)
        snapshot.workspace = workspace
        snapshot.savedAt = now
        switch update {
        case .scores(let value): snapshot.scores = CachedDisplayValue(value: value, savedAt: now)
        case .lineup(var value):
            value.editState = .unavailable("Updating your lineup…")
            snapshot.lineup = CachedDisplayValue(value: value, savedAt: now)
        case .standings(let value): snapshot.standings = CachedDisplayValue(value: value, savedAt: now)
        case .teams(let value): snapshot.teams = CachedDisplayValue(value: value, savedAt: now)
        case .roster(var value):
            guard value.scope == workspace.storageScope, value.team.id == workspace.franchiseID,
                  value.lineupWeek == nil else { return }
            value.rosterVerifiedAt = nil
            snapshot.roster = CachedDisplayValue(value: value, savedAt: now)
        case .board(var value):
            // Keep only the already-visible inbox summary, not full private conversations.
            for index in value.indices { value[index].posts = [] }
            snapshot.board = CachedDisplayValue(value: value, savedAt: now)
        }
        guard let data = try? JSONEncoder().encode(snapshot), data.count <= Self.maximumBytes else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var location = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try location.setResourceValues(values)
            memory = snapshot
        } catch { /* Cache failure must never fail a successful league read. */ }
    }

    func clear() {
        memory = nil
        try? FileManager.default.removeItem(at: fileURL)
    }
}
