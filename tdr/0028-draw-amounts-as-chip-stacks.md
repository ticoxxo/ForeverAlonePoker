# 0028. Draw chip amounts as up to three stacks of chips

- **Status:** Accepted
- **Date:** 2026-10-29
- **Feature / area:** `Packages/SkinKit` (`ChipStack`), `ForeverAlonePoker/Shared/DesignSystem/CardViews.swift` (`ChipStacksView`, `ChipAmountView`)

## Context

Every stack, bet and pot showed one chip next to its number (tdr/0027, decision 6). The reference artwork (`poker_chips.svg`) shows piles of top-view chips instead: each chip sits a little up and to the left of the one below, and two or three piles of different colors cluster together. tdr/0027 listed chip stacks as a follow-up.

## Decision

1. **The number is the truth; the stacks are a picture.** The piles round the amount and need not add up to it.
2. **`ChipStack.stacks(for:maxStacks:maxChips:)` lives in SkinKit.**
   - It breaks the amount into the fewest chips, largest denomination first.
   - It keeps at most three piles (the three largest denominations used) and at most five chips per pile.
   - An amount below the smallest chip shows one smallest chip.
3. **`ChipStacksView` draws the piles with the top view, small size**, through `ChipView`, so chip skins and fallbacks are unchanged.
   - Each chip rises 16 % of its width and shifts left 60 % of that rise, with a hairline shadow to separate the layers.
   - One, two or three piles use fixed cluster positions; the last pile is in front.
   - The view sizes itself to the cluster's bounds.
4. **`ChipAmountView` uses it as its icon** for stacks, bets, pots and seat summaries, with an 18 pt Dynamic Type–scaled chip.

The flat view still ships unused; the reference uses top views, which read better at this size.

## Consequences

- Amounts take a little more width and height than the single chip did.
- Opponents still draw classic chips (tdr/0027, decision 6).

## Alternatives considered

- **Piles that add up exactly.** Rejected: an exact breakdown needs many piles or tall piles, and the number already gives the exact amount.
- **Flat-view chips stacked vertically.** Rejected for now: the reference uses top views, and flat piles are taller than the seat pills allow.

## Test strategy

- `Packages/SkinKit/Tests/SkinKitTests/ChipStackTests`: the breakdown order, at most three piles, at most five chips per pile, and the smallest chip for small amounts.
- Manual: the practice table shows piles next to the stack, bet and pot.
