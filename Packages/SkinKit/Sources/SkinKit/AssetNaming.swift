import PokerCore

/// Maps the artists' file names to slots, and slots to published file names.
///
/// Artist names: `<suit>_<rank>_<item>` for faces (`spades_10_spanish_001`,
/// rank `10` is CORE's `T`) and `back_<item>[_default]` for backs. Jokers are
/// never dealt and are ignored.
public enum AssetNaming {
    private static let suits: [String: Suit] = [
        "clubs": .clubs, "diamonds": .diamonds, "hearts": .hearts, "spades": .spades,
    ]

    public static func parse(fileStem: String) -> (item: SkinID, slot: CosmeticSlot)? {
        if fileStem.hasPrefix("back_") {
            var name = String(fileStem.dropFirst("back_".count))
            if name.hasSuffix("_default") { name = String(name.dropLast("_default".count)) }
            return name.isEmpty ? nil : (SkinID(name), .cardBack)
        }
        let parts = fileStem.split(separator: "_", maxSplits: 2).map(String.init)
        guard parts.count == 3, let suit = suits[parts[0]], let rank = rank(parts[1]) else { return nil }
        return (SkinID(parts[2]), .cardFront(Card(rank: rank, suit: suit)))
    }

    /// The published file for a slot inside an item's folder, e.g. "front.Ts.png".
    public static func fileName(for slot: CosmeticSlot) -> String { "\(slot.rawValue).png" }

    private static func rank(_ token: String) -> Rank? {
        if token == "10" { return .ten }
        guard token.count == 1, let character = token.first, character != "T" else { return nil }
        return Rank(symbol: character)
    }
}
