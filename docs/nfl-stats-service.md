# NFL statistics: private free-plan test

Updated September 14, 2026. The original service still implements the approved **historical evaluation**. API-NFL Pro is now active; build 55 connects a separate [current-season shared feed](live-nfl-scoring.md) to normal scoring. See the paid-plan evidence below.

## What is wired

- **Hephaestus:** user-owned Python 3 service, private Tailscale HTTPS on port 8443, loopback backend on 8791. No public Funnel, Docker daemon, firewall change or subscription. Existing user lingering was already enabled; the service is enabled for restart.
- **Development app:** My Team → Settings → NFL stats test → Load games → choose a game → Load player stats → choose a player. DEBUG only; normal player cards, MFL scores/writes and Live Activity are unchanged.
- **Free seasons:** 2022–2024 only. Server and app reject 2026 stats before calling the provider. No polling, automatic paid upgrade or fantasy-point calculation. Build 43 adds isolated, human-reviewed player-ID pairs; no automatic name-only matching or production enrichment.
- **Credential:** owner approved server-side key storage. A private FIFO/SSH stdin transferred the key without a local regular-file copy, shell argument or displayed value. Remote key is mode 600, directory 700; it is not in the app, GitHub or docs.
- **HTTPS:** owner approved Tailscale Serve and completed sign-in/enablement. Certificate issuance publishes the machine's Tailscale hostname in the public certificate registry; traffic remains tailnet-only under existing access rules. Other testers need Tailscale access. No ACL was broadened.

## Account evidence

| Request | Observed result |
| --- | --- |
| `leagues?id=1&season=2026` | Free-plan error: permits 2022–2024, not 2026. |
| `leagues?id=1&season=2024` | Player-game stats advertised; injuries false. Coverage wire key: `games.statisitcs.players`. |
| `games?league=1&season=2024&date=2024-09-08&timezone=UTC` | Separate date restriction. The initial date-filtered diagnostic is not viable on this account. |
| `games?league=1&season=2024` | Documented season-list query succeeds: 335 games. No access restriction was bypassed. |
| `games/statistics/players?id=13186` | Completed 2024 Baltimore/Kansas City game: two team records with grouped player stats. |
| Private service box-score route | HTTP 200, 61 normalized players, real string-valued stats and preserved nulls. A cached reread left the service request counter at 4. |

The first service validation rejected null short-status codes; some overtime games supply an explicit `Final/OT` long status instead. That case is now recognized; genuinely unknown states cannot request stats. The unsuccessful validation counted toward the four service requests, as intended.

