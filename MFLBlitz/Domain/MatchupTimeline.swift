import Foundation
import Observation
import CryptoKit

struct MatchupTimelineEvent: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var at: Double
    var kind: String
    var name: String
    var teamID: String?
    var playerID: String?
    var previous: Double?
    var current: Double?
    var source: String
    var fromAt: Double? = nil
    var date: Date { Date(timeIntervalSince1970: at) }
}

struct MatchupTimelineResponse: Decodable, Sendable {
    let schema: Int
    let season: Int
    let leagueID: String
    let week: Int
    let teamIDs: [String]
    let checkedAt: Double?
    let events: [MatchupTimelineEvent]
}

struct MatchupTimelineArchive: Codable, Sendable {
    var scope: String
    var revision = 0
    var events: [String: [MatchupTimelineEvent]] = [:]
    var baseline: [String: Matchup] = [:]
    var receipts: [String: Double] = [:]
}

actor MatchupTimelineDisk {
    private let url: URL?
    private var revision = -1
    init(url: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appending(path: "MFLBlitz/matchup-timeline.json")) { self.url = url }
    func load(scope: String) -> MatchupTimelineArchive? {
        guard let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8_000_000,
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(MatchupTimelineArchive.self, from: data),
              value.scope == scope else { return nil }
        revision = max(revision,value.revision)
        return value
    }
    func save(_ value: MatchupTimelineArchive) throws {
        guard let url, value.revision >= revision else { return }
        revision = value.revision
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var mutable = directory; var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try mutable.setResourceValues(flags)
        let data = try JSONEncoder().encode(value)
        guard data.count <= 8_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func clear(revision: Int) throws {
        self.revision = max(self.revision,revision)
        if let url, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

@MainActor @Observable
final class MatchupTimelineStore {
    private var archive = MatchupTimelineArchive(scope: "")
    private let disk: MatchupTimelineDisk
    private var opening: Task<MatchupTimelineArchive?, Never>?
    private var lastRemote: [String: Date] = [:]
    private var reading = Set<String>()
    private(set) var issue: String?
    init(disk: MatchupTimelineDisk = MatchupTimelineDisk()) { self.disk = disk }
    static func key(week: Int, matchup: Matchup) -> String { "\(week).\([matchup.away.id,matchup.home.id].sorted().joined(separator: "."))" }
    func events(scope: String?, week: Int, matchup: Matchup) -> [MatchupTimelineEvent] {
        guard scope == archive.scope else { return [] }
        return archive.events[Self.key(week: week,matchup: matchup)] ?? []
    }
    private func open(scope: String, persist: Bool) async {
        if archive.scope != scope {
            opening?.cancel()
            archive = MatchupTimelineArchive(scope: scope, revision: archive.revision+1)
            lastRemote = [:]; reading = []; issue = nil
            opening = persist ? Task { await disk.load(scope: scope) } : nil
        }
        if let task = opening {
            let loaded = await task.value
            guard archive.scope == scope else { return }
            if let loaded, archive.events.isEmpty { archive = loaded }
            opening = nil
        }
    }
    func observe(_ snapshot: ScoresSnapshot, scope: String, persist: Bool, now: Date = Date()) async {
        guard let date = snapshot.checkedAt, date <= now, now.timeIntervalSince(date) < 210 else { return }
        await open(scope: scope,persist: persist)
        guard archive.scope == scope else { return }
        for matchup in snapshot.matchups {
            let key = Self.key(week: snapshot.week,matchup: matchup), at = date.timeIntervalSince1970
            if let previous = archive.receipts[key], at <= previous { continue }
            var entries = archive.events[key] ?? []
            func add(_ kind: String, _ name: String, team: String? = nil, player: String? = nil, previous: Double? = nil, current: Double? = nil) {
                entries.append(.init(id: "local-\(key)-\(at)-\(kind)-\(team ?? "")-\(player ?? "")",at: at,kind: kind,name: name,
                    teamID: team,playerID: player,previous: previous,current: current,source: "app",fromAt:archive.receipts[key]))
            }
            if let previous = archive.baseline[key] {
                if at-(archive.receipts[key] ?? at) >= 210,
                   Self.needsGap(previous: previous, current: matchup, at: date) {
                    add("gap","Updates were unavailable between saved checks")
                }
                for team in [matchup.away,matchup.home] {
                    guard let old = [previous.away,previous.home].first(where: { $0.id == team.id }) else { continue }
                    if let a=old.reportedScore, let b=team.reportedScore, a.isFinite, b.isFinite, a != b {
                        add("team",team.name+" total",team: team.id,previous: a,current: b)
                    }
                    guard Set(old.starters.map(\.id)) == Set(team.starters.map(\.id)),
                          old.unclassifiedPlayers.isEmpty,team.unclassifiedPlayers.isEmpty else { continue }
                    for player in team.starters {
                        if let a=old.starters.first(where: { $0.id==player.id })?.livePoints, let b=player.livePoints,
                           a.isFinite,b.isFinite,a != b { add("player",player.name,team: team.id,player: player.id,previous: a,current: b) }
                    }
                }
            } else { add("tracking","Recording started from the first saved score") }
            archive.events[key] = Array(entries.filter { now.timeIntervalSince1970-$0.at < 21*86400 }.sorted { $0.at > $1.at }.prefix(2000))
            archive.baseline[key] = matchup; archive.receipts[key] = at
        }
        await save(persist: persist)
    }
    static func needsGap(previous: Matchup, current: Matchup, at: Date) -> Bool {
        let old = previous.away.starters + previous.home.starters
        let new = current.away.starters + current.home.starters
        guard !old.isEmpty, Set(old.map(\.id)) == Set(new.map(\.id)),
              previous.away.unclassifiedPlayers.isEmpty, previous.home.unclassifiedPlayers.isEmpty,
              current.away.unclassifiedPlayers.isEmpty, current.home.unclassifiedPlayers.isEmpty else { return true }
        if previous.status == .final, current.status == .final,
           old.allSatisfy({ $0.gameState == .final }), new.allSatisfy({ $0.gameState == .final }) { return false }
        if case .pregame(let beforeKickoff) = previous.status, case .pregame(let nextKickoff) = current.status,
           let beforeKickoff, beforeKickoff == nextKickoff, at < beforeKickoff,
           old.allSatisfy({ $0.gameState == .pregame }), new.allSatisfy({ $0.gameState == .pregame }) { return false }
        return true
    }
    func refresh(workspace: LeagueWorkspace, week: Int, matchup: Matchup, address: String, preview: Bool) async {
        let scope = workspace.storageScope, key = Self.key(week: week,matchup: matchup)
        await open(scope: scope,persist: !preview)
        guard archive.scope == scope, !preview, !reading.contains(key),
              lastRemote[key].map({ Date().timeIntervalSince($0) >= 30 }) ?? true else { return }
        reading.insert(key); lastRemote[key] = Date()
        defer { if archive.scope == scope { reading.remove(key) } }
        do {
            let response = try await MatchupSyncClient(address: address).timeline(season: workspace.season,leagueID: workspace.leagueID,
                week: week,away: matchup.away.id,home: matchup.home.id)
            guard archive.scope == scope, !Task.isCancelled else { return }
            let remote = response.events
            let local = Self.localEventsToKeep(archive.events[key] ?? [], response:response)
            archive.events[key] = Array((local+remote).filter { Date().timeIntervalSince1970-$0.at < 21*86400 }
                .sorted { $0.at > $1.at }.prefix(2000))
            if archive.receipts[key] == nil { archive.receipts[key] = response.checkedAt ?? remote.map(\.at).max() }
            issue = nil
            await save(persist: true)
        } catch { if archive.scope == scope, !Task.isCancelled { issue = "Background history couldn’t refresh. Saved updates remain available." } }
    }
    /// Prefer continuous background coverage over an aggregate foreground delta
    /// after reopening. Keep local observations inside an actual server gap.
    static func localEventsToKeep(_ events:[MatchupTimelineEvent], response:MatchupTimelineResponse) -> [MatchupTimelineEvent] {
        let ordered=response.events.sorted { $0.at == $1.at ? ($0.kind=="gap" && $1.kind != "gap") : $0.at < $1.at }
        var intervals:[ClosedRange<Double>]=[]
        if var start=ordered.first?.at, let end=response.checkedAt {
            var previous=start
            for event in ordered {
                if event.kind=="gap" {
                    if previous>=start { intervals.append(start...previous) }
                    start=event.at
                }
                previous=event.at
            }
            if end>=start { intervals.append(start...end) }
        }
        let remoteIDs=Set(ordered.map(\.id))
        return events.filter { event in
            if remoteIDs.contains(event.id) { return false }
            guard event.source=="app" else { return true }
            if let from=event.fromAt, intervals.contains(where:{ $0.contains(from) && $0.contains(event.at) }) { return false }
            return !ordered.contains { $0.kind==event.kind && $0.teamID==event.teamID && $0.playerID==event.playerID &&
                $0.previous==event.previous && $0.current==event.current && abs($0.at-event.at)<210 }
        }
    }
    private func save(persist: Bool) async {
        let expired = archive.receipts.filter { Date().timeIntervalSince1970-$0.value >= 21*86400 }.map(\.key)
        let excess = archive.receipts.sorted { $0.value > $1.value }.dropFirst(12).map(\.key)
        for key in Set(expired+excess) { archive.receipts[key] = nil; archive.events[key] = nil; archive.baseline[key] = nil }
        archive.revision += 1
        if persist {
            do { try await disk.save(archive) } catch { issue = "Timeline changes couldn’t be saved on this device." }
        }
    }
    func clear() async {
        opening?.cancel(); opening = nil
        let revision=archive.revision+1
        archive=MatchupTimelineArchive(scope:"",revision:revision); lastRemote=[:]; reading=[]
        do { try await disk.clear(revision:revision) } catch { issue="Saved history couldn’t be removed." }
    }
}
