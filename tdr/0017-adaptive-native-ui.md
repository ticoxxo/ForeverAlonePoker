# 0017. Adapt every screen to its space with a native, senior-friendly design

- **Status:** Accepted
- **Date:** 2026-10-17
- **Feature / area:** `ForeverAlonePoker/Shared/DesignSystem`, `ForeverAlonePoker/Features/Table`, then every feature folder (see Roadmap)

## Context

- The players are mostly **casual poker players and older adults**. They need large text and controls, clear wording, one obvious thing to do at a time, and calm motion.
- The app runs on iPhone, iPad and the **foldable iPhone**, in portrait and landscape. The foldable shows an iPhone-sized screen when folded and a near-square, roughly 4:3 one when open, and it can switch between them while a match is in play. On iPad the app can also be any width in Split View or Stage Manager.
- Before this decision the table was a single `VStack` tuned for an upright phone. Sizes were fixed (a 200 pt opponents area; 88/64/56/30 pt cards), the action bar used small default buttons and a bare slider, and every overlay picked its own black opacity and corner radius.
- We follow Apple's Human Interface Guidelines: tap targets of at least 44 pt, Dynamic Type, Dark Mode, and the Reduce Motion, Reduce Transparency and VoiceOver settings.

## Decision

**Look:** clean and Apple-native. We use SF Pro text styles and SF Symbols, a flat felt gradient, and Liquid Glass panels (`.glassEffect`, `.glassProminent` buttons) over the felt. Colour stays restrained: yellow marks the player who has to act, and red and orange are kept for Fold and Bet/Raise.

**Tokens:** `Shared/DesignSystem/Theme.swift` holds `Theme.Spacing`, `Theme.Radius`, `Theme.Target` (`minimum` 44, `primary` 56) and `Theme.Palette`. It also has `TableFelt` and the `tablePanel()` modifier, which uses glass, or a solid dark fill when Reduce Transparency is on. New UI uses these tokens instead of literal values.

**Layout follows the available space, never the device.** `TableArrangement.make(size:)` (pure, in `Features/Table/TableModels.swift`) reads the container size from a `GeometryReader` and picks one of three arrangements:

| Arrangement | When | Shape |
|---|---|---|
| `.portrait` | short side < 600 and not wide (upright phone, folded foldable, narrow split view) | opponents on top, board, me, actions underneath |
| `.landscape` | short side < 600 and width/height > 1.25 (phone on its side) | table on the left, actions docked in a 280 pt column on the trailing side |
| `.spacious` | short side ≥ 600 (iPad in either orientation, open foldable) | portrait order with bigger cards and an action panel up to 640 pt wide |

The arrangement also gives card heights (`cardHeights(in:)`, scaled from the short side and clamped to 44…120 pt for the board) and the height of the opponents area (`opponentsHeight(in:)`). Seat views take card heights as parameters instead of using literals. A change of arrangement animates with `.smooth`, or snaps under Reduce Motion, so folding or rotating the device mid-hand doesn't jolt the table.

**Interaction rules for the table:**
- Main actions are at least 56 pt tall and labelled in plain words with the amount ("Call 40", "Raise to 120", "All in").
- Bet sizing shows the amount in large digits and adds − / + step buttons (`TableActionModel.sizingStep`, `stepped(_:by:)`) next to the slider.
- A light haptic plays when it becomes the player's turn.
- Whoever is acting gets a ring **and** an hourglass symbol, so colour is never the only signal.

## Roadmap

| Phase | Scope | State |
|---|---|---|
| 1 | Tokens, `TableArrangement`, adaptive `TableView`, redesigned `ActionBar`, seat views sized by arrangement | done in this record's PR |
| 2 | Seats and board polish: chip and pot animations, hand-result banner, dealer button, Reduce Motion pass | planned |
| 3 | Home as a "Play" hub with large Quick play / Nearby / Online cards; `NavigationSplitView` on regular width (iPad, open foldable) | planned |
| 4 | Local and online lobbies, Profile, Card store and Leaderboard moved onto the shared tokens; room code and passcode shown large | planned |
| 5 | First-run "How to play" and a hand-rankings sheet reachable from the table; accessibility audit (VoiceOver order, accessibility text sizes); UI tests per arrangement | planned |

Every later phase that changes a decision here supersedes this record or adds a dated note to it.

## Consequences

- Rotation, Split View, Stage Manager and the foldable's fold and unfold all go through the same rule, and the rule can be unit-tested without a simulator.
- Views must not hard-code card sizes or check `UIDevice` / the device idiom for layout.
- Liquid Glass needs the iOS 26+ SDK. Our deployment target (iOS 27) already requires it.
- The opponent ring still uses `SeatLayout`'s top arc in every arrangement. A full oval for `.spacious` is follow-up work for phase 2.

## Alternatives considered

- **Branch on device idiom or model.** Rejected: it gets an iPad in Split View and the foldable's live resize wrong, and it can't be tested from a size.
- **`ViewThatFits` only.** Rejected: it picks the first view that fits but can't share card sizing and seat geometry between arrangements, or explain why it chose one.
- **Classic casino skeuomorphism (wood rail, gold, 3D chips).** Considered for the audience but not chosen: the owner preferred the native look, and cards keep their own look through skins (tdr/0011).

## Test strategy

- `ForeverAlonePokerTests/Features/Table/TableArrangementTests.swift` covers which arrangement each size gets (phone portrait and landscape, iPad, open foldable, narrow split view, empty size), card-height ordering and clamps, the opponents-area share, and where the actions dock.
- `TableModelsTests.swift` › `TableActionModel` covers the − / + step size and clamping.
- Manual checks: open the Practice table on an iPhone 17 simulator and rotate it; on an iPad simulator use full screen, Split View at ⅓ and ½, and a Stage Manager resize; use a foldable simulator when available. Then turn on the largest accessibility text size, Reduce Motion and Reduce Transparency, and do a VoiceOver pass over the action panel.

## Notes

- **2026-10-19:** The deployment target is iOS 17, not 27, so Liquid Glass is gated by availability with material fallbacks. Landscape now docks a slim control rail, seats sit inline in short windows, opponents are placed by `SeatArcLayout`, and the Min button is gone. Phase 2's motion and Reduce Motion pass and phase 3's home tiles are done. Phase 5's UI tests are deliberately not written for now. See tdr/0018.
- **2026-10-19:** Where the actions sit is now decided by size classes, not by `TableArrangement` (tdr/0019). `docksActionsAtSide` and the trailing action column no longer drive any view.
