# 0011. Model cosmetic skins in a pure SkinKit package and render them through the environment

- **Status:** Accepted
- **Date:** 2026-10-11
- **Feature / area:** `Packages/SkinKit`, `ForeverAlonePoker/Shared/Skins`, `ForeverAlonePoker/Shared/DesignSystem/CardViews.swift`, `ForeverAlonePoker/Features/Table/TableView.swift`, `ForeverAlonePoker/Shared/Persistence/Models.swift`

## Context

Players will customise how cards look: a skin per card face (bought as a whole set or card by card) and a card back. The mat and chips are next. Constraints:

- **The game does not care.** `PokerCore` (cards, rules, protocol) must not learn that skins exist. `CardView(card:)` and `CardBackView()` are used across the table and must not grow skin parameters.
- **Opponents.** A player facing someone over the network may not know which skins the opponent uses. Unknown means the default skin.
- **Artwork.** Three zips arrived: a default 52-card set, a Spanish set (`spanish_001`) and three backs (`navy_check` is the default). Each came as SVG and as 750×1050 PNG. Files are named `<suit>_<rank>_<set>` (rank `10`, while CORE writes `T`) and `back_<name>[_default]`. Each set also has two jokers.
- **SVG is not usable at runtime on iOS.** iOS has no public API that renders SVG data at runtime. Asset-catalog SVG is compiled at build time only, and CoreSVG drops `<text>`, which all 108 face SVGs use for ranks (Georgia). The Spanish set also uses `feTurbulence`/`feDisplacementMap` filters, and the rosette back uses `<pattern>`.

## Decision

1. **`Packages/SkinKit` is the pure model**: Swift 6, no UI, no networking, no StoreKit. It depends on PokerCore only to read `Card`; PokerCore never imports it. The app, the server and the catalog publisher all share it. Its types:
   - `CosmeticKind`: an open string type, not an enum. It has `cardFront`, `cardBack`, `mat` and `chips` now, and catalogs may carry kinds a build cannot draw yet.
   - `CosmeticSlot`: a stable key for one place on screen, such as `front.As`, `back`, `mat` or `chips.100`.
   - `SkinItem`, `SkinCatalog` and `AssetRef`: the store's items and their files (see tdr/0012).
   - `Loadout`: slot → skin id. It is the player's choice, and its JSON form is a flat object.
   - `Ownership`: App Store product ids, or "everything" for rendering opponents.
   - `InstalledAssets`: the files present on this device.
   - `ProductIDs`, `AssetNaming` (artist names → slots; jokers ignored) and `SetPricing`.
   - `SkinCatalog.builtIn`: the free defaults, `default` (fronts) and `navy_check` (back).
   - `SkinKitTestSupport`: `SkinCatalogBuilder` and `LoadoutBuilder`.
2. **`SkinResolver` holds the one fallback rule.** A slot shows its selected item only if all of these hold:
   - the item is in the catalog;
   - it has the slot's kind;
   - it is owned;
   - its file for that slot is installed (bundled defaults always are).

   Anything else shows the default. Refunds, missing or corrupt downloads, items withdrawn from the catalog, unknown kinds and offline launches all go through this one rule. **Opponents** use the same rule with `Ownership.everything` (cosmetics are not policed) but only skins already installed here. So an opponent we know nothing about, or whose skin we don't have, is drawn with the default.
3. **Rendering through the environment.**
   - `SkinStore` (app, `@Observable`) turns catalog, ownership, installed files and loadout into a `CardSkin`: a plain value mapping slot → `SkinImageSource` (`bundled`, `file` or `remote`).
   - `ContentView` sets `.environment(\.cardSkin, skins.myCardSkin)`.
   - `CardView` and `CardBackView` keep their signatures and read `@Environment(\.cardSkin)`. They fall back from a downloaded file, to the bundled default PNG, to the original drawn view.
   - `TableView` overrides the environment on `OpponentSeatView` with the opponent's skin, `.standard` until their loadout travels (tdr/0012). Board cards use the viewer's own skin.
   - `PlayerView`, `MatchSessionClient` and the rules are unchanged.
4. **PNG, not SVG.** The bundled defaults are 750×1050 PNG image sets in `Assets.xcassets/Skins` (`skin-default-front-As`, `skin-navy_check-back`; 53 files, ~2.5 MB). Downloaded skins are PNG too. They are decoded off the main thread and downsampled to 360 px by `SkinImageCache` (ImageIO), because a full-size PNG costs ~3 MB decoded. The SVGs stay as master art in the publishing pipeline, which can rasterise them (or emit HEIC for roughly half the bytes).
5. **Persistence.**
   - The loadout is `PlayerProfile.cosmeticLoadout` (JSON) plus `cosmeticLoadoutUpdatedAt`. It has defaults, so it stays CloudKit-compatible, and it syncs with the profile.
   - When duplicate profiles merge, the newest loadout wins.
   - `IdentityStore` stays the only writer (`updateLoadout`, through `LoadoutPersisting`).
   - Ownership is **never** stored; it comes from StoreKit entitlements (tdr/0012).
6. **Card geometry** follows the artwork: 5:7 (`CardMetrics.aspectRatio`).

## Consequences

- A new set, back or price needs no app update. A new *kind* (mat, chips) needs one app update for its renderer: add it to `SkinStore.supportedKinds` and read a new environment slot. Older builds ignore catalog items of kinds they don't know.
- The table, the engine and the wire protocol stayed untouched. Only the opponent seat's environment override is new.
- The jokers are not shipped or mapped.
- The app depends on a second local package, linked once through Xcode: File ▸ Add Package Dependencies ▸ Add Local ▸ `Packages/SkinKit`. Link `SkinKit` to the app, and `SkinKit` plus `SkinKitTestSupport` to `ForeverAlonePokerTests`.
- The CloudKit schema gains two `PlayerProfile` fields. Deploy them to production before release.

## Alternatives considered

- **Skin parameters on `CardView` or skin fields on `Card`.** Leaks cosmetics into every call site and into CORE; rejected by the "game does not care" constraint.
- **SVG at runtime** (WKWebView or a third-party renderer). Heavy, and either slow or incomplete for these files (`<text>`, filters). Pre-rendered PNG is exact.
- **A closed `enum CosmeticKind`.** Every new kind would break decoding in older builds.
- **Storing ownership in SwiftData.** Duplicates the App Store's truth, can be tampered with, and would miss refunds.

## Test strategy

- `Packages/SkinKit/Tests` (`swift test --package-path Packages/SkinKit`):
  - slot keys and kinds;
  - artist-name mapping, including `10` → `T` and jokers ignored;
  - product id scheme;
  - lenient catalog decoding (unknown fields, malformed items, unknown kinds, newer schema refused), round trip, built-ins winning a merge;
  - loadout JSON and wire form;
  - every `SkinResolver` fallback, including opponents;
  - set savings.
- `ForeverAlonePokerTests/Shared/Skins/SkinStoreTests` (fakes in `Support/SkinFakes.swift`): defaults before loading, equip only owned slots, a failed download shows the default, refunds revert, unknown and known opponents, unsupported kinds hidden.
- `IdentityStoreTests`: loadout persistence and newest-wins merge.
- Manual: equip the Spanish ace and a red back, check them at the table and that the opponent's backs stay navy.
