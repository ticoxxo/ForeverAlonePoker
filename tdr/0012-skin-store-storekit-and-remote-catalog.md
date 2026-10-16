# 0012. Sell skins with StoreKit 2 and deliver them through a signed remote catalog

- **Status:** Accepted (opponent loadout over the protocol: planned, see 6). Amended 2026-10-15: card fronts are sold only as whole sets.
- **Date:** 2026-10-11
- **Feature / area:** `ForeverAlonePoker/Shared/Skins`, `ForeverAlonePoker/Features/SkinStore`, `Server/Sources/PokerServerCore/Store`, `Server/Sources/SkinPublisher`, `Server/SkinAssets`, `StoreKit/SkinStore.storekit`

## Context

The store sells card-face sets and card backs, and must work with these constraints:
- Adding a set, changing a price or running a sale must not require an app update.
- Prices are $0.99 per set and per back.
- Prices are set remotely by a separate project.
- The store must handle currency per user and comply with Apple's rules.

A strategy note (`skin-assets-strategy.md`) recommended keeping art out of the binary, delivering it remotely with checksums, and putting the models in a Swift package. Several facts constrain the rest:

- **Price points.** In-app purchase prices are App Store Connect price points. The lowest in the US is **$0.29**, so 25 cents isn't possible. Prices and scheduled price changes (sales with start and end dates) are set in App Store Connect, by hand or through the **App Store Connect API**, which is how "another project" sets prices. Our servers can't charge a different amount.
- **Commission.** Apple keeps **15%** (Small Business Program, under $1M a year) or **30%**; card-processing percentages don't apply. A $5 pack nets about $4.25 or $3.50. Where Apple remits VAT/GST, proceeds are calculated after tax.
- **Payment methods.** App Review Guideline 3.1.1 requires in-app purchase for digital goods used in the app; **Apple Pay (PassKit) is not allowed** for them. The App Store sheet already offers every method on the player's Apple Account: cards (including those in Apple Wallet), Apple Account balance and gift cards, carrier billing, and PayPal where available. Family approval (Ask to Buy) and bank authentication (SCA) surface as `.pending`.
- **Currency.** The price currency follows the **App Store storefront**, not the device locale or region. StoreKit localizes `displayPrice` and `priceFormatStyle`, and `Storefront.updates` reports changes.
- **Asset delivery options.** On-Demand Resources tie content to App Store Connect uploads and were deprecated in favour of Background Assets (Apple-hosted packs) in iOS 26, which are also uploaded through App Store Connect. Apple-hosted IAP content no longer accepts new content. Restore must be offered for non-consumables.

## Decision

1. **Products.** Every item is exactly one **non-consumable** in-app purchase with a conventional id (`ProductIDs`):
   - `fap.skin.<set>.set` for a set, $0.99;
   - `fap.skin.<item>` for a back, $0.99.

   The catalog never carries prices. Product ids are permanent, so a sold item is never renamed.

   **Sets are sold whole, never card by card** (amended 2026-10-15, before launch). The first version also sold every card on its own (`fap.skin.<set>.card.<notation>`, $0.29, 52 per set). That was removed because:
   - each set needed 53 App Store Connect products instead of one;
   - a set bought after some cards could not get cheaper. A non-consumable has one fixed price, so a discount needs extra discounted set products, and refunds of the cards bought first can be gamed against them;
   - the store and its tests become simpler: a set is owned all or nothing.

   No single-card product was ever submitted, so no player is affected. Equipping stays per slot (tdr/0011): an owned set can still be used on some cards and the classic deck on others. The `sellsSingleCards` catalog key is gone; older manifests that still carry it decode fine because unknown keys are ignored.
2. **Ownership** is StoreKit 2's `Transaction.currentEntitlements`: verified transactions with no `revocationDate`. The App Store signs transactions (JWS) and StoreKit verifies them; unverified ones are finished and never granted. Ownership is never persisted by the app, so refunds and other devices are always reflected. `PurchaseService` is a protocol, and `StoreKitPurchaseService` implements it:
   - **Product loading:** 50-id batches loaded in parallel (`TaskGroup`).
   - **Purchase:** `purchase(confirmIn:options:)` on the active scene with `.appAccountToken(profile.localID)`, returning `.purchased(finish:)`, `.pending` or `.cancelled`.
   - **Restore:** `AppStore.sync()`.
   - **Listeners:** `Transaction.updates` and `Storefront.updates`, exposed as `AsyncStream`s.

   `SkinStore` starts both listeners at launch (`.task` on the root). A purchase or update first refreshes entitlements, then finishes the transaction, then downloads.
