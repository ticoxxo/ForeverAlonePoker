/// Poker hand categories in ascending strength.
public enum HandCategory: Int, Codable, Sendable, Hashable, Comparable, CaseIterable {
    case highCard = 1
    case onePair
    case twoPair
    case threeOfAKind
    case straight
    case flush
    case fullHouse
    case fourOfAKind
    case straightFlush

    public static func < (lhs: HandCategory, rhs: HandCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .highCard: "High Card"
        case .onePair: "Pair"
        case .twoPair: "Two Pair"
        case .threeOfAKind: "Three of a Kind"
        case .straight: "Straight"
        case .flush: "Flush"
        case .fullHouse: "Full House"
        case .fourOfAKind: "Four of a Kind"
        case .straightFlush: "Straight Flush"
        }
    }
}

/// The strength of a five-card hand. Two hands compare by category first and
/// then by `tiebreakers`, which lists the ranks that matter in order of
/// significance (for example `[pairRank, kicker1, kicker2, kicker3]` for a pair).
/// Hands with equal category and tiebreakers are an exact chop.
public struct HandRank: Hashable, Sendable, Codable, Comparable {
    public let category: HandCategory
    public let tiebreakers: [Rank]
    /// The five cards that make the hand, highest significance first.
    public let bestFive: [Card]

    public init(category: HandCategory, tiebreakers: [Rank], bestFive: [Card]) {
        self.category = category
        self.tiebreakers = tiebreakers
        self.bestFive = bestFive
    }

    public static func < (lhs: HandRank, rhs: HandRank) -> Bool {
        if lhs.category != rhs.category {
            return lhs.category < rhs.category
        }
        return lhs.tiebreakers.lexicographicallyPrecedes(rhs.tiebreakers)
    }

    /// Equality for ranking purposes ignores suits of `bestFive`: a flush in
    /// hearts and a flush in spades with identical ranks are an exact chop.
    public static func == (lhs: HandRank, rhs: HandRank) -> Bool {
        lhs.category == rhs.category && lhs.tiebreakers == rhs.tiebreakers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(category)
        hasher.combine(tiebreakers)
    }
}
