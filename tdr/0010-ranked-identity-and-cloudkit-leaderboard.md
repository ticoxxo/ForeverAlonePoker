# 0010. Prove ranked identity with Sign in with Apple and publish Elo to the CloudKit public database from the server

- **Status:** Accepted
- **Date:** 2026-10-08
- **Feature / area:** `Packages/PokerCore/Sources/PokerCore/Protocol`, `Server/Sources/PokerServerCore/{Identity,Rankings}`, `ForeverAlonePoker/Shared/{Persistence,Identity}`, `Features/Profile`, `Features/Leaderboard`, `Features/OnlineMatch`

## Context

tdr/0006 planned two account tiers on top of the default user: iCloud sync (tier 1) and a ranked identity with world and country leaderboards (tier 2). tdr/0009 fixed the Elo math in CORE. This record covers how the pieces connect now that the paid developer account, the iCloud container and the capabilities exist.

Constraints: clients never run rules or write competitive data (tdr/0003); Apple's identity token lives five minutes and can only be obtained interactively, so it cannot be sent on every join; a custom server cannot verify a CloudKit user record ID; CloudKit cannot count rows, so absolute rank is out of scope.

## Decision

1. **Tier 1 is a configuration switch.** `Persistence.store()` opens the SwiftData store with `cloudKitDatabase: .private("iCloud.Ticoxxo.ForeverAlonePoker")` and falls back to the same file without mirroring if CloudKit cannot be set up (a build without the entitlement). The app reports `IdentityStore.isCloudSyncEnabled` from `CKContainer.accountStatus` and calls `IdentityStore.refresh()` on every `NSPersistentStoreRemoteChange`. Two devices that each created a default profile before their first sync are merged by `refresh()`: the **oldest profile wins**, keeps every match, and adopts the Apple identity of the duplicate if it has none. Deterministic on both devices, so they converge.

2. **Ranked identity is a server session, not Apple's token.** Profile shows a `SignInWithAppleButton`; the identity token goes once to `POST /auth/apple` on the game server, which verifies it with jwt-kit against Apple's JWKS (issuer, expiry, audience = bundle id) and answers with its own HS256 session token (30 days, `SESSION_SECRET`) and the Apple user id. The app stores both on `PlayerProfile` (`appleUserID`, `rankedSessionToken` with `.allowsCloudEncryption`) so every device of the player is ranked after one sign-in. From then on `PlayerIdentity.id` is the Apple user id and `PlayerIdentity.countryCode` carries the profile country.

3. **Protocol version 2.** `ClientMessage.join(PlayerIdentity, sessionToken: String?)`, `PlayerIdentity.countryCode`, and `ServerMessage.rated(RatingUpdate)`. The rules (`MatchRoom`) ignore the token; the server `Room` verifies it before the rules see the message, rejects mismatches ("account does not match this player") and expired tokens, and remembers the seat as ranked. A seat (re)joined without a valid token is unranked.

4. **The server rates and publishes.** When a match between two ranked seats reaches `.finished`, `Room` hands winner and loser to `RankingService` (an actor, so concurrent finishes never interleave a read-modify-write), which looks up both `LeaderboardEntry` rows, applies `EloCalculator.update`, increments wins/losses, refreshes name and country from the identities, saves, and the room sends `.rated` to both players. The CloudKit call runs off the room actor. Local and practice matches, and online matches with an unsigned seat, are never rated. A player cannot be rated against themselves.

5. **Leaderboard rows live in the CloudKit public database, written only by the server** through CloudKit Web Services with a server-to-server key (ES256 signature over `date:sha256(body):path`, `CloudKitRequestSigner`). Record `LeaderboardEntry`, name `rating-<appleUserID>`, fields `displayName`, `countryCode`, `rating`, `matchesPlayed`, `wins`, `losses`, `updatedAt`; writes use `forceUpdate`. Clients write only their own `PublicProfile` (`profile-<appleUserID>`: `displayName`, `countryCode`, `avatar` asset) after sign-in and profile edits. Clients read with `CKQuery` sorted by `rating`, optionally filtered by `countryCode`, top 100, plus their own row pinned when outside the top (`Features/Leaderboard`).

