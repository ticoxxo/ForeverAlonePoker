import PokerCore

/// One place on screen a skin can fill: the face of a specific card, the card
/// back, and later the mat or a chip denomination. The raw value is a stable
/// key ("front.As", "back", "mat", "chips.100") used in loadouts, manifests
/// and on the wire.
public struct CosmeticSlot: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    private static let frontPrefix = "front."

    public static func cardFront(_ card: Card) -> CosmeticSlot {
        CosmeticSlot(rawValue: frontPrefix + card.notation)
    }

    public static let cardBack = CosmeticSlot(rawValue: "back")
    public static let mat = CosmeticSlot(rawValue: "mat")

    /// The 52 card faces, suit by suit.
    public static let allCardFronts: [CosmeticSlot] = Suit.allCases.flatMap { suit in
        Rank.allCases.map { cardFront(Card(rank: $0, suit: suit)) }
    }

    public var kind: CosmeticKind {
        if rawValue.hasPrefix(Self.frontPrefix) { return .cardFront }
        if self == .cardBack { return .cardBack }
        let head = rawValue.split(separator: ".", maxSplits: 1).first.map(String.init) ?? rawValue
        return CosmeticKind(rawValue: head)
    }

    /// The card a front slot shows; `nil` for every other slot.
    public var card: Card? {
        guard rawValue.hasPrefix(Self.frontPrefix) else { return nil }
        return Card(String(rawValue.dropFirst(Self.frontPrefix.count)))
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: CosmeticSlot, rhs: CosmeticSlot) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }
}
