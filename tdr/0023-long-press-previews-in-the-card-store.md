# 0023. Preview store cards with a long press

- **Status:** Accepted
- **Date:** 2026-10-26
- **Feature / area:** `ForeverAlonePoker/Features/SkinStore`

## Context

Store thumbnails are small (about 56 pt high), so it is hard to judge a card back or a single card face before buying it. The store list shows card backs one per row. Card-face sets show three thumbnails in the list and every card in `SkinSetDetailView`.

## Decision

Holding a card shows it enlarged over the screen until the player taps anywhere. `SkinPreview` (the item plus `.back` or `.face(Card)`) is what gets previewed, and the `skinPreview(_:)` modifier in `Features/SkinStore/SkinPreview.swift` draws it with `SkinStore.previewSkin(for:)`. That means locked cards preview too, and the preview goes through `SkinResolver` like every other card (tdr/0011).

- **Card backs:** long press the row in `SkinStoreView`. The Use / Buy buttons keep their own taps.
- **Card faces:** only inside the set (`SkinSetDetailView`), one card at a time. List rows keep their tap-to-open behaviour and get no preview.

Grid cells in the set use a tap gesture and a long-press gesture instead of a `Button`, because a `Button` fires when a long press lifts too, which would open the card dialog behind the preview. The cells keep the `.isButton` trait and a default accessibility action. Each previewable card also gets a "Preview" accessibility action, and the overlay closes with the escape gesture. The overlay animates through `motion(_:value:)` (Reduce Motion) and plays a haptic when it appears.

## Consequences

- Players can inspect artwork before buying, including cards they don't own yet.
- The overlay covers the scrolling content but not the navigation bar.
- New store surfaces that show cards should reuse `skinPreview(_:)` and not build their own enlargement.

## Alternatives considered

- **`contextMenu(menuItems:preview:)`.** It gives a system preview for free but comes with a menu nobody needs, and it lifts the whole row, not a single card.
- **A sheet.** Heavier than a quick look, and a sheet needs a dismiss affordance.
- **Preview from the face-set row in the list.** Rejected: there, a single press should mean one card, and the row shows three.

## Test strategy

Pure view behaviour with no logic beyond setting state, so it is verified manually and in previews: long press a card back row; open a set and long press locked and owned cards; check that a short tap still opens the card dialog only for owned cards; with VoiceOver, check the "Preview" action and escape-to-close.
