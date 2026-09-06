# Competitive research snapshot — September 5, 2026

Historical discovery research, not a continuously verified storefront report or a new September 6 market survey. Ratings, prices, features and availability can change; recheck original listings before using this for public comparisons. Observations below are the original research inputs, not acceptance evidence for MFL Blitz. Current implementation and remaining work are in [status](current-status.md) and [roadmap](roadmap.md).

## MFL iOS clients reviewed

| Product | Strongest evidence | Opportunity for MFL Blitz |
|---|---|---|
| [MFL Mobile](https://apps.apple.com/us/app/mfl-mobile-myfantasyleague/id639397317) | 4.7 stars / about 2.4K ratings; broad lineup, score, waiver, draft, trade, board, chat, and commissioner coverage | Make information hierarchy calmer; provide projection/YTD/trend waiver sorting; show exact sync and submission receipts; avoid ads/tracking |
| [MFL Platinum](https://apps.apple.com/us/app/mfl-platinum/id452910130) | Long-lived and broad; iPhone/iPad; often praised for unusual leagues and last-minute actions | Reduce navigation and draft friction; show division standings clearly; make accessibility systematic |
| [MFL Modern](https://apps.apple.com/us/app/mfl-modern/id6751516222) | Modern styling, trade calculator, separate chat, one free league | Prove configuration correctness; keep MFL activity canonical; support iPad; avoid subscription confusion and stale-state ambiguity |
| [MFL Live](https://apps.apple.com/us/app/mfl-live/id6670762804) | Focused scores, lineup, standings, transactions; declares no data collection | Add full FAAB and board workflows while preserving focus |
| MFL Pro | 2026 entrant with projections, Live Activities, FAAB, conversations, draft, and commissioner tools | Keep critical writes free, offer iPad/accessibility, minimize linked data, build a transparent verification record |

All visible general-purpose clients appear independent rather than first-party MFL products.

## What reviews consistently reward

- Complete support for the core MFL season loop.
- The ability to make a last-minute lineup change from a phone.
- Live scoring that avoids the desktop site.
- Compatibility with dynasty, IDP, salary, large, and commissioner-heavy leagues.
- Multiple leagues and useful customization.

## What reviews and community reports consistently expose

- Features technically exist but are buried or hard to scan.
- Free-agent sorting does not surface projected, season, or recent scoring well.
- Data can look stale without an obvious refresh timestamp.
- Complex league formats produce wrong starter counts, standings, labels, or draft state.
- Adds/drops and conditional waivers are easy to misunderstand.
- Separate proprietary chat splits activity and only helps when an entire league adopts it.
- Current broad clients advertise no accessibility support in App Store metadata.
- Several competitors use ad/tracking SDKs or subscription-gate routine writes.

## Product conclusion

“Modern MFL” is no longer sufficient positioning. The sharper promise is:

> **Every critical league action is obvious, legal, fresh, and confirmed.**

The original recommendation was a narrower release validated across a deliberately difficult league matrix before broad draft/trade/commissioner/contract/research expansion. Subsequent user priorities brought native trading into private build 0.3.0, with safety and presentation refinements through 0.3.7. Broad configuration certification, draft/commissioner tooling and richer research are still unfinished; this research conclusion does not supersede the current execution plan.

For broader platform context, current commissioner discussions still contrast MFL's configurability with its dated presentation while praising newer platforms' mobile communication and criticizing their increasing bloat: [2026 platform discussion](https://www.reddit.com/r/FFCommish/comments/1vfnynp/best_fantasy_football_platform_in_2026/).
