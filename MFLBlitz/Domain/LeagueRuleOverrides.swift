import Foundation
import MFLCore

enum LeagueRuleOverrides {
    nonisolated static func minimumBlindBid(for league: MFLLeague, season: Int) -> Decimal? {
        // Prefer MFL whenever it supplies the rule. Josh confirmed the $0
        // minimum for Champion Hall's 2026 season on September 6, 2026; its
        // league export omits bbidMinimum. Do not infer this for other leagues
        // or carry it into another season.
        if let minimum = league.blindBidMinimum { return minimum }
        if league.id == "41333", season == 2026 { return 0 }
        return nil
    }
}
