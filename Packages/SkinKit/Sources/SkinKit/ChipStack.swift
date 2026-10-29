/// A pile of chips of one denomination, drawn next to an amount (tdr/0028).
/// Only a picture: the number beside it is the truth, so the piles round
/// the amount and never need to add up to it.
public struct ChipStack: Hashable, Sendable {
    public let denomination: ChipDenomination
    public let count: Int

    public init(denomination: ChipDenomination, count: Int) {
        self.denomination = denomination
        self.count = count
    }

    /// The piles an amount is drawn with: the fewest chips that make it up,
    /// keeping only the `maxStacks` biggest denominations and at most
    /// `maxChips` chips per pile. An amount below the smallest chip shows
    /// one smallest chip.
    public static func stacks(for amount: Int, maxStacks: Int = 3, maxChips: Int = 5) -> [ChipStack] {
        var remaining = amount
        var stacks: [ChipStack] = []
        for denomination in ChipDenomination.all.reversed() where stacks.count < maxStacks {
            let count = remaining / denomination.value
            guard count > 0 else { continue }
            remaining -= count * denomination.value
            stacks.append(ChipStack(denomination: denomination, count: min(count, maxChips)))
        }
        return stacks.isEmpty ? [ChipStack(denomination: ChipDenomination.all[0], count: 1)] : stacks
    }
}
