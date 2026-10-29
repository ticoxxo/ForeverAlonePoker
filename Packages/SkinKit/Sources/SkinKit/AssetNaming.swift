import Foundation
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

    /// Chip artwork: `chip_<color>_<flat|top>[_large]` for the classic set and
    /// `premium_<nn>_chip_<color>_<flat|top>[ copy]` for a premium set, whose
    /// "copy" files are the large ones. The color picks the denomination
    /// (`ChipDenomination.color`); unknown colors are ignored.
    public static func parseChip(fileStem: String) -> (item: SkinID, slot: CosmeticSlot)? {
        var stem = fileStem
        var size = ChipSize.small
        for suffix in ["_large", " copy"] where stem.hasSuffix(suffix) {
            stem = String(stem.dropLast(suffix.count))
            size = .large
        }
        let parts = stem.split(separator: "_").map(String.init)
        let item: SkinID
        let rest: ArraySlice<String>
        if parts.count == 5, parts[0] == "premium", parts[2] == "chip" {
            item = SkinID("premium_\(parts[1])_chips")
            rest = parts[3...]
        } else if parts.count == 3, parts[0] == "chip" {
            item = SkinCatalog.defaultChipsID
            rest = parts[1...]
        } else {
            return nil
        }
        guard let denomination = ChipDenomination.color(rest[rest.startIndex]),
              let face = ChipFace(rawValue: rest[rest.startIndex + 1]) else { return nil }
        return (item, .chip(denomination, face: face, size: size))
    }

    /// The published file for a slot inside an item's folder, e.g. "front.Ts.png".
    public static func fileName(for slot: CosmeticSlot) -> String { "\(slot.rawValue).png" }

    /// The image set a bundled default uses in the app's asset catalog, e.g.
    /// "skin-navy_check-back" or "skin-classic_chips-chips-100-top-small".
    public static func bundledImageName(item: SkinID, slot: CosmeticSlot) -> String {
        "skin-\(item.rawValue)-\(slot.rawValue.replacingOccurrences(of: ".", with: "-"))"
    }

    private static func rank(_ token: String) -> Rank? {
        if token == "10" { return .ten }
        guard token.count == 1, let character = token.first, character != "T" else { return nil }
        return Rank(symbol: character)
    }
}
