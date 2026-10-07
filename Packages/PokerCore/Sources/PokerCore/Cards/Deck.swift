public enum DeckError: Error, Equatable, Sendable {
    case notEnoughCards(requested: Int, available: Int)
}

/// An ordered stack of cards. Dealing always takes from the front, so a deck
/// built from an explicit card list is a "rigged" deck whose outcome is fully
/// known. That is how tests and replays control every hand.
public struct Deck: Hashable, Sendable, Codable {
    public private(set) var cards: [Card]

    /// A full 52-card deck in canonical (unshuffled) order.
    public init() {
        cards = Suit.allCases.flatMap { suit in
            Rank.allCases.map { Card(rank: $0, suit: suit) }
        }
    }

    /// A deck with exactly these cards in this order (first card dealt first).
    public init(cards: [Card]) {
        self.cards = cards
    }

    public var count: Int { cards.count }
    public var isEmpty: Bool { cards.isEmpty }

    /// Fisher-Yates via the standard library; injecting the generator keeps the
    /// engine deterministic when a seeded generator is supplied.
    public mutating func shuffle<G: RandomNumberGenerator>(using generator: inout G) {
        cards.shuffle(using: &generator)
    }

    /// A full deck shuffled with the given generator.
    public static func shuffled<G: RandomNumberGenerator>(using generator: inout G) -> Deck {
        var deck = Deck()
        deck.shuffle(using: &generator)
        return deck
    }

    /// A full deck shuffled with the system generator.
    public static func shuffled() -> Deck {
        var generator = SystemRandomNumberGenerator()
        return shuffled(using: &generator)
    }

    public mutating func deal() throws -> Card {
        try deal(1)[0]
    }

    public mutating func deal(_ count: Int) throws -> [Card] {
        guard count <= cards.count else {
            throw DeckError.notEnoughCards(requested: count, available: cards.count)
        }
        let dealt = Array(cards.prefix(count))
        cards.removeFirst(count)
        return dealt
    }
}
