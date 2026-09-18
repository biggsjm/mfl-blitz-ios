import Foundation
import Observation

struct NFLFeedStat: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let value: String?
    var id: String { name }
    var label: String {
        ["sk": "Sacks", "ic": "Interceptions", "fc": "Fumbles recovered", "sf": "Safeties", "#ir": "Interception return TDs", "tpa": "Total points allowed",
         "comp att": "Completions / attempts", "passing touch downs": "Passing TDs",
         "rushing touch downs": "Rushing TDs", "receiving touch downs": "Receiving TDs",
         "total rushes": "Carries", "total receptions": "Receptions", "two pt": "Two-point conversions",
         "kick return td": "Kick return TDs", "exp return td": "Extra-point return TDs"][name.lowercased()] ?? name.capitalized
    }
}
struct NFLFeedGroup: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let stats: [NFLFeedStat]
    var id: String { name }
}
struct NFLFeedPlayer: Codable, Hashable, Identifiable, Sendable {
    let providerID: Int
    let name: String
    let team: String
    let position: String?
    let groups: [NFLFeedGroup]
    var mflID: String? = nil
    var mflName: String? = nil
    var id: Int { providerID }
    var summary: String? {
        // Keep scoring events from every group. A two-group or line limit can
        // hide a receiver's TD or a quarterback's lost fumble behind yardage.
        var parts: [String] = []
        func values(_ group: String) -> [String: String] {
            let stats = groups.filter { $0.name.lowercased() == group }.flatMap(\.stats)
            return Dictionary(grouping: stats, by: { $0.name.lowercased() })
                .compactMapValues { $0.count == 1 ? $0[0].value : nil }
        }
        func append(_ value: String?, _ label: String, zero: Bool = false) {
            guard let value, !value.isEmpty else { return }
            // Retain unknown/composite source values rather than guessing a total.
            if !zero, Double(value) == 0 { return }
            let singular = ["carries": "carry", "tackles": "tackle", "sacks": "sack", "QB hits": "QB hit",
                "forced fumbles": "forced fumble", "blocked kicks": "blocked kick",
                "fumbles lost": "fumble lost", "fumbles recovered": "fumble recovered"]
            parts.append("\(value) \(Double(value) == 1 ? singular[label] ?? label : label)")
        }
        let teamDefense = values("team defense")
        for (field,label) in [("sk","sacks"),("ic","INT"),("fc","fumbles recovered"),("sf","safeties"),("#ir","INT TD"),("tpa","points allowed")] { append(teamDefense[field],label,zero: true) }
        let passing = values("passing"), rushing = values("rushing"), receiving = values("receiving")
        append(passing["comp att"], "pass")
        append(passing["yards"], "pass yd", zero: true)
        append(passing["passing touch downs"], "pass TD")
        append(passing["interceptions"], "INT thrown")
        append(passing["two pt"], "pass 2PT")
        append(rushing["total rushes"], "carries", zero: true)
        append(rushing["yards"], "rush yd", zero: true)
        append(rushing["rushing touch downs"], "rush TD")
        append(rushing["two pt"], "rush 2PT")
        append(receiving["total receptions"], "rec", zero: true)
        append(receiving["yards"], "rec yd", zero: true)
        append(receiving["receiving touch downs"], "rec TD")
        append(receiving["two pt"], "rec 2PT")

        let kicking = values("kicking")
        append(kicking["field goals"], "FG", zero: true)
        append(kicking["extra point"], "XP", zero: true)
        for (field, label) in [("1 19", "1–19"), ("20 29", "20–29"), ("30 39", "30–39"), ("40 49", "40–49"), ("50", "50+")] {
            append(kicking["field goals from \(field) yards"], "FG \(label) yd")
        }

        let defense = values("defensive"), interceptions = values("interceptions"), fumbles = values("fumbles")
        append(defense["tackles"], "tackles")
        append(defense["unassisted tackles"], "solo")
        append(defense["sacks"], "sacks")
        append(defense["tfl"], "TFL")
        append(defense["passes defended"], "passes defended")
        append(defense["qb hts"], "QB hits")
        append(defense["ff"], "forced fumbles")
        append(defense["blocked kicks"], "blocked kicks")
        append(interceptions["total interceptions"], "INT")
        append(interceptions["yards"], "INT return yd")
        append(interceptions["intercepted touch downs"] ?? defense["interceptions for touch downs"], "INT TD")
        append(fumbles["lost"], "fumbles lost")
        append(fumbles["rec"], "fumbles recovered")
        append(fumbles["rec td"], "fumble TD")

        let kicks = values("kick_returns"), punts = values("punt_returns")
        append(kicks["yards"], "kick return yd")
        // Some fields repeat in offensive/defensive and return groups. Select
        // one source for each event; never add duplicated provider totals.
        append(kicks["td"] ?? kicks["kick return td"] ?? rushing["kick return td"] ?? defense["kick return td"], "kick return TD")
        append(punts["yards"], "punt return yd")
        append(punts["td"], "punt return TD")
        append(kicks["exp return td"] ?? rushing["exp return td"] ?? defense["exp return td"], "XP return TD")
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Shorter labels only: retain every value/event from the full summary.
    var compactSummary: String? {
        let labels = ["pass yd": "PYD", "rush yd": "RYD", "rec yd": "YDS",
            "pass TD": "PTD", "rush TD": "RTD", "rec TD": "TD", "INT thrown": "INT",
            "pass 2PT": "P2PT", "rush 2PT": "R2PT", "rec 2PT": "REC2PT",
            "carries": "CAR", "carry": "CAR", "rec": "REC", "pass": "",
            "points allowed": "PA", "sacks": "SK", "sack": "SK", "safeties": "SFTY",
            "tackles": "TKL", "tackle": "TKL", "forced fumbles": "FF", "forced fumble": "FF",
            "fumbles lost": "FL", "fumble lost": "FL", "fumbles recovered": "FR", "fumble recovered": "FR",
            "passes defended": "PD", "blocked kicks": "BLK", "blocked kick": "BLK", "QB hits": "QBH", "QB hit": "QBH",
            "INT return yd": "IRYD", "kick return yd": "KRYD", "punt return yd": "PRYD",
            "kick return TD": "KRTD", "punt return TD": "PRTD", "XP return TD": "XRTD", "fumble TD": "FRTD"]
        let ordered = labels.keys.sorted { $0.count > $1.count }
        return summary?.components(separatedBy: " · ").map { part in
            guard let label = ordered.first(where: { part.hasSuffix(" " + $0) }), let short = labels[label] else { return part }
            return String(part.dropLast(label.count + 1)) + (short.isEmpty ? "" : " " + short)
        }.joined(separator: " · ")
    }

}
struct NFLFeedGame: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let season: Int
    let week: Int
    let kickoff: Double
    let status: String
    let timer: String?
    let home: String
    let away: String
    let homeScore: Double?
    let awayScore: Double?
    let checkedAt: Double
    var stale: Bool
    var players: [NFLFeedPlayer]
    let statsCheckedAt: Double?
    var statsStale: Bool
    var defenses: [NFLFeedPlayer]? = nil
    var defenseCheckedAt: Double? = nil
    var defenseStale: Bool? = nil
    var isLive: Bool { ["Q1", "Q2", "Q3", "Q4", "HT", "OT", "BT"].contains(status) }
    var isFinal: Bool { ["FT", "AOT"].contains(status) }
    var statusLabel: String {
        switch status {
        case "Q1", "Q2", "Q3", "Q4": return [status, timer].compactMap { $0 }.joined(separator: " ")
        case "HT": return "Halftime"
        case "OT": return ["Overtime", timer].compactMap { $0 }.joined(separator: " ")
        case "BT": return "Quarter break"
        case "FT": return "Final"
        case "AOT": return "Final / OT"
        case "PST": return "Postponed"
        case "CANC": return "Canceled"
        case "SUSP": return "Suspended"
        case "INT": return "Interrupted"
        case "NS": return "Upcoming"
        default: return "Status unavailable"
        }
    }
    func gameIsStale(now: Date = Date()) -> Bool {
        stale || now.timeIntervalSince1970 < checkedAt || (!isFinal && now.timeIntervalSince1970 - checkedAt > (isLive ? 120 : 1800))
    }
    func statsAreStale(now: Date = Date()) -> Bool {
        guard let statsCheckedAt else { return true }
        // Completed boxes retain their original receipt. The server controls
        // correction checks; an archived final does not expire merely with age.
        if isFinal { return statsStale || now.timeIntervalSince1970 < statsCheckedAt }
        let age = now.timeIntervalSince1970 - kickoff
        let threshold: Double = isLive ? 150 : age < 21600 ? 600 : age < 172800 ? 7200 : 172800
        return statsStale || now.timeIntervalSince1970 < statsCheckedAt || now.timeIntervalSince1970 - statsCheckedAt > threshold
    }
    static func isDefense(_ position: String) -> Bool { ["DEF","DF","DST","D/ST"].contains(position.uppercased()) }
    func statsReceipt(for player: MatchupPlayer) -> Double? { Self.isDefense(player.position) ? defenseCheckedAt : statsCheckedAt }
    func statsAreStale(for player: MatchupPlayer, now: Date = Date()) -> Bool {
        guard Self.isDefense(player.position) else { return statsAreStale(now: now) }
        guard let checked = defenseCheckedAt else { return true }
        return defenseStale != false || checked > now.timeIntervalSince1970 || (!isFinal && now.timeIntervalSince1970-checked > 300)
    }
    func player(matching player: MatchupPlayer) -> NFLFeedPlayer? {
        let team = Self.team(player.nflTeam)
        guard team == home || team == away else { return nil }
        if Self.isDefense(player.position) {
            let matches = (defenses ?? []).filter { $0.team == team && Self.isDefense($0.position ?? "") }
            return matches.count == 1 ? matches[0] : nil
        }
        let matches = players.filter {
            $0.team == team && ($0.mflID.map { $0 == player.id } ?? (Self.name($0.name) == Self.name(player.name))) &&
            ($0.mflID == nil || $0.mflName.map { Self.name($0) == Self.name(player.name) } == true) &&
            $0.position.map { Self.position($0) == Self.position(player.position) } == true
        }
        // Reviewed server translations bind both IDs and names. Other players
        // still require exact normalized identity; ambiguous matches stay absent.
        return matches.count == 1 ? matches[0] : nil
    }
    static func name(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    static func position(_ value: String) -> String { value.uppercased() == "PK" ? "K" : value.uppercased() }
    static func team(_ value: String) -> String {
        ["GB": "GBP", "NE": "NEP", "NO": "NOS", "SF": "SFO", "TB": "TBB", "KC": "KCC", "LV": "LVR", "JAX": "JAC", "WAS": "WAS"] [value.uppercased()] ?? value.uppercased()
    }
}
struct NFLWeekFeed: Codable, Sendable {
    let schema: Int
    let provider: String
    let season: Int
    let week: Int
    let fetchedAt: Double?
    let warming: Bool
    let retryAfter: Int
    var games: [NFLFeedGame]
    func game(team: String) -> NFLFeedGame? {
        let code = NFLFeedGame.team(team)
        let matches = games.filter { $0.home == code || $0.away == code }
        return matches.count == 1 ? matches[0] : nil
    }
    func validated(season: Int, week: Int, now: Date = Date()) throws -> Self {
        guard schema == 1, provider == "API-NFL", self.season == season, self.week == week,
              games.count <= 16, Set(games.map(\.id)).count == games.count,
              fetchedAt.map({ $0.isFinite && $0 > 0 && $0 <= now.timeIntervalSince1970 + 30 }) ?? games.isEmpty else { throw NFLFeedError.response }
        for game in games {
            guard game.id > 0, game.season == season, game.week == week, game.home != game.away,
                  !game.home.isEmpty, !game.away.isEmpty, game.kickoff.isFinite,
                  game.checkedAt.isFinite, game.checkedAt > 0, game.checkedAt <= now.timeIntervalSince1970 + 30,
                  game.statsCheckedAt.map({ $0.isFinite && $0 > 0 && $0 <= now.timeIntervalSince1970 + 30 }) ?? true,
                  [game.homeScore, game.awayScore].allSatisfy({ $0.map { $0.isFinite && $0 >= 0 && $0 <= 999 && $0.rounded() == $0 } ?? true }),
                  game.players.count <= 300, Set(game.players.map(\.id)).count == game.players.count else { throw NFLFeedError.response }
            let mappedIDs = game.players.compactMap(\.mflID)
            guard Set(mappedIDs).count == mappedIDs.count else { throw NFLFeedError.response }
            guard (game.defenses?.count ?? 0) <= 2,
                  Set((game.defenses ?? []).map(\.team)).count == (game.defenses?.count ?? 0),
                  (game.defenses ?? []).allSatisfy({ NFLFeedGame.isDefense($0.position ?? "") }),
                  game.defenseCheckedAt.map({ $0.isFinite && $0 > 0 && $0 <= now.timeIntervalSince1970 + 30 }) ?? true else { throw NFLFeedError.response }
            for player in game.players + (game.defenses ?? []) {
                guard (player.mflID == nil) == (player.mflName == nil),
                      player.mflID.map({ (1...12).contains($0.count) && $0.allSatisfy { "0123456789".contains($0) } }) ?? true,
                      player.mflName.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 }) ?? true else { throw NFLFeedError.response }
                guard player.providerID > 0, !player.name.isEmpty, [game.home, game.away].contains(player.team),
                      player.groups.count <= 30, Set(player.groups.map(\.name)).count == player.groups.count,
                      player.groups.allSatisfy({ $0.stats.count <= 60 && Set($0.stats.map(\.name)).count == $0.stats.count }) else { throw NFLFeedError.response }
            }
        }
        return self
    }
}
enum NFLFeedError: Error { case address, response, unavailable }
private final class NFLFeedRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
struct NFLFeedClient: Sendable {
    let baseURL: URL
    let session: URLSession
    init(address: String, session: URLSession? = nil) throws {
        guard let url = URLComponents(string: address), url.scheme == "https", let host = url.host,
              host.hasSuffix(".ts.net"), host.split(separator: ".").count >= 4,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", let baseURL = url.url else { throw NFLFeedError.address }
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 10
        self.session = session ?? URLSession(configuration: config, delegate: NFLFeedRedirectGuard(), delegateQueue: nil)
    }
    func load(season: Int, week: Int, teams: [String] = [], defenseTeams: [String] = []) async throws -> NFLWeekFeed {
        guard (2020...2100).contains(season), (1...18).contains(week) else { throw NFLFeedError.response }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/seasons/\(season)/weeks/\(week)"))
        request.setValue("1", forHTTPHeaderField: "X-Blitz-NFL")
        BetaServiceAccess.authorize(&request)
        let codes = Set(teams.map(NFLFeedGame.team)).filter { $0.count <= 3 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isLetter) }.sorted()
        if !codes.isEmpty { request.setValue(codes.prefix(32).joined(separator: ","), forHTTPHeaderField: "X-Blitz-NFL-Teams") }
        let defenseCodes = Set(defenseTeams.map(NFLFeedGame.team)).filter { $0.count <= 3 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isLetter) }.sorted()
        if !defenseCodes.isEmpty { request.setValue(defenseCodes.prefix(32).joined(separator: ","), forHTTPHeaderField: "X-Blitz-NFL-Defense") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 5_000_000 else { throw NFLFeedError.unavailable }
        return try JSONDecoder().decode(NFLWeekFeed.self, from: data).validated(season: season, week: week)
    }
}

