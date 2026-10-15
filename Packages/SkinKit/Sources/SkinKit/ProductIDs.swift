/// App Store product identifiers, by convention from the item id. Each item
/// is exactly one non-consumable: card-front sets are sold whole, never card
/// by card (tdr/0012). Product ids are permanent in App Store Connect: never
/// rename an item that has been sold.
public enum ProductIDs {
    public static let prefix = "fap.skin"

    /// The whole card-front set.
    public static func set(_ item: SkinID) -> String { "\(prefix).\(item).set" }

    /// An item sold as one piece (a card back, later a mat).
    public static func single(_ item: SkinID) -> String { "\(prefix).\(item)" }

    /// The product that unlocks `item`; empty for a free item.
    public static func all(for item: SkinItem) -> [String] {
        item.productID.map { [$0] } ?? []
    }
}
