# 0018. Animate the table, gate Liquid Glass by availability, and make every screen fit and speak

- **Status:** Accepted
- **Date:** 2026-10-19
- **Feature / area:** `ForeverAlonePoker/Shared/DesignSystem`, `ForeverAlonePoker/Features/Table`, `Features/Home`, `Features/LocalMatch`, `Features/OnlineMatch`, `Features/SkinStore`, `Features/Leaderboard`, `Features/Profile`, `Shared/Skins/SkinStore.swift`

## Context

- tdr/0017 phase 1 made the table follow its space, but on devices it still clipped. On an upright iPhone the table and action panel together were taller than the screen, so the buttons were cut off. On a phone on its side the action panel and my own seat ran off the bottom. At a bigger table the top opponent was centred on its arc point, so half of it reached into the navigation bar.
- Dealt cards looked choppy. The first deal effect flipped each card by rebuilding it, and swapping in a skin image on every animation frame, over a 0.45 s spring with a 0.12 s stagger.
- The Min button duplicated the − stepper.
- The deployment target is **iOS 17** (commit "Min deployment target lowered to 17"; both packages also declare `.iOS(.v17)`). Liquid Glass (`glassEffect`, `.glass`, `.glassProminent`, `GlassEffectContainer`) exists only on iOS 26 and later. tdr/0017 assumed iOS 27.
- Our players are mostly casual and older (tdr/0017). VoiceOver read cards as notation ("Td"), seat plates as loose fragments, and gave no cue when it became the player's turn.
- The first request also asked for animations when buying something. Purchases completed silently.

## Decision

**Glass where available.** Every glass call goes through `Theme.swift`. `tableGlass(in:)` and `surfaceGlass(in:)` use a solid fill under Reduce Transparency, Liquid Glass on iOS 26 and later, and a material before that. `glassButtonStyle(_:)` picks `.glass` / `.glassProminent`, or `.bordered` / `.borderedProminent` before iOS 26. `GlassGroup` wraps `GlassEffectContainer` only where it exists. Views never call the glass APIs directly.

**Short windows fit without clipping.**
- `TableArrangement.cardHeights(in:)` is also capped by the window height.
- Seats in portrait and landscape put their cards beside the name plate (`seatsInline`). In landscape my own seat does too, and shares a row with the status banner (`mySeatInline`).
- In landscape the pot sits beside the board.
- `SeatArcLayout`, a custom `Layout`, places opponents on `SeatLayout`'s arc and nudges each seat inward until it fits, so none crosses the navigation bar or the window edge.
- The table area scrolls only when it truly cannot fit, which happens at accessibility text sizes. It never clips.

**Landscape control rail.** On a phone on its side the action panel becomes a slim rail on the trailing edge, like the foldable's side toolbar. `actionDockWidth` is about a quarter of the width, 200 to 280 pt, or wider at accessibility sizes. The rail has the amount with All in beside it, the − / slider / + row, Fold and Check/Call side by side, and Bet/Raise below, all 44 pt tall. It scrolls if the window is shorter still, anchored at the bottom near the thumb.

**Action panel.** The Min button is removed. All in sits beside the amount. Buttons use the regular control size with labels at least 56 pt tall under the table, on one line that shrinks a little, so "Raise to 1,480" never wraps the panel off screen. At accessibility sizes the buttons stack and allow two lines. Table and panel share one `AnyLayout`, so folding or rotating mid-hand keeps a half-chosen raise amount.

**Toolbars per the HIG.**
- The emote picker is a navigation-bar item, because it is a secondary action.
- The card store's Restore is a navigation-bar button.
- Home puts the profile avatar in the navigation bar.
- The table forces a dark navigation bar so the title stays readable on the felt.

**Motion.** Named animations live in `Theme.Motion`, and `motion(_:value:)` stands still under Reduce Motion.
- A dealt card (`AnyTransition.dealt(from:)`) changes only offset, tilt, rotation, scale and opacity. The renderer interpolates these without rebuilding the card, so the deal runs at the display's full frame rate. The spring lasts 0.35 s with little bounce, and `DealTiming` staggers cards 0.09 s apart.
- The dealer button glides between seats through a shared `matchedGeometryEffect` namespace.
- Bets pop in, chip counts roll with `numericText`, and the status banner swaps with a blur.
- A won pot plays a success haptic and a trophy bounce.
- A completed purchase raises `SkinStore.lastUnlock`. The store shows `UnlockCelebration`: the cards fan out under a glass panel, with a success haptic and a VoiceOver announcement. It dismisses itself after 4 s or with Done.

**Accessibility.**
- Cards are read in words through `Card.spokenName` and `[Card].spokenList`.
- Name plates, board, pot, bets, lobby rows and leaderboard rows each read as one phrase.
- The table orders VoiceOver as status, my cards, board, then the rest.
- "Your turn" and match results are announced with high priority. The connection-lost card is modal.
- Emojis have spoken names.
- Sizes that should follow the text use `@ScaledMetric`, capped where a picture would otherwise crowd the table.
- Every control is at least 44 pt, and main actions are 56 pt (`PrimaryActionButton`).

**Home** is a grid of large tiles in adaptive columns, one on a folded phone and two or three on an open foldable or iPad, all inside one `NavigationStack`.

## Consequences

- The app runs on iOS 17 to 25 with materials and bordered buttons, and on iOS 26 and later with Liquid Glass, from one code path.
- A view that calls `glassEffect` or `.buttonStyle(.glass…)` directly breaks the iOS 17 build. Use the `Theme` helpers.
- Phone landscape and upright phones no longer clip. Accessibility text sizes scroll the table area instead.
- The deal no longer flips cards face down. A flip would need either a per-frame view swap, which is what made it choppy, or a separate back layer for each card.
- This record supersedes tdr/0017's statement that the deployment target already requires Liquid Glass.

## Alternatives considered

- **A split-view home (`NavigationSplitView`) on wide windows.** Rejected: collapsing and expanding on fold can rebuild the detail column, which would end a live match through the match views' `onDisappear`.
- **Raising the deployment target to iOS 26 or 27 to use glass everywhere.** Rejected: the owner lowered it to 17 on purpose.
- **Scaling the whole table down to fit (`scaleEffect`).** Rejected: it shrinks text below the chosen Dynamic Type size.
- **Choosing between full and compact tables with `ViewThatFits`.** Rejected: switching rebuilds seat views and replays deal transitions on every resize.

## Test strategy

- `ForeverAlonePokerTests/Features/Table/TableMotionTests.swift` covers `DealTiming` staggering and Reduce Motion, the rail width and button stacking, and spoken card names.
- `ForeverAlonePokerTests/Shared/Skins/SkinStoreTests.swift` covers that only a completed purchase raises `lastUnlock` and that acknowledging it clears it.
- `TableArrangementTests.swift` still covers arrangement choice, card-height ordering and clamps.
- **No new UI tests (XCUITest) for this work, by decision.** The owner asked to skip UI tests to save effort. They are slow and need a simulator for every arrangement. Glass, motion and layout are verified by eye instead: SwiftUI previews (the table previews in portrait and landscape, the action panel's three previews) and a manual pass on devices. tdr/0017 phase 5 still lists per-arrangement UI tests as future work.
- Manual checks: iPhone portrait and landscape at 2, 3 and 6 players, the largest accessibility text size, and Reduce Motion and Reduce Transparency on and off. Also a VoiceOver pass over the table, the store purchase flow, and an iOS 17 simulator for the fallbacks.