@MainActor @Observable
final class NFLScoringStore {
    typealias Loader = @Sendable (Int, Int, [String], [String]) async throws -> NFLWeekFeed
    private var feeds: [String: NFLWeekFeed] = [:]
    private var failures: [String: Int] = [:]
    private var nextRead: [String: Date] = [:]
    private var requests: [String: Task<NFLWeekFeed, any Error>] = [:]
    private let loader: Loader?
    var isConfigured: Bool { loader != nil }
    var isPreview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--nfl-scoring-preview")
        #else
        return false
        #endif
    }
    init(loader: Loader? = nil) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--nfl-scoring-preview") {
            self.loader = { season, week, _, _ in NFLFeedPreview.make(season: season, week: week) }
            return
        }
        #endif
        if let loader { self.loader = loader }
        else if let address = Bundle.main.object(forInfoDictionaryKey: "NFLScoringURL") as? String,
                let client = try? NFLFeedClient(address: address) { self.loader = { try await client.load(season: $0, week: $1, teams: $2, defenseTeams: $3) } }
        else { self.loader = nil }
    }
    func feed(season: Int, week: Int) -> NFLWeekFeed? { feeds["\(season).\(week)"] }
    func failed(season: Int, week: Int) -> Bool { failures["\(season).\(week)", default: 0] > 0 }
    func failureCount(season: Int, week: Int) -> Int { failures["\(season).\(week)", default: 0] }
    func loading(season: Int, week: Int) -> Bool { requests["\(season).\(week)"] != nil }
    func refresh(season: Int, week: Int, force: Bool = false, teams: [String] = [], defenseTeams: [String] = []) async {
        let key = "\(season).\(week)"
        guard let loader, (1...18).contains(week) else { return }
        if let task = requests[key] { _ = try? await task.value; return }
        if let next = nextRead[key], next > Date(), !force || failures[key, default: 0] > 0 { return }
        // Pull-to-refresh bypasses only the phone's cache; the server never
        // accepts a cache-bypass flag or performs an upstream read for a caller.
        let task = Task { try await loader(season, week, teams, defenseTeams).validated(season: season, week: week) }
        requests[key] = task
        defer { requests[key] = nil }
        do {
            let value = try await task.value
            if let prior = feeds[key]?.fetchedAt, let new = value.fetchedAt, new < prior { return }
            // A cold/restarting server must not erase a usable earlier response.
            if !value.games.isEmpty || feeds[key] == nil { feeds[key] = value }
            failures[key] = nil
            nextRead[key] = Date().addingTimeInterval(value.warming ? 5 : 15)
            if feeds.count > 3, let oldest = feeds.filter({ $0.key != key }).min(by: { ($0.value.fetchedAt ?? 0) < ($1.value.fetchedAt ?? 0) })?.key {
                feeds[oldest] = nil; nextRead[oldest] = nil; failures[oldest] = nil
            }
        } catch {
            guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            failures[key, default: 0] += 1
            nextRead[key] = Date().addingTimeInterval(min(120, 15 * pow(2, Double(min(4, failures[key, default: 1] - 1)))))
            if var old = feeds[key] {
                for index in old.games.indices { old.games[index].stale = true; old.games[index].statsStale = true; old.games[index].defenseStale = true }
                feeds[key] = old
            }
        }
    }
    func poll(season: Int, week: Int, teams: [String] = [], defenseTeams: [String] = []) async {
        guard isConfigured else { return }
        while !Task.isCancelled {
            await refresh(season: season, week: week, teams: teams, defenseTeams: defenseTeams)
            let value = feed(season: season, week: week)
            let delay = value?.warming == true ? 5 : value?.games.contains(where: \.isLive) == true ? 20 : 60
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        }
    }
}

