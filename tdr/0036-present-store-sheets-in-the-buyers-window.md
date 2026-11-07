# 0036. Present the App Store purchase and refund sheets in the window that asked for them

- **Status:** Accepted
- **Date:** 2026-11-07
- **Feature / area:** `ForeverAlonePoker/Shared/Skins/PurchaseService.swift`, `ForeverAlonePoker/Shared/Skins/SkinStore.swift`, `ForeverAlonePoker/Features/SkinStore` (`BuyButton`, `Help/RefundRequestView`, `Help/PurchaseHelpModel`); supersedes how the sheets are presented in tdr/0012 (purchase) and tdr/0022 decision 2 (refund)

## Context

The app has to resize properly on the foldable iPhone Duo, in iPad split view and in Stage Manager (tdr/0017, tdr/0020). It uses a SwiftUI `WindowGroup`, so on iPad it can have more than one window open.

`StoreKitPurchaseService` found the window for the App Store purchase sheet and the system refund sheet by walking `UIApplication.shared.connectedScenes` and taking the first `.foregroundActive` window scene. With two windows open, that can be a window the player is not looking at. If no scene was active, the call failed with `PurchaseError.noActiveScene`.

StoreKit's documentation recommends the SwiftUI APIs for SwiftUI apps, multi-scene apps included:

- `@Environment(\.purchase)` (`PurchaseAction`, iOS 17) presents the confirmation "in proximity to the scene in which the view displays".
- `View.refundRequestSheet(for:isPresented:onDismiss:)` (iOS 15) does the same for refunds.

## Decision

1. **Purchases.**
   - `PurchaseService.purchase` takes a `PurchaseSheet`: a `Sendable` wrapper around a main-actor closure that presents the purchase confirmation for a StoreKit `Product`.
   - `BuyButton` reads `@Environment(\.purchase)` and passes `PurchaseSheet(purchase)` to `SkinStore.purchase(_:sheet:)`. That initializer lives next to `BuyButton` because `PurchaseAction` belongs to StoreKit's SwiftUI overlay.
   - `StoreKitPurchaseService` still looks up the `Product`, adds `.appAccountToken`, and verifies and pins the result (tdr/0022, tdr/0024). Only the presentation moved.
2. **Refunds.**
   - `PurchaseService.requestRefund(for:)` and `SkinStore.requestRefund(for:)` are removed.
   - `PurchaseHelpModel.requestRefund(_:)` is now synchronous. It marks the row `.requesting` and sets `presentedRefund` to the row's transaction id.
   - Each `RefundRow` attaches `.refundRequestSheet(for: row.id, isPresented:)`, which is bound to `presentedRefund == row.id`. Its `onDismiss` calls `refundSheetClosed(for:with:)`. `RefundOutcome(Transaction.RefundRequestStatus)` keeps the old mapping, and a `RefundRequestError` still becomes `PurchaseError.refundUnavailable`.
3. **No scene walking.** `activeScene()`, `PurchaseError.noActiveScene` and the `UIKit` import are removed from `PurchaseService.swift`. Nothing in the store reads `UIApplication.shared`.

## Consequences

- Both sheets appear in the window the player tapped in: on iPad with two windows, in Stage Manager, and on the foldable as it changes size.
- Every purchase now starts from a view, because the sheet comes from that view's environment. Code without a view, such as an App Intent, would need its own `PurchaseSheet`.
- `PurchaseService` conformers (`StoreKitPurchaseService`, `FakePurchases`, the preview `ScriptedPurchases`) take the new parameter and no longer implement `requestRefund`.
- tdr/0012 (purchase on "the active scene") and tdr/0022 decision 2 (refund "on the foreground `UIWindowScene`") describe the old presentation. Everything else in them still holds.

## Alternatives considered

- **Pass a `UIWindowScene` into `purchase` and `requestRefund`**, read from a helper `UIViewRepresentable`. It would keep the async refund call, but it adds UIKit plumbing to a SwiftUI app and goes against StoreKit's guidance for SwiftUI.
- **StoreKit views (`ProductView`, `StoreView`).** They handle purchases on their own, but the store's custom layout, Buy button, purchase states and unlock celebration (tdr/0018) would all have to be rebuilt.

## Test strategy

- `ForeverAlonePokerTests/Features/SkinStore/PurchaseHelpModelTests`:
  - requesting a refund presents the sheet for that transaction and marks it `.requesting`;
  - a refunded row presents nothing;
  - closing the sheet with submitted, cancelled or failed sets the matching state and clears `presentedRefund`.
- `ForeverAlonePokerTests/Shared/Skins/SkinStoreTests`: the purchase tests pass `PurchaseSheet.unused` (`Support/SkinFakes.swift`), which records an issue if anything ever presents it.
- Manual, with `StoreKit/SkinStore.storekit` active:
  - on iPad, open two windows side by side, buy from the right-hand one, and check that the sheet appears over that window;
  - do the same with Help › Request a Refund;
  - repeat on the iPhone Duo simulator folded, unfolded and half open.
