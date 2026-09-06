# Privacy policy

Effective September 5, 2026

MFL Blitz is an independent, open-source iOS client for MyFantasyLeague. It has no advertising, analytics, tracking, crash-reporting, or proprietary chat service.

## Data the app handles

- Your MFL username, password, league ID, and season are sent directly from your device to MyFantasyLeague over HTTPS when you sign in.
- Your password is used only for that login request. MFL Blitz does not persist it.
- The MFL session value is stored in this device’s Keychain, accessible while unlocked and not synchronized to iCloud Keychain or migrated to another device. It is used to reconnect after app termination; your password is never saved.
- League information requested from MFL can include rosters, scores, standings, pending waiver bids, and message-board content. Version 0.1 uses only an in-memory response cache.
- Lineup drafts, queued waiver edits, board drafts, and an unconfirmed-post marker are stored in the same device-only Keychain, scoped to season, league, and franchise. The marker prevents an interrupted send from being automatically repeated after relaunch.
- Team icons and logos use the HTTPS artwork URLs supplied by your league. Images may be hosted by MFL or an external website. Artwork requests use a separate session that sends no account cookie or credentials, accepts no image-host cookies, and has no disk cache. Small, static thumbnails are cached only in memory.

No MFL account or league data is sent to the developer or to an MFL Blitz server. Apple and MyFantasyLeague may process network or platform data under their own policies. Artwork hosts also receive your IP address and the requested image URL under their own policies; they do not receive your MFL sign-in or other league API responses.

## Sharing and tracking

MFL Blitz does not sell or share personal information and does not track you across apps or websites. The app includes no third-party analytics, advertising, or social SDKs.

## Retention and deletion

Disconnecting a live team clears its saved session, local drafts, unconfirmed-post marker, and in-memory league data. Session expiry preserves drafts so you can recover them by signing in to the same franchise. Closing the app clears the response cache but retains the protected session and drafts. Data already submitted to MFL remains on MyFantasyLeague. Resolve any unconfirmed post on MFL before disconnecting, since disconnecting removes the local duplicate-prevention marker too.

## Connected-league actions

This private testing build permits live reads and user-confirmed lineup, supported conditional blind-bid, and message-board submissions. Each is sent directly to MFL and read back for confirmation. MFL does not expose saved lineup tiebreakers. A multi-round waiver save can partially succeed; the app stops and asks you to compare saved versus drafted rounds. An unconfirmed post is not automatically resent. Unsupported waiver configurations use the league website. The interactive Champion Hall preview uses local sample data and sends nothing to MFL.

## Contact

For privacy questions, contact the repository owner through the [MFL Blitz GitHub repository](https://github.com/biggsjm/mfl-blitz-ios). For security reports, use GitHub's private vulnerability-reporting flow instead of a public issue.