3. **Catalog.**
   - **Endpoint:** the game server serves `GET /store/catalog` → `SignedCatalog { manifest (bytes), signature (Ed25519), keyID }`, with an `ETag` and `Cache-Control: no-cache`.
   - **Source file:** `manifest.json` in `SKINS_DIR`, re-read whenever it changes on disk (publishing is a file copy, no restart). A malformed new file keeps the last good catalog in service. The server signs with `CATALOG_SIGNING_KEY` and logs a warning when it serves unsigned.
   - **App trust:** the app pins publisher public keys in Info.plist (`SkinCatalogPublicKeys`, key id → base64), so keys rotate by shipping the new public key first. Release builds refuse unsigned or unverifiable catalogs. Debug builds with no pinned keys accept an unsigned development server.
   - **Client:** `HTTPCatalogClient` revalidates with `If-None-Match` and caches only verified catalogs, re-verifying the cache on launch.
   - **Decoding:** lenient. Unknown fields and malformed items are skipped, items of kinds the build can't draw or newer than its `minAppVersion` are hidden, and only a newer `schemaVersion` is refused.
4. **Files.**
   - Each `AssetRef` has a path relative to `assetBaseURL`, its SHA-256 and its size. `assetBaseURL` is `/skins/` on the development server (served from `SKINS_DIR` by `FileMiddleware`) or a CDN URL in production.
   - `SkinAssetRepository` (an actor) downloads only the **slots the player owns**, verifies the SHA-256, writes atomically to `Application Support/Skins/<item>/<slot>.png` (excluded from backup) and indexes the verified hash, so a republished file is downloaded again.
   - Downloads use a background `URLSession` (`BackgroundSkinDownloader`, delegate-bridged to async/await, `SkinDownloadAppDelegate` for relaunch events), so a set keeps downloading after the player leaves the app. At most 4 run at a time from `SkinStore.syncAssets`.
   - Store previews of unowned art use `AsyncImage`.
5. **Publishing.**
   - **This repo:** `SkinPublisher` (dev tool in `Server/`) has three commands:
     - `import <artwork>`: maps artist files to slot files and skips jokers, previews and SVGs;
     - `manifest`: hashes the files, applies product-id conventions and per-item `item.json` metadata (names, badge, `minAppVersion`), and bumps the version;
     - `keygen`: creates an Ed25519 key pair.
   - **Pricing project:** the separate pricing project produces the same manifest with SkinKit and drives prices and sales through the App Store Connect API. New in-app purchase products need App Review for the product, not an app update.
   - **Shipped content:** the Spanish set and the red check and red rosette backs ship in `Server/SkinAssets` as the first remote items. `StoreKit/SkinStore.storekit` mirrors their 3 products for local testing.
6. **Opponent loadout (planned, protocol v3).**
   - `PlayerIdentity` gains `cosmetics: [String: String]?` (the opaque `Loadout.wire`), and `MatchRoom` copies it into the opponent's `PlayerSummary`. `ProtocolVersion.current` becomes 3. Rules, `HandEngine` and `MatchState` are untouched.
   - The receiving app calls `SkinStore.opponentCardSkin(_:)`, which shows only skins installed locally and falls back to the default for the rest.
   - Until then `TableView` draws the opponent with `.standard`, which is what "no information" requires.
7. **Server-side receipt checks (planned).** Apple's `app-store-server-library-swift` would support two endpoints:
   - `POST /store/asset-access`: verify `Transaction.jwsRepresentation` against Apple's root certificates and return short-lived signed CDN URLs, so paid art can't be scraped from public paths;
   - App Store Server Notifications V2: refunds and analytics.

   The `appAccountToken` is already sent so those records tie to a player. Until then the files are public at versioned, hash-checked paths, which is acceptable for low-value cosmetic art.

## Consequences

- Sets, backs, artwork updates, badges, prices and sales change with no app update and no server restart. Only a new cosmetic kind needs an app update (tdr/0011).
- Offline launches use the cached verified catalog, the installed files and the defaults; nothing blocks play.
- One App Store Connect product per set or back (limit: 10,000 in-app purchases per app); `fap.skin.spanish_001.set` ("Spanish Deck") already exists.
- **Operations:**
  - accept the Paid Apps agreement;
  - create the products;
  - run `SkinPublisher keygen` and pin the public key in Info.plist;
  - set `CATALOG_SIGNING_KEY` as a server secret (never commit it);
  - pick the StoreKit configuration in the scheme for local testing.

