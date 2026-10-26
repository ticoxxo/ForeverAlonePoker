# 0024. Trust Xcode StoreKit testing on StoreKit's verification and pin every App Store transaction to Apple Root CA – G3

- **Status:** Accepted
- **Date:** 2026-10-26
- **Feature / area:** `ForeverAlonePoker/Shared/Skins` (`TransactionCertificateValidator`, `PurchaseService`); supersedes the root choice in tdr/0022, decision 4

## Context

tdr/0022 pinned Debug builds to `StoreKitTestCertificate.cer` (from Xcode's Editor › Save Public Certificate) and Release builds to `AppleIncRootCertificate.cer`. In use, every local purchase was denied:

- The Transaction Manager listed the Spanish Deck as *Purchased*.
- The app showed "The purchase could not be completed.", and the set stayed locked after relaunch.

The saved certificate is the legacy RSA 2048 "StoreKit" root, with *Code Signing* usage. It signs only the PKCS#7 receipt. StoreKit 2 transactions from Xcode testing are ES256 JWS signed with a key local to the Xcode install, and that key chains to no certificate an app can bundle. The pin can therefore never pass for Xcode transactions. They are denied in `purchase`, `currentEntitlements`, `updates` and `purchaseHistory`.

Apple's App Store Server Library skips chain verification for the `xcode` environment for the same reason.

## Decision

1. `TransactionCertificateValidator` gains `trustsLocalTesting` and `validate(jws:environment:)`:
   - When the environment is `AppStore.Environment.xcode`, the result is `trustsLocalTesting`, resting on StoreKit's own `.verified`.
   - Every other environment (production, sandbox, TestFlight) goes through the existing pin: an `x5c` chain to the bundled root plus the ES256 signature.
2. `bundled()` always pins to `AppleIncRootCertificate.cer` (Apple Root CA – G3). Only `#if DEBUG` sets `trustsLocalTesting: true`. Release builds deny any Xcode-signed transaction.
3. `StoreKitPurchaseService.trusted(_:)` passes the verified `Transaction.environment`.

## Consequences

- Local purchases with `StoreKit/SkinStore.storekit` grant again, and earlier ones show up through `currentEntitlements`.
- Debug builds now also grant sandbox purchases, because they are pinned to the same root as Release. tdr/0022's "Debug builds only trust Xcode's StoreKit testing" no longer holds.
- `StoreKitTestCertificate.cer` is no longer read and can be removed from `Resources/Certificates`.
- A Debug build trusts StoreKit alone for Xcode transactions. That is acceptable: Debug builds never ship.

## Alternatives considered

- **Bundle the Xcode signing certificate from a captured JWS.** It is specific to the machine and Xcode install, so it breaks on every other developer's Mac and on CI.
- **Read `environment` from the JWS payload instead of `Transaction`.** It is equivalent once StoreKit has verified the transaction, but the typed property is clearer.
- **Disable pinning in Debug entirely.** That would let sandbox data with a broken chain pass unnoticed until Release.

## Test strategy

- `ForeverAlonePokerTests/Shared/Skins/TransactionCertificateValidatorTests`:
  - an Xcode transaction is accepted when local testing is trusted, even under an unpinned root;
  - an Xcode transaction is denied when local testing is not trusted (Release);
  - sandbox and production transactions stay pinned while local testing is trusted.
- Manual: with `StoreKit/SkinStore.storekit` active, buy a set and check it unlocks. Relaunch and check it stays unlocked.
