# Security policy

Please use the repository's **Security → Report a vulnerability** flow, or contact the repository owner privately, rather than opening a public issue.

Never include MyFantasyLeague usernames, passwords, `MFL_USER_ID` values, API keys, private message content, blind bids, or unredacted response fixtures in a report.

MFL Blitz is designed to:

- send credentials only to MFL over HTTPS;
- keep the password in memory only for login;
- keep the resulting MFL session in memory only and discard it on disconnect or app termination;
- reject insecure API endpoints and cross-host mutation redirects;
- perform no analytics, ad tracking, or credential proxying;
- avoid automatic retries of lineup, waiver, and message-board writes.
