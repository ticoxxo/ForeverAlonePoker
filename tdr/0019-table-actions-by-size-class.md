# 0019. Place the table's actions by size class: a panel when regular, the bottom toolbar otherwise

- **Status:** Accepted
- **Date:** 2026-10-19
- **Feature / area:** `ForeverAlonePoker/Features/Table` (`TableView`, `ActionBar`, `TableModels`)

## Context

- Apple's Human Interface Guidelines (Layout › Size classes) say to decide layout from size classes, not the device or its orientation, and to consider every combination of compact and regular width and height.
- The HIG on toolbars says to put the actions that support the main task in the toolbar, with one prominent action on the trailing side, and to keep text-labelled actions apart.
- Before this record the `ActionBar` panel was always on screen. tdr/0018 put it under the table, or docked it as a slim rail on the trailing edge in phone landscape (`TableArrangement.docksActionsAtSide`, `actionDockWidth`). Table and panel shared one `AnyLayout` so a half-chosen raise survived rotation.
- The table used hard-coded padding, and the panel rose into place with a fixed `.offset(y: 24)`.

## Decision

**Placement follows the size classes.** `TableActionPlacement.make(isRegularWidth:isRegularHeight:)` (pure, in `TableModels.swift`) returns `.panel` only when both the horizontal and vertical size classes are regular, and `.toolbar` otherwise. `TableView` reads `horizontalSizeClass` and `verticalSizeClass` from the environment.

| Size classes | Example | Actions |
|---|---|---|
| regular × regular | iPad full screen or ½ split, open foldable | `ActionBar` panel under the table, up to `TableArrangement.actionPanelMaxWidth` wide |
| any compact | upright phone, phone on its side, iPad ⅓ split or Slide Over, folded foldable | bottom toolbar plus `SizingStrip` |

**Toolbar mode.**
- `ToolbarItemGroup(placement: .bottomBar)` holds `FoldActionButton` (leading, red), `PassiveActionButton` (Check, or Call with the amount, in the middle) and `SizedActionButton` (Bet / Raise to with the amount, trailing, the single prominent orange action), separated by spacers so the text labels never run together.
- The bet sizing stays at the bottom of the table in a `SizingStrip`: − / slider / + with All in at the trailing end. The amount reads on the toolbar's Bet / Raise button.
- The toolbar stays for the whole match. Between turns its buttons are disabled with Fold / Check / Bet placeholders, and the strip fades out but keeps its height, so the bottom safe area, and with it the card sizes, never changes from one turn to the next. A light haptic marks the player's turn.
- The emote picker stays in the navigation bar (tdr/0015). Both bars use the dark colour scheme over the felt.

**Shared pieces.** The three buttons are standalone views in `ActionBar.swift`, used by the panel and the toolbar alike. `ActionLabel` hugs its text and is 44 pt tall in the toolbar (`actionLabelIsInToolbar`), and fills the panel at 56 pt elsewhere. `SizingSlider` and `AllInButton` are shared by the panel's `SizingControl` and the strip.

**The raise amount lives in `TableView`** (`raiseAmount`), reset when the legal sizing changes. Swapping panel and toolbar on rotation, resize or fold keeps a half-chosen raise without the shared `AnyLayout`.

**Insets, not offsets.** The panel or strip is attached with `.safeAreaInset(edge: .bottom)`, so the table's `GeometryReader` measures only what is left above it. Side and top gutters use `.safeAreaPadding`. The panel's `.offset` rise is gone; it fades in instead.

## Consequences

- One rule covers rotation, Split View, Stage Manager and the foldable, and it matches the system's own size classes.
- The landscape rail is gone. Phone landscape (compact height) uses the toolbar.
- `TableArrangement` still decides card sizes, inline seats and the opponents area from the container size (tdr/0017). Its rail API (`docksActionsAtSide`, `actionDockWidth`, `stacksActionButtons`) is no longer used by any view. It stays only because the existing tests reference it; see Test strategy.
- `ActionBar` stacks its buttons at accessibility text sizes on its own; it no longer takes an axis.
- The table needs a navigation container for the bottom bar. Every host (`PracticeTableView`, `LocalMatchView`, `OnlineMatchView`) is already inside `HomeView`'s `NavigationStack`.

## Alternatives considered

- **Keep deciding from `TableArrangement` (aspect ratio).** Rejected: the HIG asks for size classes, and the system already reports them for every window shape.
- **Hide the toolbar between turns.** Rejected: the bottom safe area would change on every turn and the cards would resize with it.
- **Put the slider in the toolbar too.** Rejected: a toolbar holds a few distinguishable items (HIG); a slider with steppers and All in would overcrowd it on a phone.
- **Keep the amount in each control's own `@State`.** Rejected: switching between panel and toolbar would reset a half-chosen raise.

## Test strategy

- **No tests were added or changed for this record, by decision.** The owner asked to skip them for now to save effort.
- Follow-up tests to write:
  - `TableActionPlacement`: regular × regular → `.panel`; compact width, compact height, and both compact → `.toolbar` (one behaviour per test, e.g. in `ForeverAlonePokerTests/Features/Table/TableArrangementTests.swift`).
  - Then remove the unused rail API from `TableArrangement` together with its tests: the "docks" test in `TableArrangementTests.swift` and the "TableArrangement action dock" suite in `TableMotionTests.swift`.
- Manual checks: the Practice table on an iPhone in portrait and landscape (toolbar and strip, a raise amount surviving rotation), an iPad full screen (panel), an iPad at ⅓ split and in Slide Over (toolbar), the largest accessibility text size, Reduce Motion, an iOS 17 simulator for the bordered-button fallbacks in the toolbar, and a VoiceOver pass over the toolbar buttons and the strip.
- Previews: `ActionBar.swift` has the panel facing a bet, with no bet, and the sizing strip with the bottom toolbar in landscape.
