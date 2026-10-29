# 0027. Skin the chips with a bundled classic set and App Store chip sets

- **Status:** Accepted
- **Date:** 2026-10-29
- **Feature / area:** `Packages/SkinKit` (`ChipDenomination`, chip slots, `AssetNaming.parseChip`), `ForeverAlonePoker/Shared/DesignSystem/CardViews.swift` (`ChipView`, `ChipAmountView`), `ForeverAlonePoker/Features/SkinStore`, `Server/Sources/PokerServerCore/Store/CatalogPublisher.swift`, `Server/SkinAssets/premium_01_chips`

## Context

Card fronts and backs are skins (tdr/0011, tdr/0012), and `chips` was reserved as the next kind. Until now every stack, bet and pot showed an SF Symbol. The artist delivered chip artwork:

- 11 colors: white, red, blue, light blue, green, black, purple, yellow, pink, beige (named `biege`) and gray.
- Each color has two views: `top` (seen from above, square) and `flat` (lying in perspective, about 129:59).
- Each view comes at two resolutions: small (about 131 px) and large (about 393 px, three times the small one).
- Names follow two patterns:
  - classic: `chip_<color>_<face>[_large]`;
  - premium: `premium_01_chip_<color>_<face>[ copy]`, where the `copy` file is the large one.
- Files starting with `premium` are to be sold. The rest are the free default.
- The colors carry no values. Any mapping is fine as long as the values are multiples of 10 up to 100,000.

## Decision

1. **Denominations live in SkinKit, not PokerCore.**
   - `ChipDenomination` maps colors to values, ascending: white 10, red 50, blue 100, light blue 250, green 500, black 1,000, purple 5,000, yellow 10,000, pink 25,000, beige 50,000, gray 100,000.
   - The game still counts plain `Chips`. The denomination only decides which picture to draw.
   - `ChipDenomination.showing(amount)` is the largest chip the amount covers, and the 10 chip below that.
2. **One slot per file.**
   - `CosmeticSlot.chip(_:face:size:)` is `chips.<value>.<face>.<size>`, e.g. `chips.100.top.small`.
   - Its kind is `chips` (the head before the first dot, as tdr/0011 planned). Catalogs, loadouts, ownership, downloads and `SkinResolver`'s per-slot fallback therefore work unchanged.
   - `CosmeticSlot.allChips` is 11 × 2 × 2 = 44 slots.
3. **The free set is bundled.** `classic_chips` is in `SkinCatalog.builtIn` with every chip slot. Its files are image sets in `Assets.xcassets/Skins`, named by `AssetNaming.bundledImageName` (`skin-classic_chips-chips-100-top-small`), which the app's `BundledSkin` now also uses. Every chip slot falls back to it.
4. **Premium sets are sold whole.**
   - `premium_01_chips` is one non-consumable, `fap.skin.premium_01_chips.set` ($0.99), served from `Server/SkinAssets/premium_01_chips`.
   - The publisher gives every `chips` item a `.set` product id and previews it with `chips.1000.top.large`.
   - A later premium set (`premium_02_chip_…`) maps to `premium_02_chips` with no code change.
   - "Use" equips the whole set (`equipAll`). A chip a set lacks shows the classic chip.
5. **Artist sizes are kept.** The art already came in two sizes, so the planned resize to 512 / 128 px was dropped: upscaling 393 px to 512 px adds bytes and no detail. Small (≈131 px) is sharp for icons up to about 44 pt at @3x. Large (≈393 px) is for previews and future stacks. `SkinImageCache` downsamples anything over 360 px.
6. **The table shows the top view, small size, for now.**
   - `ChipView(denomination:face:size:)` reads `\.cardSkin`, like the card views.
   - `ChipAmountView` (stack, bet, pot) draws `ChipView(.showing(amount), .top, .small)` at a Dynamic Type–scaled 18 pt.
   - Flat files ship but are not shown yet.
   - Opponents keep `.standard`, so their chips are classic, as their cards are.
7. **Store.**
   - A "Chips" section has a `ChipSetRow` with three fanned chips.
   - A long press shows every chip with its value (`SkinPreview.Subject.chips`).
   - The unlock panel and refund rows draw chips for chip items.
8. **Publishing.** `SkinPublisher import-chips <dir> [skins-dir] [--bundled DIR]` (`CatalogPublisher.importChips`) sends premium files to the skins directory and the classic set to the asset catalog. Then run `SkinPublisher manifest`.

## Consequences

- New premium chip sets, prices and badges need no app update. They need only artwork, an `import-chips` run, a manifest and an App Store Connect product.
- The binary grows by 44 small PNGs (about 0.5 MB).
- The loadout holds up to 44 chip entries when a set is equipped. That is acceptable for a flat JSON dictionary, and it keeps per-slot equipping available.
- **Ops:** create `fap.skin.premium_01_chips.set` in App Store Connect and deploy `Server/SkinAssets`.
- **Follow-up:**
  - draw chip stacks with the flat view;
  - send opponents' loadouts (tdr/0012, decision 6), which will include chips.

## Alternatives considered

- **One slot per denomination with variants inside the asset.** This needs a new `AssetRef` shape and manifest schema version. Slot per file needs neither.
- **Denominations in PokerCore.** The engine has no notion of physical chips, and CORE must not learn about cosmetics (tdr/0011).
- **Selling each chip color.** This is rejected for the same reasons as single cards (tdr/0012, amendment).
- **Resizing to 512 / 128 px.** Rejected because the art already came in two sizes; see decision 5.

## Test strategy

- `Packages/SkinKit/Tests`:
  - chip slot keys and kind, and the `allChips` count;
  - the denomination ladder and `showing`;
  - `parseChip` for classic and premium files, both suffixes, and ignored names;
  - `bundledImageName`;
  - the built-in classic set;
  - the chip product id;
  - every chip fallback in `SkinResolver` (unowned, not installed, a slot the set lacks).
- `Server/Tests/PokerServerTests/StoreTests`: `importChips` routing and the image-set `Contents.json`; the manifest kind, product id and preview for a chips folder.
- `ForeverAlonePokerTests/Shared/Skins/SkinStoreTests` (`SkinStore chips`): bundled default, offered kind, purchase and download, failed download, refund, and unknown opponent.
- Manual, with `StoreKit/SkinStore.storekit`:
  - the classic top chip shows next to stack, bet and pot;
  - buying "Premium chips" replaces it;
  - a refund in the Transaction Manager reverts it;
  - the long-press preview shows all 11 chips.
