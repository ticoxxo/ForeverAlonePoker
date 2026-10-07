/// A playing card. Encodes to its two-character notation ("As", "Td") so wire
/// payloads stay compact and test fixtures stay readable.
public struct Card: Hashable, Sendable, CustomStringConvertible {
    public let rank: Rank
    public let suit: Suit

    public init(rank: Rank, suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    /// Parses two-character notation such as "As", "Td" or "2c". Returns `nil`
    /// for anything that is not exactly a rank symbol followed by a suit letter.
    public init?(_ notation: String) {
        let characters = Array(notation)
        guard characters.count == 2,
              let rank = Rank(symbol: characters[0]),
              let suit = Suit(rawValue: String(characters[1]).lowercased())
        else { return nil }
        self.init(rank: rank, suit: suit)
    }

    /// Two-character notation, e.g. "As".
    public var notation: String { rank.symbol + suit.rawValue }

    public var description: String { notation }
}

extension Card: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let notation = try container.decode(String.self)
        guard let card = Card(notation) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid card notation: \(notation)"
            )
        }
        self = card
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(notation)
    }
}
