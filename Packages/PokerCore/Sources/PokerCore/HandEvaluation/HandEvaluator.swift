/// Evaluates the best five-card poker hand from five to seven cards.
///
/// Seven-card evaluation enumerates the 21 five-card combinations and keeps
/// the strongest. That is trivially correct and fast enough for a heads-up
/// game where at most two hands are evaluated per showdown.
public enum HandEvaluator {
    /// - Precondition: `cards` holds between 5 and 7 distinct cards.
    public static func evaluate(_ cards: [Card]) -> HandRank {
        precondition((5...7).contains(cards.count), "HandEvaluator needs 5 to 7 cards, got \(cards.count)")
        if cards.count == 5 {
            return evaluateFive(cards)
        }
        var best: HandRank?
        for combination in combinations(of: cards, choosing: 5) {
            let rank = evaluateFive(combination)
            if best == nil || rank > best! {
                best = rank
            }
        }
        return best!
    }

    // MARK: - Five-card evaluation

    private static func evaluateFive(_ hand: [Card]) -> HandRank {
        let sorted = hand.sorted { $0.rank > $1.rank }
        let isFlush = Set(hand.map(\.suit)).count == 1
        let straightHigh = straightHighRank(sorted.map(\.rank))

        if let high = straightHigh {
            let ordered = orderStraight(sorted, high: high)
            return HandRank(
                category: isFlush ? .straightFlush : .straight,
                tiebreakers: [high],
                bestFive: ordered
            )
        }

        // Group by rank: larger groups first, then higher rank first.
        let groups = Dictionary(grouping: sorted, by: \.rank)
            .map { (rank: $0.key, cards: $0.value) }
            .sorted { lhs, rhs in
                if lhs.cards.count != rhs.cards.count { return lhs.cards.count > rhs.cards.count }
                return lhs.rank > rhs.rank
            }
        let shape = groups.map(\.cards.count)
        let tiebreakers = groups.map(\.rank)
        let ordered = groups.flatMap(\.cards)

        let category: HandCategory
        switch shape {
        case [4, 1]: category = .fourOfAKind
        case [3, 2]: category = .fullHouse
        case [3, 1, 1]: category = .threeOfAKind
        case [2, 2, 1]: category = .twoPair
        case [2, 1, 1, 1]: category = .onePair
        default: category = isFlush ? .flush : .highCard
        }
        return HandRank(category: category, tiebreakers: tiebreakers, bestFive: ordered)
    }

    /// Returns the high rank of a straight, or `nil`. `ranks` must be sorted
    /// descending. The wheel (A 5 4 3 2) counts as a five-high straight.
    private static func straightHighRank(_ ranks: [Rank]) -> Rank? {
        let values = ranks.map(\.rawValue)
        guard Set(values).count == 5 else { return nil }
        if values[0] - values[4] == 4 {
            return ranks[0]
        }
        if values == [14, 5, 4, 3, 2] {
            return .five
        }
        return nil
    }

    /// Puts the straight's cards in rank order with the high card first; for
    /// the wheel the ace moves to the end since it plays low.
    private static func orderStraight(_ sortedDescending: [Card], high: Rank) -> [Card] {
        guard high == .five, let ace = sortedDescending.first, ace.rank == .ace else {
            return sortedDescending
        }
        return Array(sortedDescending.dropFirst()) + [ace]
    }

    // MARK: - Combinations

    private static func combinations(of cards: [Card], choosing k: Int) -> [[Card]] {
        var result: [[Card]] = []
        var current: [Card] = []
        func recurse(_ start: Int) {
            if current.count == k {
                result.append(current)
                return
            }
            guard start < cards.count else { return }
            for index in start..<cards.count {
                current.append(cards[index])
                recurse(index + 1)
                current.removeLast()
            }
        }
        recurse(0)
        return result
    }
}