## Alternatives considered

- **Bundling every skin** (or On-Demand Resources, or Background Assets): each new set goes through App Store Connect and often an app update. Rejected by the "no update per set" requirement.
- **A virtual currency** (buy coins via IAP, spend 25 per card): exact $0.25 pricing and server-driven sales, but it needs a server ledger and database, StoreKit can't restore it, and it draws more review scrutiny. Rejected in favour of direct non-consumables.
- **Apple Pay or an external processor:** not allowed for in-app digital goods (3.1.1). US-only external purchase links are out of scope.
- **Unsigned catalog over HTTPS only:** a compromised CDN or proxy could swap items or asset URLs, and the signature costs one line on each side.
- **Selling single cards** ($0.29 each, alongside the set): see the amendment in decision 1. A set price that drops by $0.10 per owned card would need 7 extra discounted set products per set, picked by the app, and purchase-date bookkeeping so refunded cards can't be kept through the discount. Rejected as too much product and code for a cosmetic.
- **Discount-free single cards plus the set:** players who bought a few cards pay full price for the set anyway, which reads as unfair.

## Comparison with `skin-assets-strategy.md`

| Topic | Strategy note | This decision |
|---|---|---|
| Art outside the binary; no second Xcode project | Recommended | Agreed. Only the free default set and back are bundled. |
| Delivery | On-Demand Resources, or remote CDN | Remote CDN or server only. ODR (now deprecated for Background Assets) and Apple-hosted packs both go through App Store Connect. |
| Format | Zipped images or a compiled asset catalog | Loose PNG files plus a manifest. A downloaded asset catalog can't be compiled at runtime, and SVG can't be rendered at runtime (tdr/0011). |
| Integrity | Checksum or signature | Both: SHA-256 per file and an Ed25519-signed manifest with pinned keys. |
| Models package | Optional `PokerSkinsKit` / `SkinRenderingKit` | `SkinKit` is required, shared by the app, server and publisher, with test builders. Rendering stays in the app's DesignSystem. |
| Cache | Application Support or Caches, LRU eviction | Application Support, excluded from backup. Owned files are kept and re-downloaded if lost. Only owned slots are downloaded, so eviction isn't needed yet. |
| Fallback | Default skin if a pack is missing or corrupt | Generalised into `SkinResolver`, which also covers refunds, opponents, unknown kinds and offline play. |
| Purchases | "StoreKit purchase flow" | StoreKit 2 entitlements as the only ownership source, launch-time listeners, `.pending`, restore, `appAccountToken`, storefront currency. |
| Pricing | Catalog metadata from the backend | Corrected: App Store Connect owns prices and sales, through its API from the pricing project. The catalog never carries a price. |
| Not covered by the note | | Whole-set-only sales, the $0.29 minimum price, the commission, App Review 3.1.1 and restore, forward-compatible kinds, multiplayer fallback. |

## Test strategy

- `Server/Tests/PokerServerTests/StoreTests`:
  - signing;
  - unsigned mode;
  - hot reload, keeping the last good catalog on a broken file;
  - missing manifest;
  - environment configuration;
  - `/store/catalog` 200, 304 and 503;
  - `/skins` file serving;
  - publisher import (jokers and previews skipped);
  - manifest hashes, product ids, metadata and previews;
  - key generation.
- `ForeverAlonePokerTests/Shared/Skins`:
  - `SkinStoreTests`: purchase, pending → approved via updates, cancel and failure, refund, restore, storefront change reloads prices, owned-only downloads, an unbought set can't be equipped, a bought set shows every card, single-card entitlements unlock nothing;
  - `CatalogClientTests`: pinned-key verification, tampering, unknown keys, unsigned policy, ETag revalidation, nothing cached on failure, asset URL resolution;
  - `SkinAssetRepositoryTests`: install and index, checksum mismatch discarded, republished hash re-downloads, backup exclusion.
- Manual, with `StoreKit/SkinStore.storekit` selected in the scheme:
  - buy the Spanish set and check all 52 cards unlock; locked cards offer no purchase of their own;
  - approve an Ask to Buy and refund from Xcode's Transaction Manager;
  - change the storefront to check currency;
  - run `swift run --package-path Server PokerServer` with the default `Server/SkinAssets`.
