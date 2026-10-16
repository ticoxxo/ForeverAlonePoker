import SkinKit

/// Builds catalogs for tests: `SkinCatalogBuilder().with(.cardSet("x")).build()`.
public struct SkinCatalogBuilder {
    private var items: [SkinItem] = []
    private var catalogVersion = 1
    private var assetBaseURL = "/skins/"

    public init() {}

    public func with(_ item: SkinItem) -> SkinCatalogBuilder {
        var copy = self
        copy.items.append(item)
        return copy
    }

    public func version(_ version: Int) -> SkinCatalogBuilder {
        var copy = self
        copy.catalogVersion = version
        return copy
    }

    public func assetBase(_ base: String) -> SkinCatalogBuilder {
        var copy = self
        copy.assetBaseURL = base
        return copy
    }

    public func build() -> SkinCatalog {
        SkinCatalog(catalogVersion: catalogVersion, assetBaseURL: assetBaseURL, items: items)
    }

    /// A paid 52-card front set with placeholder hashes.
    public static func cardSet(_ id: SkinID, productID: String? = nil) -> SkinItem {
        SkinItem(
            id: id,
            kind: .cardFront,
            names: ["en": id.rawValue],
            productID: productID ?? ProductIDs.set(id),
            assets: Dictionary(uniqueKeysWithValues: CosmeticSlot.allCardFronts.map { ($0, asset(id, $0)) })
        )
    }

    /// A paid card back.
    public static func back(_ id: SkinID, productID: String? = nil) -> SkinItem {
        SkinItem(
            id: id,
            kind: .cardBack,
            names: ["en": id.rawValue],
            productID: productID ?? ProductIDs.single(id),
            assets: [.cardBack: asset(id, .cardBack)]
        )
    }

    public static func asset(_ id: SkinID, _ slot: CosmeticSlot, sha256: String = "00", bytes: Int = 1) -> AssetRef {
        AssetRef(path: "\(id)/\(AssetNaming.fileName(for: slot))", sha256: sha256, bytes: bytes)
    }
}

/// Builds loadouts: `LoadoutBuilder().equip("x", on: [.cardBack]).build()`.
public struct LoadoutBuilder {
    private var loadout = Loadout()

    public init() {}

    public func equip(_ item: SkinID, on slots: [CosmeticSlot]) -> LoadoutBuilder {
        var copy = self
        copy.loadout.equip(item, on: slots)
        return copy
    }

    public func build() -> Loadout { loadout }
}
