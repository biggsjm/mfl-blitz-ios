# Automatic league beta access

September 16, 2026. Josh requested full enhanced NFL statistics and background notification capability for all invited owners, then explicitly asked to remove the separate code step. Owners install the new TestFlight build and sign in to their own MFL team. Co-owners use their own MFL accounts. Lineup notifications remain opt-in through the toolbar bell and the iOS prompt.

## Connection and verification

After live MFL sign-in or restored membership verification, the app connects league services in the background. Cached/offline sessions and the synthetic preview never enroll. A random 32-byte device credential is saved in device-only Keychain before enrollment so interrupted requests can retry idempotently. The enrollment POST goes only to the compiled-in HTTPS gateway origin, never a user-edited server address; redirects, ambient cookies, credentials and URL caching are disabled.

The gateway receives the MFL session transiently, sends it only to MFL's fixed HTTPS `myleagues` export, and verifies the requested season/league/franchise against the response and its private team allowlist. It does not receive a password, persist a session, log request bodies or keep MFL membership responses. Core dumps are disabled. A submitted team ID alone cannot activate access. After verification, only the random device credential's hash, team scope and expiry are stored. Later scoring requests carry that credential, not the MFL session. The sign-in screen and privacy policy explain this exchange.

Both Two Bad Neighbors owners receive independent device credentials mapped to the same franchise. There are no emailed codes or shared credentials to enter. The 13 manually generated invitations from the earlier deployment checkpoint were never sent and are retired when the automatic configuration is deployed.

## Access boundary and retention

`mfl-tester-gateway.service` runs as Linux user `josh` and binds `127.0.0.1:8794`. A separate Tailscale Funnel HTTPS port 10000 exposes this gateway; the older private Serve ports 8443–8445 remain independent. Only enrollment can run without a gateway credential; it verifies an authenticated MFL session and an allowed team. All data/status/registration endpoints require a valid scoped device credential. No browser CORS, arbitrary proxy, incoming identity forwarding, provider credential or bundled shared secret is available.

The gateway permits the invited season's shared NFL cache, the team's matchup timeline and registrations containing the team. Existing per-device subscription secrets protect updates/deletion even between co-owners. The upstream scoring service sees a distinct allowlisted identity for each team, not MFL credentials.

Team access expires February 1, 2027 UTC. Remove a team from configuration or a device grant from SQLite to stop new requests immediately. Previously accepted background leases may continue until explicitly deleted or expired; Apple may already have accepted a push. Disconnect requests subscription deletion before revoking the device grant. If offline, its random enrollment secret remains for idempotent reconnection; it contains no MFL session or password. Pending background deletions cannot be guaranteed after revocation or credential replacement and remain bounded by their original leases. Expired records are pruned on subsequent requests; a stopped service cannot prune.

## Capacity and request budget

- Six device grants per team; four Live Activity and four lineup registrations per team support co-owners while capping total registrations at 48 each.
- 60 gateway requests per minute per device, 240 per team, 600 total; persistent counters, 16 concurrent handlers, bounded messages and timeouts.
- Enrollment permits at most six attempts per minute globally and two per device, with a persisted two-second MFL spacing and five-minute cooldown after an MFL rate limit. A verified enrollment retry performs no additional MFL request. Failed app connections retry on later foreground use after five minutes, with a manual Reconnect option in League services.
- Existing scoring caches, one-minute MFL reads, persistent scoring cooldowns, sub-eight-hour activity leases and eight-day lineup leases are unchanged.
- Every phone uses one NFL cache/worker. The provider's existing 6,000-call daily application ceiling, 7,500-call plan, game-aware polling, failure backoff and correction schedule remain unchanged. Gateway reads cannot call the provider directly.

## Operations

Team configuration: `~/.config/mfl-tester-gateway/testers.json`, mode 0600; `teams` maps `season.league.franchise` to an opaque `blitz-beta-*` backend identity, season, league ID, franchise ID and Unix expiry. No owner email is needed. Device hashes, bounded registration IDs/secret hashes and rate counters live under `~/.local/share/mfl-tester-gateway/state/access.sqlite3`. Keep credentials and all real membership responses out of logs, source, screenshots and app metadata.

Deploy with `scripts/deploy_tester_gateway.sh`, after provisioning the private team allowlist and matching scoring `allowedLogins`. Publish only this loopback service on port 10000. Do not reset existing Serve configuration. Roll back with `tailscale funnel --https=10000 off`, then stop this user service. Maintain the canonical Hephaestus background-role inventory during changes.

Both native service build settings point to the gateway origin. Existing private scoring overrides migrate after successful automatic connection. TestFlight processing/review and actual phone push delivery are separate from gateway health and APNs signer readiness; record verified state in current-status.md.
