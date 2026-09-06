import Foundation

extension SampleData {
    static let trades: TradeSnapshot = {
        let ownerAssets = lineupPlayers.map { TradeAsset(id: $0.id, name: $0.name, detail: "\($0.position) · \($0.nflTeam)", kind: .player) }
        let otherAssets = [
            TradeAsset(id: "demo-wr", name: "CeeDee Lamb", detail: "WR · DAL", kind: .player),
            TradeAsset(id: "demo-rb", name: "Bijan Robinson", detail: "RB · ATL", kind: .player),
            TradeAsset(id: "demo-qb", name: "Josh Allen", detail: "QB · BUF", kind: .player),
            TradeAsset(id: "FP_0008_2027_1", name: "2027 · Round 1", detail: "Originally Route Runners", kind: .pick)
        ]
        let teams = [
            TradeTeam(id: "0001", name: workspace.franchiseName, abbreviation: "UB", assets: ownerAssets, blindBidBalance: 100),
            TradeTeam(id: "0008", name: "Route Runners", abbreviation: "RR", assets: otherAssets, blindBidBalance: 75),
            TradeTeam(id: "0002", name: "Croton Bug Eaters", abbreviation: "CBE", assets: [TradeAsset(id: "demo-te", name: "Brock Bowers", detail: "TE · LV", kind: .player)], blindBidBalance: nil)
        ]
        return TradeSnapshot(teams: teams, offers: [
            TradeOffer(id: "demo-incoming", offeredBy: "0008", offeredTo: "0001", giving: [otherAssets[0]],
                receiving: [ownerAssets[1], ownerAssets[3]], comments: "Interested in a two-for-one? Happy to talk.",
                expires: now.addingTimeInterval(2 * 86_400), timestamp: now.addingTimeInterval(-3_600), status: "pending"),
            TradeOffer(id: "demo-sent", offeredBy: "0001", offeredTo: "0002", giving: [ownerAssets[6]],
                receiving: teams[2].assets, comments: "Looking for a tight end upgrade.",
                expires: now.addingTimeInterval(86_400), timestamp: now.addingTimeInterval(-7_200), status: "pending")
        ], updatedAt: now)
    }()
}

extension DemoLeagueRepository {
    func loadTrades() async throws -> TradeSnapshot { demoTrades }
    func performTrade(_ command: TradeCommand) async throws -> TradeReceipt {
        switch command {
        case .propose(let draft):
            func asset(_ code: String, team: String) -> TradeAsset {
                demoTrades.teams.first { $0.id == team }?.assets.first { $0.id == code }
                    ?? TradeAsset(id: code, name: code.replacingOccurrences(of: "BB_", with: "$"), detail: "FAAB dollars", kind: .budget)
            }
            demoTrades.offers.append(TradeOffer(id: UUID().uuidString, offeredBy: "0001", offeredTo: draft.partnerID,
                giving: draft.giving.sorted().map { asset($0, team: "0001") }, receiving: draft.receiving.sorted().map { asset($0, team: draft.partnerID) },
                comments: draft.comments, expires: draft.expires, timestamp: Date(), status: "pending"))
        case .respond(let offer, let response, _):
            guard demoTrades.offers.contains(where: { $0.id == offer.id && $0.matchesTerms(of: offer) }),
                  response == .revoke ? offer.offeredBy == "0001" : offer.offeredTo == "0001" else {
                throw RepositoryError.server("That preview offer is no longer available.")
            }
            demoTrades.offers.removeAll { $0.id == offer.id }
        }
        demoTrades.updatedAt = Date()
        return TradeReceipt(confirmed: true, message: "Preview updated. No offer or response was sent to MFL.")
    }
    func loadTransactionActivity() async throws -> [TransactionActivity] {
        [TransactionActivity(id: "demo-waiver", title: "Blind-bid waiver", detail: "", date: Date().addingTimeInterval(-3_600), isTrade: false,
            teamName: "Route Runners", bid: 3, moves: [.init(label: "Added", names: "Braelon Allen"), .init(label: "Dropped", names: "Jaylin Noel")]),
         TransactionActivity(id: "demo-activity", title: "Trade", detail: "", date: Date().addingTimeInterval(-86_400), isTrade: true,
            teamName: "Route Runners", partnerName: "Croton Bug Eaters", moves: [.init(label: "Sent", names: "CeeDee Lamb"), .init(label: "Received", names: "Brock Bowers")])]
    }
}
