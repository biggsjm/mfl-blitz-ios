# Privacy policy

Effective September 6, 2026

MFL Blitz is an independent, open-source iOS client for MyFantasyLeague. It has no advertising, analytics, tracking, crash-reporting, or proprietary chat service.

## Data the app handles

- Your MFL username, password, league ID, and season are sent directly from your device to MyFantasyLeague over HTTPS when you sign in.
- Your password is used only for that login request. MFL Blitz does not persist it.
- The MFL session value is stored in this device’s Keychain, accessible while unlocked and not synchronized to iCloud Keychain or migrated to another device. It is used to reconnect after app termination; your password is never saved.
- League information requested from MFL can include rosters, scores, standings, owner names, pending waiver bids, trade offers and comments, tradable assets, transaction history, and message-board content. API responses are cached only in memory. Owner names are displayed only as provided by MFL for your authenticated session; the app does not look up owners elsewhere.
- The public NFL player directory is the exception: a season-specific copy is kept in the app’s disposable Caches folder for up to 24 hours and reused after reopening. It contains public player data, not credentials, owner details, private league data, or response headers. iOS may remove it; the next successful download replaces it.
- Lineup drafts, queued waiver edits, board and trade drafts, and unconfirmed-action markers are stored in the same device-only Keychain, scoped to season, league, and franchise. Trade drafts and markers include offer terms, optional comments, expiration, and identifying information needed to verify the action. Markers prevent an interrupted send from being automatically repeated after relaunch.
- Team icons and logos use the HTTPS artwork URLs supplied by your league. Images may be hosted by MFL or an external website. Artwork requests use a separate session that sends no account cookie or credentials, accepts no image-host cookies, and has no disk cache. Small, static thumbnails are cached only in memory.

No MFL account or league data is sent to the developer or to an MFL Blitz server. Apple and MyFantasyLeague may process network or platform data under their own policies. Artwork hosts also receive your IP address and the requested image URL under their own policies; they do not receive your MFL sign-in or other league API responses.

## Sharing and tracking

MFL Blitz does not sell or share personal information and does not track you across apps or websites. The app includes no third-party analytics, advertising, or social SDKs.

## Retention and deletion

Disconnecting a live team clears its saved session, local drafts, unconfirmed-action markers, and in-memory league data. Session expiry preserves drafts so you can recover them by signing in to the same franchise. Closing the app clears private response caches but retains the protected session and drafts, plus the public player cache described above. Expired player data is not used and is replaced on the next successful download; uninstalling the app removes its cache files. Data already submitted to MFL remains on MyFantasyLeague. Resolve any unconfirmed post or trade action on MFL before disconnecting, since disconnecting removes the local duplicate-prevention markers too.

## Connected-league actions

This private testing build permits live reads and user-confirmed lineup, supported conditional blind-bid, trade, and message-board submissions. Each is sent directly to MFL and read back for confirmation. Offers and responses may notify other owners through MFL. A counteroffer is a new offer and leaves the original open; acceptance may require league approval or processing. MFL does not expose saved lineup tiebreakers. A multi-round waiver save can partially succeed; the app stops and asks you to compare saved versus drafted rounds. Unconfirmed posts and trade actions are not automatically resent. Unsupported waiver configurations and unverified trade details use the league website. The interactive Champion Hall preview uses local sample data and sends nothing to MFL.

## Contact

For privacy questions, contact the repository owner through the [MFL Blitz GitHub repository](https://github.com/biggsjm/mfl-blitz-ios). For security reports, use GitHub's private vulnerability-reporting flow instead of a public issue.
