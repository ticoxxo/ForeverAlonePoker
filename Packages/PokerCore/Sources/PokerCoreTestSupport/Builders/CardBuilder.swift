import PokerCore

/// Parses space-separated card notation into cards: `cards("As Kd")`.
/// Crashes on malformed input on purpose: a typo in a fixture is a test bug.
public func cards(_ notation: String) -> [Card] {
    notation.split(separator: " ").map { token in
        guard let card = Card(String(token)) else {
            fatalError("Invalid card notation in test fixture: \(token)")
        }
        return card
    }
}

/// Single-card convenience: `card("As")`.
public func card(_ notation: String) -> Card {
    guard let card = Card(notation) else {
        fatalError("Invalid card notation in test fixture: \(notation)")
    }
    return card
}

public extension Deck {
    /// A deck whose first cards are the given ones, followed by the rest of the
    /// standard deck in canonical order. Lets a test rig the exact cards dealt
    /// while still having 52 cards available.
    static func rigged(_ notation: String) -> Deck {
        rigged(PokerCoreTestSupport.cards(notation))
    }

    static func rigged(_ topCards: [Card]) -> Deck {
        let remaining = Deck().cards.filter { !topCards.contains($0) }
        return Deck(cards: topCards + remaining)
    }
}
