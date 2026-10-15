/// What the player may use, derived from App Store entitlements (the product
/// ids of verified, unrevoked transactions). Never persisted by the app.
public struct Ownership: Hashable, Sendable {
    public var productIDs: Set<String>
    /// Used to render an opponent's loadout: cosmetics are not policed, only
    /// whether this device has the files.
    public var ownsEverything: Bool

    public init(productIDs: Set<String> = [], ownsEverything: Bool = false) {
        self.productIDs = productIDs
        self.ownsEverything = ownsEverything
    }

    public static let none = Ownership()
    public static let everything = Ownership(ownsEverything: true)

    public func owns(_ slot: CosmeticSlot, of item: SkinItem) -> Bool {
        guard item.assets[slot] != nil else { return false }
        if ownsEverything || item.isDefault { return true }
        guard let productID = item.productID else { return true }  // free item
        return productIDs.contains(productID)
    }

    /// Whether every slot of the item is owned (the item was bought).
    public func ownsAll(of item: SkinItem) -> Bool {
        item.slots.allSatisfy { owns($0, of: item) }
    }

    public func ownedSlots(of item: SkinItem) -> [CosmeticSlot] {
        item.slots.filter { owns($0, of: item) }
    }
}

/// One installed file: an item's asset for one slot.
public struct AssetKey: Hashable, Sendable, Codable {
    public let item: SkinID
    public let slot: CosmeticSlot

    public init(item: SkinID, slot: CosmeticSlot) {
        self.item = item
        self.slot = slot
    }
}

/// The asset files present on this device (bundled defaults are implied).
public typealias InstalledAssets = Set<AssetKey>

public extension Set where Element == AssetKey {
    static func all(of item: SkinItem) -> InstalledAssets {
        Set(item.slots.map { AssetKey(item: item.id, slot: $0) })
    }
}
