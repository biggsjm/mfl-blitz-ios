# Privacy policy

Effective September 7, 2026

Implementation reviewed against private build **0.5.3 (28)**. This build adds protected on-device league metadata and last-loaded screen caches so returning users can see content during reconnection. It adds no data source, permission, analytics or server. Other private response caches remain memory-only, as specified below.

MFL Blitz is an independent, open-source iOS client for MyFantasyLeague. It has no advertising, analytics, tracking, crash-reporting, or proprietary chat service.

## Data the app handles

- Your MFL username, password, league ID, and season are sent directly from your device to MyFantasyLeague over HTTPS when you sign in.
- Your password is used only for that login request. MFL Blitz does not persist it.
- The MFL session value is stored in this device’s Keychain, accessible while unlocked and not synchronized to iCloud Keychain or migrated to another device. It is used to reconnect after app termination; your password is never saved.
- League information requested from MFL can include rosters, player ownership/status and optional biography, fantasy season schedules, scores, standings, owner names, pending waiver bids, trade offers and comments, tradable assets, transaction history, and message-board content. Most response caches are memory-only; the private disk exceptions are described next. Owner names are displayed only as provided by MFL; the app does not look up owners elsewhere.
- Last-loaded scores/projections, lineup, standings, team identity, own-team season roster and Board list summaries may be stored in one size-bounded display file. Each section is usable for cached display only while younger than seven days; expired-file retention is explained below. It does not retain full Board posts or pending bids/trade offers. A separate daily metadata file retains MFL's league export, which may include owner names/contact fields and bid balances supplied by MFL. It is reused only after fresh membership verification; balance display and submissions require stricter freshness.
- Both private cache files use iOS complete file protection, are excluded from backup and bound to the exact saved session/season/league/franchise. Cache identifiers contain a one-way session hash, not the raw cookie. These are display/read optimizations, not permission or offline submission records. iOS may evict them. The [cache contract](docs/performance-startup.md) specifies size, expiry and account-isolation checks.
- The public NFL player directory has a separate season-specific copy in the app’s disposable Caches folder for up to 24 hours and is reused after reopening. It contains public player data, not credentials, owner details, private league data, or response headers. iOS may remove it; the next successful download replaces it.
- Targeted player biographies have a separate 24-hour memory cache; they are not added to the persisted public directory. Schedule, roster and player browsing is scoped to the current account/league, and late responses from an old session cannot populate the new account.
- Lineup drafts, queued waiver edits, board and trade drafts, and unconfirmed-action markers are stored in the same device-only Keychain, scoped to season, league, and franchise. Trade drafts and markers include offer terms, optional comments, expiration, and identifying information needed to verify the action. Markers prevent an interrupted send from being automatically repeated after relaunch.
- Team icons and logos use the HTTPS artwork URLs supplied by your league. Images may be hosted by MFL or an external website. Artwork requests use a separate session that sends no account cookie or credentials, accepts no image-host cookies, and has no disk cache. Small, static thumbnails are cached only in memory, including the signed-in team logo displayed in the My Team tab.

No MFL account or league data is sent to the developer or to an MFL Blitz server. Apple and MyFantasyLeague may process network or platform data under their own policies. Artwork hosts also receive your IP address and the requested image URL under their own policies; they do not receive your MFL sign-in or other league API responses.

The player-tools increment also reads public injury/schedule/bye feeds, league-scored player history and points allowed, the owner's watchlist and action permissions. These responses are memory-only. Watchlist stars send incremental add/remove requests directly to MFL; roster moves send only the reviewed player IDs. Watchlist markers retain player ID, desired state and time; roster markers retain scope, requested move, expected membership and time. Both are device-only Keychain data used for readback/duplicate prevention, not analytics.

## Sharing and tracking

MFL Blitz does not sell or share personal information and does not track you across apps or websites. The app includes no third-party analytics, advertising, or social SDKs.

## Retention and deletion

Disconnecting a live team clears its saved session, local drafts, unconfirmed-action markers, in-memory league data and private cache files. Session expiry preserves drafts so you can recover them by signing in to the same franchise; cached startup display is rejected without its matching saved session. Closing the app retains the protected session/drafts and the cache files described above, while other private response caches disappear from memory. Expired cache entries are not used and are replaced on a successful download; unused expired files may remain until replacement, disconnect, iOS eviction or uninstall. Uninstalling removes app cache files. Data already submitted to MFL remains on MyFantasyLeague. Resolve any unconfirmed post, trade, watchlist or roster action on MFL before disconnecting, since disconnecting removes the local duplicate-prevention markers too.

Meaningful trade edits are autosaved privately for interruption recovery. Cancel restores the draft that existed before the editor opened, with a discard confirmation for changes; opening an empty composer alone does not retain a draft. Discard draft deletes that local draft, not offers already sent to MFL. Uninstalling may not remove Keychain items; use Disconnect first to remove the team's protected data.

Meaningful Board edits are autosaved for interruption recovery. Close asks whether to retain the draft, discard it, or keep editing. Saved new threads and replies are accessible from Board → Drafts; a thread can also Resume reply. Discard deletes only that draft, not any MFL post or unresolved-send marker. Empty composers do not retain a draft. Save/discard failures keep the composer open for retry.

## Connected-league actions

This private testing build permits live reads, explicit watchlist star toggles, and user-reviewed lineup, supported conditional blind-bid, trade, board, supported FCFS add/drop and IR submissions. Each is sent directly to MFL and read back for confirmation. Offers and responses may notify other owners through MFL. A counteroffer is a new offer and leaves the original open; acceptance may require league approval or processing. MFL does not expose saved lineup tiebreakers. A multi-round waiver save can partially succeed; the app stops and asks you to compare saved versus drafted rounds. Unconfirmed posts, trades, watchlist changes and roster moves are not automatically resent. Unsupported waiver configurations and unverified trade details use the league website. The interactive Champion Hall preview uses local sample data and sends nothing to MFL.

## Contact

For general privacy questions, contact the owner through the [MFL Blitz GitHub repository](https://github.com/biggsjm/mfl-blitz-ios), without including account or private league content. For sensitive matters, use an established private contact or request a private reporting route without disclosing details. GitHub private vulnerability reporting was disabled at this review; see [Security](SECURITY.md) rather than assuming that feature is available.
