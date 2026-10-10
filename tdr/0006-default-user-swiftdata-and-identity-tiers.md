# 0006. Start as a default user in SwiftData; grow into iCloud and ranked identities without migration

- **Status:** Accepted (tier 0 implemented here; tiers 1 and 2 implemented per tdr/0010)
- **Date:** 2026-10-07
- **Feature / area:** `ForeverAlonePoker/Shared/Persistence`, `ForeverAlonePoker/Shared/Identity`, `Features/Home`, `Features/Profile`; later `Features/Leaderboard`, `Server/Sources/PokerServer/{Identity,Rankings}`

## Context

The app must be playable immediately with no sign-in, and later offer an account backed by Apple iCloud with match history, world and country rankings and a profile picture. The user asked that any persistence use SwiftData.

## Decision

### Tier 0 (implemented): default user on device
- One `PlayerProfile` row is created on first launch (`displayName` "Player", `countryCode` from `Locale.current.region`, random `localID`). `IdentityStore` is the only writer; it exposes `identity` (`PlayerIdentity` for the table) and `recentMatches`.
- `MatchRecord` rows are written when `MatchSessionClient` reports `onMatchFinished`; the client knows nothing about persistence, features wire the callback (`LocalMatchView`, `PracticeTableView`).
- Schema is CloudKit-compatible from day one: defaults on every property, optional relationships, no unique attributes, mode stored as a raw string.

### Tier 1 (planned): iCloud sync
- Switch `Persistence.container()` to `ModelConfiguration(cloudKitDatabase: .private("iCloud.Ticoxxo.ForeverAlonePoker"))` when `CKContainer.accountStatus == .available`; otherwise stay local. No schema change. Requires iCloud + CloudKit, Push Notifications and Background Modes (remote notifications) capabilities. `IdentityStore.isCloudSyncEnabled` reports the tier.

### Tier 2 (planned): ranked player
- Opting into ranked play performs Sign in with Apple; the stable subject is stored in `PlayerProfile.appleUserID` (synced by tier 1) and sent with `ClientMessage.join` so the server can verify a JWT. A CloudKit user record ID cannot be verified by a custom server, which is why Sign in with Apple is used for the server-facing identity.
- Public data lives in the CloudKit **public database**: `PublicProfile` (name, country, avatar asset) written by the client; `LeaderboardEntry` (rating, wins, losses) written **only by the server** via CloudKit Web Services with a server-to-server key after each completed online match. Elo math lives in PokerCore (`Rating/`). Clients read leaderboards with `CKQuery` sorted by rating, optionally filtered by `countryCode`. Local matches are never ranked.

## Consequences

- Upgrading tiers never migrates data: the same row gains sync, then an Apple user id.
- Avatars are downscaled to 256 px JPEG before storing so they stay cheap to sync as CloudKit assets.
- Absolute rank position ("#4,321 in the world") needs a count that CloudKit cannot do; v1 shows Top 100 world/country plus the player's own entry.
- CloudKit and Sign in with Apple need a paid developer account and dashboard setup; Postgres stays out unless CloudKit Web Services proves too limiting (tdr/0003).

## Alternatives considered

- **Game Center identity and leaderboards.** Free and simple, but no country leaderboards and the user asked for iCloud.
- **Postgres-backed accounts and rankings.** Splits the player's data between iCloud and a second store; kept as fallback.
- **Client-written leaderboard records.** Trivially cheatable; competitive data must come from the referee.

## Test strategy

- `IdentityStoreTests`: default user created once, reopen keeps the same user, trimmed edits, match recording order and counts, tier mapping.
- `CountryFlagTests`: region code to flag and name.
- `MatchSessionClientTests/reportsFinishedMatch`: the finish callback fires exactly once per match with the final stacks.
- Tier 1 and 2 behaviour is verified when implemented (two devices on one iCloud account; CloudKit Dashboard for leaderboard entries).

## Notes

### 2026-10-08

Tiers 1 and 2 are implemented; the details that differ from the plan above (server session tokens instead of Apple's identity token on every join, protocol version 2, duplicate-profile merge, record names and fields) are in tdr/0010.
