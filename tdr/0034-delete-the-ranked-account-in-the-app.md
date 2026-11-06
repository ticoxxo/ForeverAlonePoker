# 0034. Delete the ranked account in the app and revoke its Apple tokens

- **Status:** Accepted
- **Date:** 2026-11-05
- **Feature / area:** `ForeverAlonePoker/Features/Profile` (`DeleteRankedAccountView`, `RankedSignInModel`), `ForeverAlonePoker/Shared/Identity/RankedAuthService.swift`, `Server/Sources/PokerServerCore` (`POST /account/delete`, `Identity/AppleTokenRevoker.swift`, `LeaderboardStore.delete`)

## Context

Ranked play (tdr/0010) creates an account with Sign in with Apple: the server stores the Apple subject with the display name, country, rating and record in the CloudKit public leaderboard. App Review Guideline 5.1.1(v) requires every app that lets people create an account to let them delete it from inside the app, and apps using Sign in with Apple must revoke the user's tokens through Apple's REST API when they do. Until now Profile only offered "Sign out of ranked play", which unlinks the device and leaves the row in place.

The server is stateless: it never kept Apple's refresh token, so it has nothing to revoke later.

## Decision

Profile shows **Delete ranked account** to signed-in players. It opens `DeleteRankedAccountView`, which lists what goes and what stays and asks the player to **Continue with Apple**. That fresh sign-in is the confirmation: its identity token proves the owner is present and its authorization code is what the server needs to revoke.

The app sends both to `POST /account/delete` (`AccountDeletionRequest`). The server verifies the identity token like `/auth/apple`, deletes the leaderboard row (`RankingService.forget` → `LeaderboardStore.delete`, a CloudKit `forceDelete` where `NOT_FOUND` counts as done), then `AppleSignInTokenRevoker` redeems the code at `appleid.apple.com/auth/token` with an ES256 client secret and revokes the refresh token (the access token when no refresh token comes back) at `/auth/revoke`. A failed revocation is logged and still answers 204: the player's data is already gone and a retry could not reuse the code. On success, or on 503 (a server without ranked play stores nothing), the app unlinks the profile.

Revocation needs a Sign in with Apple key: `APPLE_TEAM_ID`, `APPLE_SIGNIN_KEY_ID` and `APPLE_SIGNIN_PRIVATE_KEY[_PATH]`. Without them deletion still removes the row and logs a warning.

Local data (name, picture, history, purchases) is not part of the ranked account and stays; the privacy policy (tdr/0035) explains how to remove it.

## Consequences

- The app meets Guideline 5.1.1(v); the player can delete without contacting us.
- Production needs the three Sign in with Apple secrets set on Fly (`fly secrets set ...`), or tokens are not revoked.
- Match history rows already marked ranked on the device keep that mark.

## Alternatives considered

- **Store the refresh token at sign-in.** Needs a private database on the server; the public leaderboard cannot hold secrets.
- **Sign out only, delete on request by email.** Apple rejects deletion that needs a support contact for an account created in the app.
- **Fail deletion when revocation fails.** Leaves personal data in place over an Apple-side error the player cannot fix.

## Test strategy

- `Server/Tests/PokerServerTests/AccountDeletionTests.swift`: row deletion in memory and the CloudKit delete body and response handling; the client secret claims and the token/revoke form calls against a fake `HTTPExecutor`; environment wiring; the route deleting and revoking, refusing forged tokens, surviving a failed revocation, and answering 503 without ranked play. Uses `makeRanked` and `FakeVerifier` from `RankedTests.swift`.
- `ForeverAlonePokerTests/Features/Profile/RankedSignInModelTests.swift`: deletion unlinks, a 503 still unlinks, a rejection explains itself and keeps the player signed in.
- Manual: on a device with a real Sign in with Apple key, delete and check that the app disappears from Settings > Apple Account > Sign in with Apple.