Automated checks prove historical connectivity and response shape. Josh subsequently confirmed his sample accuracy check; the specific players, fields and comparison source were not recorded. This is owner-reported spot-check acceptance, **not comprehensive accuracy, correction, live-freshness or cross-provider identity validation**. No authenticated raw payload is committed as a fixture; tests use synthetic records. Actual account restrictions take precedence over broad product descriptions. The [provider guide](https://www.api-football.com/news/post/how-to-get-started-with-api-nfl-the-complete-beginners-guide) documents season lists/game stats. [Terms](https://api-sports.io/terms) still require review before wider distribution; private testing is not blanket publication authorization. No subscription was purchased.

## Contract and safeguards

Implementation: `services/nfl_test/server.py`, Python standard library only.

| Route | Cold-cache upstream work |
| --- | --- |
| `/v1/status` | Zero provider calls; configuration/budget status, no key or account identity. |
| `/v1/seasons/{year}/games` | One whole-season NFL game list; no date-filter query. |
| `/v1/seasons/{year}/games/{id}/players` | Validate game membership/completed status, confirm season coverage, fetch one game-level player-stat response. Reuse existing games/coverage. |
| `/v1/seasons/{year}/games/{id}/players/{playerID}/profile` | Require exactly one matching player in that historical box score, then fetch `/players?id=...`. Profiles share the existing quota, spacing and cache; no per-row fan-out. |

- Fixed official HTTPS provider host, strict routes/seasons/IDs, no arbitrary proxy parameters; redirects never forward credentials.
- Persistent SQLite cache and **20-attempt UTC-day service budget**, below the advertised 100/day free allowance. Other dashboard/account requests still share the provider quota. Reserve every attempt before I/O, including failures; restart cannot reset usage.
- Coalesce concurrent misses; space calls at least 6.5 seconds apart. Honor provider zero-remaining headers and HTTP 429 cooldowns across routes/restarts. Known plan errors cache for a day; transient failures briefly back off. No automatic retries/polling.
- Cache historical data for 24 hours. Refresh failures may use data under seven days old with the original fetched time and a stale label. Inactive records remain until replaced or deliberately cleaned up; permitted seasons/game IDs bound the cache's scope.
- Preserve nulls as `—`, zeroes as zeroes, composite strings and stat-group context. Never merge passing/rushing yards or calculate fantasy points. Validate response/collection size, finite numbers, unique IDs, expected league/season and game-team membership.
- Loopback backend, app-specific request header, browser-origin rejection, no CORS/public endpoint, access logs, MFL data or mutation routes. User service has owner-only state, `NoNewPrivileges`, private temp storage and read-only system paths.

## App behavior

`NFLStatsTestClient` has an independent ephemeral, cookieless, credentialless session. It accepts only HTTPS Tailscale service-root addresses, with no username/password/query/fragment. Redirects are refused; cancellation stays silent and failures show locally authored messages. Returned season/game/team identity is checked before display.

The address is a private device preference, **not an API key**. Forget server clears it and displayed results. Developer builds may seed it through a local `NFLStatsTestURL` Info.plist value; no private hostname is committed. The initial list shows completed regular-season games. Stats load once per game; selecting players then uses that response with no extra network calls. The UI labels the historical season, source, original retrieval time and missing values. Retrieval time is not the provider's last correction time.

Champion Hall Preview uses synthetic records without contacting Hephaestus. This feature is compiled out of release builds and is not part of startup, search or actual roster actions.

### Reviewed player-ID mapping (build 43)

From a historical player’s stats, choose **Review MFL player match**. This explicitly loads one provider profile and reuses the app’s daily MFL search catalog. The profile’s position/college/height/weight assist review. The MFL catalog’s year is displayed separately; its team is not treated as the player’s historical game team. League-unsupported positions, absent/retired catalog entries or position conflicts may leave a player unresolved.

The provider documents stable provider IDs but no MFL ID or birth date in these profiles. Names rank suggestions only: no preselection, suffix stripping, nickname expansion, or silent match. The user must select a position-compatible MFL player, independently check identity, enter a 10–500-character verification note and confirm. This is a **human-reviewed assertion**, not an authoritative crosswalk. A note itself cannot prove identity; broader identity validation remains required before production use.

Saved records preserve both IDs/names, position, provider profile, historical season/game/team, MFL catalog season, source retrieval date, review date, note and private service origin. Each provider/MFL ID may occur only once per service; conflicting pairs cannot overwrite a saved match. Different origins and Preview are isolated. The review is invalidated by missing/changed identity or season/position conflicts, but a team change alone does not change a player’s identity. Fresh profile evidence is required to confirm. Unknown versions/corrupt archives fail closed. The DEBUG-only local preferences archive is not consumed by real player cards, scores or Live Activity.

**Reviewed player matches** on the NFL test root lists saved pairs and allows removal; a player’s review also has Remove match. Removal deletes only that local assertion, not a player, stats, roster or provider data. Preview uses memory-only synthetic IDs and cannot persist real matches. No MFL IDs, catalog, searches or review notes are sent to Hephaestus/API-Sports.

Live contract check: the documented ID-only profile request succeeded for a known player in game 13186. The initial combined ID/season query returned the service’s sanitized provider error; its exact cause was not retained. ID-only profile data is explicitly not represented as a historical biography or roster snapshot. Service usage was **8 of 20** requests for September 10 UTC after this work; subsequent cached reads add none. Actual reviewed MFL pairs still require owner review—no real match was created automatically.

## Operations and verification

- User service: `mfl-nfl-test.service`.
- Code: `~/.local/share/mfl-nfl-test/`; key: `~/.config/mfl-nfl-test/api-key` (600).
- Database: `~/.local/share/mfl-nfl-test/state/cache.sqlite3` (600).
- Unit: `~/.config/systemd/user/mfl-nfl-test.service`.
- Stop/restart: `systemctl --user stop mfl-nfl-test.service` / `systemctl --user restart mfl-nfl-test.service`.
- Remove this HTTPS route only: `tailscale serve --https=8443 off`. Do not reset unrelated Serve configuration.

`install_key.py` refuses existing-key overwrites. Rotation is a separate deliberate operation. Never paste a key into command arguments, URLs, screenshots, GitHub or app settings. The one-time `scripts/provision_nfl_test_key.sh` uses a private FIFO and strict-host-key SSH for the approved host.

The earlier hidden-prompt `scripts/api_nfl_probe.py` remains a standalone three-request diagnostic with 27 synthetic tests. Its date query can hit the free account's date restriction; use the new season-based test UI for this evaluation.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s services/nfl_test -p 'test_*.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_api_nfl_probe.py' -v
```

Native tests: `NFLStatsTestClientTests`, `NFLTestPlayerMappingTests` and `NFLStatsTestUITests`. The mapping increment has 20 server tests, 9 client tests, 7 mapping tests and a synthetic Settings → game → player → review → confirm → remove → Back journey. [Current status](current-status.md) records actual build/test/phone evidence separately from implementation.

Phone connection follow-up: the original catch-all error now distinguishes sanitized HTTP status, JSON-decoding failure and numeric transport error, retaining silent cancellation. Eight client tests pass. The explicit DEBUG `--nfl-test-connection-check` launch mode runs only the historical NFL read (no MFL restoration) and emits only record counts or locally authored messages. The owner's phone successfully loaded 335 games in this mode after unlocking. After normal launch, Josh confirmed that both the Settings game list and the game → player-stat breakdown load. The earlier failure's root cause remains unconfirmed; successful owner acceptance does not establish stat accuracy or live-feed qualification.

## Remaining plan

- [x] Verify restrictions, historical game list and one box-score response.
- [x] Deploy private cache/quota service with approved credential and HTTPS setup.
- [x] Add isolated manual historical test screen with synthetic Preview.
- [x] Owner dev-phone/Tailscale acceptance: game list and game → player-stat breakdown both load in the normal app.
- [x] Owner sample accuracy check: Josh reported it checked after confirming the player-stat breakdown loads. Comparison details were not supplied.
- [ ] Broader accuracy checks with recorded game/player/field references, including missing values and corrections.
- [ ] Qualify overtime/postseason completeness, corrections and missing fields; initial UI lists regular-season finals only.
- [x] Owner authorized API-NFL Pro at $15/month for seasonal use; the first prepaid month is active. Direct-dashboard billing terms were reviewed. Current-season access succeeds; wider distribution remains outside this private evaluation.
- [x] Implement historical-only reviewed ID pairs, provenance, collision protection, removal, cached profiles and synthetic regression coverage; no name-only auto-matching.
- [ ] Owner reviews real player pairs; qualify identity coverage/aliases/position changes before attaching stats to real MFL cards. A saved human assertion is not authoritative identity proof.
- [x] Implement current-week enrichment in build 55 with a shared request budget, identity checks, outage handling and synthetic regression checks.
- [ ] Observe actual in-game latency/corrections; game-log and postseason expansion remain separate.
- [ ] Only then consider more testers or active-game polling. No background APNs service is included.

[nflverse](https://nflreadr.nflverse.com/articles/nflverse_data_schedule.html) remains a possible free post-game source, not a guaranteed live feed. Self-hosting cannot make restricted upstream current-season data free.

## Current live-stat options: September 14, 2026

The initial options discussion did not authorize a subscription. The owner subsequently selected the $15/month API-NFL plan, conditional on seasonal use; the completed purchase and validation are recorded below.

| Source | Published plan | Fit and limits |
| --- | --- | --- |
| [API-NFL](https://www.api-football.com/news/post/how-to-get-started-with-api-nfl-the-complete-beginners-guide) | Pro $15/month, 7,500 requests/day | Documents live game/player stats with 30-second typical refresh. Reuses the existing historical adapter. The owner's free account previously rejected 2026; current-season access and actual game-day latency still need validation on an eligible plan. |
| [BALLDONTLIE NFL](https://nfl.balldontlie.io/) | ALL-STAR $9.99/month, 60 requests/min | Documents live player/team game stats. GOAT $39.99/month adds play-by-play. No account or real data tested here. Its card-required trial converts to paid unless canceled; do not start without authorization. |
| [SportsDataIO](https://sportsdata.io/developers) | Commercial live feed: custom quote | Full live coverage is a commercial agreement. Discovery Lab data is delayed one day; the free trial scrambles data. Those are not substitutes for live validation. |
| [nflverse](https://nflreadr.nflverse.com/articles/nflverse_data_schedule.html) | Public data | Player/team stats generally arrive on the nightly post-game schedule, with additional game-day runs. Useful for completed games, not a dependable in-game source. |

Recommendation: evaluate one current-season live game using API-NFL Pro because we already tested its historical response format and have the private service foundation. This is a recommendation, not a purchase or a claim that live accuracy has been verified. BALLDONTLIE is a credible cheaper alternative requiring a separate adapter/evaluation.

Hephaestus can own one polling/cache layer shared by phones, retain completed box scores and corrections, keep provider credentials server-side, and supply the app promptly on entry. MFL remains authoritative for league fantasy points; the other feed enriches player box stats and game context. Provider-to-MFL identity matching, live latency, missing values and correction handling need validation before enriching normal scoring. Hosting on Hephaestus does not supply the missing data rights or current-season plan. The existing 2022–2024 test stays unchanged until a live integration is separately requested.

## API-NFL Pro activated: September 14, 2026

Josh authorized the $15/month plan if it could be used only during August–December. The [direct dashboard](https://dashboard.api-football.com/subscription/nfl) and [billing terms](https://api-sports.io/terms) confirm prepaid access without automatic renewal: expiration returns the account to Free. One-month periods start at purchase, rather than calendar-month boundaries. Purchased periods are nonrefundable. Five one-month purchases at the current price total $75; no future renewal or additional purchase was submitted.

Checkout selected **NFL / Pro / 1 Month / 7,500 requests per day / 1 seat**, with **$15 total including $2.50 VAT**. Checkout completed during the browser session. The account page and a sanitized provider `/status` read from Hephaestus both confirmed **Pro, active, 7,500/day, expiring October 14, 2026 at 15:21:14 UTC (10:21 AM Central)**. The existing server-side key works; it was neither rotated nor copied into the app.

Current-season validation from Hephaestus:

- `leagues?id=1&season=2026` advertises player/game stats, team stats, events and injuries.
- `games?league=1&season=2026` returns 328 rows. Seven future postseason placeholders have team ID `0` and null names; the strict historical normalizer rejects the whole list when it encounters them. A diagnostic classified those rows separately and normalized 321 resolved games. A production adapter must handle unresolved future fixtures explicitly without inventing teams or dropping valid games.
- Completed 2026 Week 1 game **21527**, Dallas at New York Giants, reports **DAL 20–NYG 28, FT**. Its player-stat endpoint normalizes **67 players**, including provider player **2076, Dak Prescott**: passing 22/34, 175 yards, 2 touchdowns, 1 interception; rushing 2 attempts, 14 yards. These are provider observations, not an independent accuracy comparison or a saved MFL identity mapping.
- This was a bounded manual read: one zero-quota `/status` call and five data requests, including repeated game-list reads while diagnosing the placeholder shape. No polling or deployed service configuration changed. The historical service's own request counter does not include this separate diagnostic.

No game was live during the sample. Current-season eligibility and a completed box score are verified; in-game latency, quarter/clock transitions, overtime, corrections and production player-ID matching still need validation. Build 54 remains installed, and the main scoring screens still use MFL data until the new feed is integrated.

Build 55 supersedes the pending-integration status above. See [live NFL scoring](live-nfl-scoring.md) and the latest [current status](current-status.md) for the deployed service, budget and phone delivery.
