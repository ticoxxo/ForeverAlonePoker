import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport

@Suite("Cards")
struct CardTests {
    @Test("parses two-character notation")
    func parsesNotation() {
        #expect(Card("As") == Card(rank: .ace, suit: .spades))
        #expect(Card("Td") == Card(rank: .ten, suit: .diamonds))
        #expect(Card("2c") == Card(rank: .two, suit: .clubs))
        #expect(Card("kh") == Card(rank: .king, suit: .hearts), "rank symbol is case-insensitive")
    }

    @Test("rejects malformed notation", arguments: ["", "A", "Asx", "1s", "Ax", "10d"])
    func rejectsMalformed(notation: String) {
        #expect(Card(notation) == nil)
    }

    @Test("round-trips through notation and Codable")
    func roundTrips() throws {
        let original = cards("As Kd 2c Th")
        #expect(original.map(\.notation) == ["As", "Kd", "2c", "Th"])

        let data = try JSONEncoder().encode(original)
        #expect(String(decoding: data, as: UTF8.self) == #"["As","Kd","2c","Th"]"#)
        let decoded = try JSONDecoder().decode([Card].self, from: data)
        #expect(decoded == original)
    }

    @Test("ranks compare in poker order with ace high")
    func rankOrdering() {
        #expect(Rank.two < Rank.three)
        #expect(Rank.ten < Rank.jack)
        #expect(Rank.king < Rank.ace)
        #expect(Rank.allCases.sorted().last == .ace)
    }
}

@Suite("Deck")
struct DeckTests {
    @Test("a fresh deck has 52 unique cards")
    func freshDeck() {
        let deck = Deck()
        #expect(deck.count == 52)
        #expect(Set(deck.cards).count == 52)
    }

    @Test("shuffling with the same seed is reproducible")
    func seededShuffleIsReproducible() {
        var first = SeededRandomNumberGenerator(seed: 42)
        var second = SeededRandomNumberGenerator(seed: 42)
        #expect(Deck.shuffled(using: &first) == Deck.shuffled(using: &second))
    }

    @Test("different seeds produce different orders and keep all cards")
    func differentSeedsDiffer() {
        var first = SeededRandomNumberGenerator(seed: 1)
        var second = SeededRandomNumberGenerator(seed: 2)
        let a = Deck.shuffled(using: &first)
        let b = Deck.shuffled(using: &second)
        #expect(a != b)
        #expect(Set(a.cards) == Set(b.cards))
    }

    @Test("dealing takes from the front and reduces the count")
    func dealing() throws {
        var deck = Deck.rigged("As Kd Qh")
        let hand = try deck.deal(2)
        #expect(hand == cards("As Kd"))
        #expect(try deck.deal() == card("Qh"))
        #expect(deck.count == 49)
    }

    @Test("dealing more cards than available throws")
    func dealingTooMany() {
        var deck = Deck(cards: cards("As"))
        #expect(throws: DeckError.notEnoughCards(requested: 2, available: 1)) {
            try deck.deal(2)
        }
    }

    @Test("a rigged deck still contains every card exactly once")
    func riggedDeckIsComplete() {
        let deck = Deck.rigged("As As Kd")
        #expect(Set(deck.cards).count == 52, "duplicates in the rig must not create duplicate cards")
    }
}
