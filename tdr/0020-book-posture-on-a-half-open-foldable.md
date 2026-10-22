# 0020. Split the table across the fold of a half-open foldable on its side

- **Status:** Accepted
- **Date:** 2026-10-22
- **Feature / area:** `ForeverAlonePoker/Features/Table`, `ForeverAlonePoker/Shared/DesignSystem/HingeObserver.swift`

## Context

On the iPhone Duo, partially folded and held on its side, the fold runs top to bottom through the middle of the screen, like an open book. The spacious arrangement (tdr/0017) drew the table across the whole width, so my seat, my bet and the action panel sat on the crease. Partially folded and held upright, the fold runs side to side. The bottom half then already holds my hand and the actions, which works well, and the owner asked to keep that case as it is.

iOS 27.1 reports the hinge through UIKit's `UIHingeInteraction` (`UIHinge.Status`: closed, partially open, fully open, plus an angle), and SwiftUI has no equivalent. The hinge does not say which way the fold runs. The deployment target is iOS 17.

## Decision

`View.onHingePartiallyOpenChange(_:)` (`Shared/DesignSystem/HingeObserver.swift`) puts a `UIHingeInteraction` on an invisible `UIViewRepresentable` behind the view and reports whether the status is `.partiallyOpen`. It is gated by `#available(iOS 27.1, *)` and is never called on earlier systems or devices without a hinge, so the default stays "not partially open".

`TableArrangement.isBookPosture(isHingePartiallyOpen:size:)` is true when the hinge is partially open and the window is wider than tall; the shape stands in for the fold's direction. `TableArrangement.make(size:isBookPosture:)` then returns the new `.book` case. `TableView` decides the posture from the whole window size (`onGeometryChange`), not the table's `GeometryReader`, because the book takes the actions out of the bottom safe-area inset and so changes what that reader measures.

`.book` lays the table out as two equal halves, each kept `Theme.Spacing.xLarge` off the fold:

- **Left:** the opponents (heads-up seat or the ring and waiting zone), the board and pot, the status banner and the Elo notice.
- **Right:** my seat (my street bet, my hole cards, my name plate), any rejection notice, and the actions: the action panel, or the sizing strip when the size classes put the buttons in the toolbar (tdr/0019).

Cards are sized from one half of the width (`cardHeights`), seats are stacked rather than inline, and each half scrolls on its own at the largest text sizes.

## Consequences

- A half-open foldable on its side keeps every control off the crease, and the hand plus its actions sit together under one thumb.
- A half-open foldable held upright, a flat-open one, phones and iPads keep their existing arrangements.
- Hinge state is the one input to the arrangement that is not a size. It stays a plain `Bool` in `TableArrangement`, so the model has no UIKit dependency and stays testable.
- A foldable whose hinge runs the other way, wider than tall, would be mistaken for a book. No such device exists today; revisit if one appears.

## Alternatives considered

- **Read the fold from the safe area or display features.** iOS exposes no fold rect to SwiftUI; guessing the middle of the window is what the shape rule already does.
- **Split whenever the window is wide and spacious.** Rejected: a flat-open foldable and an iPad would split for no reason.
- **Split upright too (top/bottom).** Rejected by the owner: the upright half-open layout already works.

## Test strategy

- `ForeverAlonePokerTests/Features/Table/TableArrangementTests.swift`: wide plus half open is a book; tall plus half open is not; fully open is not; `make(size:isBookPosture:)` returns `.book`; book cards fit one half and seats are stacked.
- Manual: on the iPhone Duo simulator (iOS 27.1), open the Practice table, rotate the phone onto its side and fold it partway. The table should split with my hand, bet and actions on the right. Fold it upright and check that nothing changes. Open it flat and check that it returns to the spacious table. Repeat at a large accessibility text size and with the toolbar placement.
