import Foundation
import PokerCore

/// App Store product identifiers, by convention from the item id, so the
/// catalog never has to list 53 ids per set. Product ids are permanent in App
/// Store Connect: never rename an item that has been sold.
public enum ProductIDs {
    public static let prefix = "fap.skin"

    /// The whole card-front set.
    public static func set(_ item: SkinID) -> String { "\(prefix).\(item).set" }

    /// One card of a set, e.g. "fap.skin.spanish_001.card.Ts".
    public static func card(_ item: SkinID, _ card: Card) -> String { "\(prefix).\(item).card.\(card.notation)" }

    /// An item sold as one piece (a card back, later a mat).
    public static func single(_ item: SkinID) -> String { "\(prefix).\(item)" }

    /// Every product that unlocks some part of `item`, whole item first.
    public static func all(for item: SkinItem) -> [String] {
        guard let productID = item.productID else { return [] }
        guard item.sellsSingleCards else { return [productID] }
        return [productID] + item.slots.compactMap { slot in slot.card.map { card(item.id, $0) } }
    }
}

/// Price arithmetic for the store UI. Amounts are App Store prices in the
/// storefront's currency (`Product.price`); this never formats money.
public enum SetPricing {
    /// What buying the whole set saves over buying the missing cards one by
    /// one; zero when the cards would be cheaper.
    public static func savings(setPrice: Decimal, cardPrice: Decimal, cardsRemaining: Int) -> Decimal {
        max(0, cardPrice * Decimal(cardsRemaining) - setPrice)
    }
}
