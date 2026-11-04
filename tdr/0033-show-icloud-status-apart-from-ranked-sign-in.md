# 0033. Report the iCloud account in Profile and keep ranked sign-in apart from it

- **Status:** Accepted
- **Date:** 2026-11-04
- **Feature / area:** `ForeverAlonePoker/Features/Profile`, `ForeverAlonePoker/Shared/Identity/CloudAccount.swift`, `ForeverAlonePoker/App`

## Context

A log-out from iCloud was requested for Profile. iOS gives apps no way to sign the device out of iCloud: the account belongs to the system and changes only in Settings.

Behind the request was a real problem. A player signed into iCloud still saw a Sign in with Apple button in the account section, which reads as an iCloud log-in. That button is the ranked opt-in (tdr/0010) and cannot go away: the server cannot verify an iCloud account, so it is the only way to reach ranked play. `IdentityStore.tier` also puts ranked ahead of iCloud, so a ranked player's iCloud state was never shown.

## Decision

Profile shows the two accounts in two sections, worded by `AccountStatus` (`Features/Profile`):

- **Account** reports iCloud and offers no action: "Signed in" with `checkmark.icloud.fill`, or "Not signed in" with `icloud.slash` and a footer pointing to Settings. It reads `IdentityStore.isCloudSyncEnabled` rather than `tier`.
- **Ranked play** holds the Sign in with Apple button, labelled optional, or the signed-in row and "Sign out of ranked play".

The app has no iCloud log-out. `reportCloudTier()` re-checks `CloudAccount.isAvailable()` on every `.CKAccountChanged` (`CloudAccount.changes`) so the row follows changes made in Settings while the app runs.

## Consequences

- No data, sync or sign-in behaviour changes; `Tier` stays as it is.
- An iCloud sign-out in Settings updates the row, but the store stays opened as it was at launch.
- Follow-up if asked for: a setting to stop mirroring (`disableCloudSync` exists but nothing in the UI writes it). Needs a decision on the data left on the device.

## Alternatives considered

- **Stopping iCloud sync and calling it log-out.** The device would stay signed into iCloud, so the name would mislead. Declined.
- **Hiding the Apple button for iCloud players.** Closes ranked play to most players.
- **Moving ranked sign-in to the Leaderboard screen.** Needs the sign-in model and button in `Shared` because features never import each other, for no gain over a clearly labelled section.

## Test strategy

- `AccountStatusTests`: label, symbol and footers for both iCloud states, a ranked player keeps their iCloud state, ranked footer before and after sign-in.
- Manual only: the signed-in row and `.CKAccountChanged` need a signed build with an iCloud account (`CKContainer` traps without the entitlement).
