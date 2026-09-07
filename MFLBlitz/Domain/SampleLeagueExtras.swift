import Foundation
import MFLCore

extension DemoLeagueRepository {
    func loadTradingBlock(refresh: Bool) async throws -> TradingBlockSnapshot {
        TradingBlockSnapshot(scope: SampleData.workspace.storageScope, listings: demoBlockListings,
            teams: SampleData.trades.teams, fetchedAt: Date())
    }
    func publishTradingBlock(_ draft: TradingBlockDraft) async throws -> TradingBlockReceipt {
        let fresh = try await loadTradingBlock(refresh: true)
        try TradingBlockPolicy.validate(draft, fresh: fresh, ownerID: SampleData.workspace.franchiseID)
        demoBlockListings.removeAll { $0.id == SampleData.workspace.franchiseID }
        if !draft.isRemoval {
            demoBlockListings.append(MFLTradingBlockListing(id: SampleData.workspace.franchiseID, codes: draft.codes, lookingFor: draft.lookingFor))
        }
        return TradingBlockReceipt(confirmed: true, snapshot: try await loadTradingBlock(refresh: true), removed: draft.isRemoval)
    }
    func loadLeagueCalendar(refresh: Bool) async throws -> LeagueCalendarSnapshot {
        let now = Date()
        let source = MFLLeagueCalendar(events: [
            MFLCalendarEvent(id: "demo-bids", type: "WAIVER_BBID", start: now.addingTimeInterval(2 * 86_400)),
            MFLCalendarEvent(id: "demo-adds", type: "WAIVER_UNLOCK", start: now.addingTimeInterval(2 * 86_400)),
            MFLCalendarEvent(id: "demo-closes", type: "WAIVER_LOCK", start: now.addingTimeInterval(5 * 86_400)),
            MFLCalendarEvent(id: "demo-trade-deadline", type: "TRADE", start: now.addingTimeInterval(10 * 86_400)),
            MFLCalendarEvent(id: "demo-draft", type: "DRAFT_START", start: now.addingTimeInterval(-7 * 86_400))
        ])
        return LeagueCalendarSnapshot(scope: SampleData.workspace.storageScope, source: MFLCalendarOccurrences(calendar: source, ics: nil), fetchedAt: now)
    }
}