#if DEBUG
/// Synthetic UI fixture; no real IDs, provider calls, or persisted mappings.
enum NFLFeedPreview {
    static func make(season: Int = 2026, week: Int = 1) -> NFLWeekFeed {
        let now = Date().timeIntervalSince1970
        let player = NFLFeedPlayer(providerID: 999001, name: ProcessInfo.processInfo.arguments.contains("--unified-player-preview") ? "Dak Prescott" : "UB Quarterback", team: "DAL", position: "QB", groups: [
            NFLFeedGroup(name: "Passing", stats: [.init(name: "comp att", value: "24/31"), .init(name: "yards", value: "311"),
                .init(name: "passing touch downs", value: "2"), .init(name: "interceptions", value: "0")]),
            NFLFeedGroup(name: "Rushing", stats: [.init(name: "total rushes", value: "3"), .init(name: "yards", value: "18")])])
        let game = NFLFeedGame(id: 99901, season: season, week: week, kickoff: now - 7200, status: "Q3", timer: "04:32",
            home: "DAL", away: "NYG", homeScore: 20, awayScore: 14, checkedAt: now, stale: false,
            players: [player], statsCheckedAt: now - 15, statsStale: false)
        let receiver = NFLFeedPlayer(providerID: 999002, name: "UB Tight End", team: "JAC", position: "TE", groups: [
            NFLFeedGroup(name: "Receiving", stats: [.init(name: "total receptions", value: "2"), .init(name: "yards", value: "23"),
                .init(name: "receiving touch downs", value: "1")])])
        let receiverGame = NFLFeedGame(id: 99902, season: season, week: week, kickoff: now - 14400, status: "FT", timer: nil,
            home: "JAC", away: "CLE", homeScore: 21, awayScore: 14, checkedAt: now, stale: false,
            players: [receiver], statsCheckedAt: now - 30, statsStale: false)
        return NFLWeekFeed(schema: 1, provider: "API-NFL", season: season, week: week, fetchedAt: now,
            warming: false, retryAfter: 20, games: [game, receiverGame])
    }
}
#endif