6. **Server configuration by environment.** `SESSION_SECRET` enables ranked play; `APPLE_BUNDLE_ID` (default `Ticoxxo.ForeverAlonePoker`); `CLOUDKIT_CONTAINER` (default `iCloud.Ticoxxo.ForeverAlonePoker`), `CLOUDKIT_ENVIRONMENT` (`development` | `production`), `CLOUDKIT_KEY_ID`, `CLOUDKIT_PRIVATE_KEY` or `CLOUDKIT_PRIVATE_KEY_PATH`. Without a CloudKit key the leaderboard is an in-memory store (development with `PokerBot`); without the secret `/auth/apple` answers 503 and tokens on join are ignored.

## Consequences

- A ranked player sees "Rating 1220 (+20)" on the match-over banner and the match is marked ranked in history.
- Account-side setup is required and documented in this record's "Operations" notes below; the CloudKit schema (record types, indexes, security roles) must be deployed to production before release.
- Disconnecting mid-match only forfeits the hand (tdr/0003); a ranked player can abandon a losing match without taking the loss. Follow-up: time out a held seat and score it as a loss.
- Session tokens are revocable only by rotating `SESSION_SECRET` (which signs everyone out). Follow-up if needed: a server-side denylist.
- Rows carry the name and country at the time of the last match; a player who changes country moves leaderboards after their next ranked match.

## Alternatives considered

- **Sending Apple's identity token on every join.** Impossible without an interactive sign-in each time.
- **Refresh tokens through Apple's `/auth/token`.** Needs a Services ID and a private key on the server for nothing we use; our own session token is simpler and sufficient.
- **Server writes to CloudKit with CloudKit JS or a user token.** Server-to-server keys are what Apple provides for this; user tokens would make the server impersonate a player.
- **Clients writing `LeaderboardEntry`.** Rejected in tdr/0006.
- **Game Center leaderboards.** Rejected in tdr/0006.

## Test strategy

- `PokerCoreTests/ProtocolTests`: ranked join and rating update round-trip, version bumped.
- `PokerServerTests/RankedTests`: Apple token verification with a throwaway RSA key (valid, wrong audience, wrong issuer, expired, key rotation refetch); session tokens (round-trip, tampered, foreign secret, expired); CloudKit request signature verifies with the public key, record JSON bodies and response parsing, environment configuration; `RankingService` first match (±20) and later matches from stored ratings; `Room` publishes and delivers `.rated`, rejects bad and mismatched tokens, never publishes unranked matches, ignores tokens when unconfigured; `/auth/apple` 200/401/503.
- `ForeverAlonePokerTests`: `IdentityStoreTests` (link/unlink, identity country, marking ranked, duplicate-profile merge), `MatchSessionClientTests/rankedJoin` with a scripted transport, `LeaderboardModelTests` with a fake service, `RankedSignInModelTests` with fake auth and publisher.
- Manual: Sign in with Apple on a device, play a ranked match against a second signed-in device, check the `LeaderboardEntry` row in the CloudKit Console and the Leaderboard screen.

## Operations (dated notes)

### 2026-10-08. Account and console setup

1. developer.apple.com: accept the current Program License Agreement (Xcode cannot register capabilities until then).
2. Xcode, target `ForeverAlonePoker`, Signing & Capabilities: iCloud (CloudKit, container `iCloud.Ticoxxo.ForeverAlonePoker`), Push Notifications, Background Modes (Remote notifications), Sign in with Apple. The entitlements file and Info.plist already carry them; a device build with automatic signing registers them on the App ID.
3. CloudKit Console, container `iCloud.Ticoxxo.ForeverAlonePoker`, Development schema: record types `LeaderboardEntry` (`displayName` String, `countryCode` String, `rating` Int64, `matchesPlayed` Int64, `wins` Int64, `losses` Int64, `updatedAt` Date/Time) and `PublicProfile` (`displayName` String, `countryCode` String, `avatar` Asset). Indexes: `LeaderboardEntry.rating` SORTABLE, `LeaderboardEntry.countryCode` QUERYABLE, `recordName` QUERYABLE on both. Security roles: `_world` Read on both; `_icloud` Create and `_creator` Write on `PublicProfile`; no `_icloud` Create or Write on `LeaderboardEntry`.
4. CloudKit Console, Tokens & Keys, Server-to-Server Keys: create one from the public half of an EC P-256 key (`openssl ecparam -name prime256v1 -genkey -noout -out cloudkit.pem; openssl ec -in cloudkit.pem -pubout`), note the Key ID.
5. Run the server with `SESSION_SECRET`, `CLOUDKIT_KEY_ID`, `CLOUDKIT_PRIVATE_KEY_PATH=cloudkit.pem` (and `CLOUDKIT_ENVIRONMENT=production` once the schema is deployed).
