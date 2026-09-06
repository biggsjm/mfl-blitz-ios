# Privacy policy

Effective September 5, 2026

MFL Blitz is an independent, open-source iOS client for MyFantasyLeague. It has no advertising, analytics, tracking, crash-reporting, or proprietary chat service.

## Data the app handles

- Your MFL username, password, league ID, and season are sent directly from your device to MyFantasyLeague over HTTPS when you sign in.
- Your password is used only for that login request. MFL Blitz does not persist it.
- The MFL session value is held in app memory only for the current run. It is discarded when you disconnect or the app terminates.
- League information requested from MFL can include rosters, scores, standings, pending waiver bids, and message-board content. Version 0.1 uses only an in-memory response cache.

No MFL account or league data is sent to the developer or to an MFL Blitz server. Apple and MyFantasyLeague may process network or platform data under their own policies.

## Sharing and tracking

MFL Blitz does not sell or share personal information and does not track you across apps or websites. The app includes no third-party analytics, advertising, or social SDKs.

## Retention and deletion

Disconnecting clears the active session and in-memory league data. Closing the app also removes the active session and cache. MFL data remains on MyFantasyLeague and must be managed according to MyFantasyLeague's controls and policies.

## Connected-league safety preview

Version 0.1 permits live reads but disables lineup, waiver, and message-board writes by default until the production API client and mutation flows have been validated in disposable leagues. The interactive Champion Hall preview uses local sample data and sends nothing to MFL.

## Contact

For privacy questions, contact the repository owner through the [MFL Blitz GitHub repository](https://github.com/biggsjm/mfl-blitz-ios). For security reports, use GitHub's private vulnerability-reporting flow instead of a public issue.
