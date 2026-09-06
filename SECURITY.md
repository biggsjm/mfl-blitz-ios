# Security policy

Reviewed September 6, 2026 against **0.5.1 (20) candidate**. Contact the repository owner through an established private channel rather than posting a vulnerability publicly. GitHub private vulnerability reporting is currently disabled; establishing an available reporting route is a [distribution gate](docs/roadmap.md). Do not assume a **Report a vulnerability** button is available. If no private contact is available, request a private reporting route without disclosing exploit details or sensitive data.

Never include MyFantasyLeague usernames, passwords, `MFL_USER_ID` values, API keys, private message content, trade terms, blind bids or unredacted authenticated payloads in an issue or routine diagnostic report. Use synthetic reproduction data; report build, affected workflow and expected/observed behavior.

MFL Blitz is designed to:

- send credentials only to MFL over HTTPS;
- keep the password in memory only for login;
- retain sessions, scoped drafts and unconfirmed-action markers in device-only Keychain items available while unlocked, without iCloud synchronization; freshly verify membership/franchise on restore;
- clear the team's protected session/drafts/markers on explicit disconnect; preserve drafts after session expiry so the same franchise can recover them;
- reject insecure API endpoints and cross-host mutation redirects;
- perform no analytics, ad tracking, or credential proxying;
- isolate franchise images in an ephemeral cookieless session with HTTPS validation, no redirects and bounded static thumbnails;
- persist only the public player directory as a response cache; keep private API response caches in memory;
- review intended lineup, waiver, trade, board and roster actions, use fresh preflight/readback, and never blindly retry imports;
- retain durable markers for ambiguous board/trade/watchlist/roster writes across relaunch, without assuming disappearance alone proves a timed-out trade acceptance.

Roster actions require exact owner-scoped ability IDs, a supported league format, fresh reviewed membership/limits and explicit acquisition-unlocked state for additions. IR uses current roster membership, never a guessed lineup slot. Full membership/status readback confirms moves. Unknown/duplicate permissions or roster states fail closed; a shared roster-write gate prevents overlapping local mutations. Watchlist updates are incremental, not full-list replacements.

Resolve any unconfirmed action against MFL before disconnecting, since disconnect removes its local duplicate-prevention marker. Data already submitted to MFL is not deleted by Cancel, disconnect or app removal. See [privacy](PRIVACY.md) for data flow and retention.

Build 16 fixes a response-review presentation bug in earlier trade builds: first-tap Decline/Withdraw could display a default Accept review. Use build 16 or a later validated build for trade testing. Fresh identifiable sheet payloads and explicit editor identities are regression requirements, in addition to API participant checks.

These controls and tests are not a completed independent security audit or proof of support for every league configuration. See [release status](docs/current-status.md) and the remaining validation gates before broader distribution.
