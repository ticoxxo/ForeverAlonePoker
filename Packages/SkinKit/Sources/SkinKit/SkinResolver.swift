/// The skin to draw in one slot, after every fallback rule was applied.
public struct ResolvedSkin: Hashable, Sendable {
    public let item: SkinItem
    public let slot: CosmeticSlot

    public var isDefault: Bool { item.isDefault }
    public var asset: AssetRef? { item.assets[slot] }
}

/// The single place that decides what a slot shows (tdr/0011). A selection is
/// honoured only when its item is in the catalog, has the slot's kind, is
/// owned, and its file is on this device; anything else shows the default.
/// The same rule renders the opponent, with `Ownership.everything`, so an
/// opponent's skin appears only when this device already has its files.
public struct SkinResolver: Sendable {
    public let catalog: SkinCatalog
    private let defaults: [CosmeticKind: SkinItem]

    public init(catalog: SkinCatalog) {
        self.catalog = catalog
        var defaults: [CosmeticKind: SkinItem] = [:]
        for item in catalog.items where item.isDefault && defaults[item.kind] == nil {
            defaults[item.kind] = item
        }
        self.defaults = defaults
    }

    public func defaultItem(for kind: CosmeticKind) -> SkinItem? { defaults[kind] }

    /// `nil` only when the slot's kind has no default at all (e.g. a mat on a
    /// build that has none bundled): there is nothing to draw.
    public func resolve(
        _ slot: CosmeticSlot,
        loadout: Loadout,
        ownership: Ownership,
        installed: InstalledAssets
    ) -> ResolvedSkin? {
        if let selected = loadout[slot],
           let item = catalog.item(selected),
           item.kind == slot.kind,
           ownership.owns(slot, of: item),
           item.isDefault || installed.contains(AssetKey(item: item.id, slot: slot)) {
            return ResolvedSkin(item: item, slot: slot)
        }
        guard let fallback = defaults[slot.kind], fallback.assets[slot] != nil else { return nil }
        return ResolvedSkin(item: fallback, slot: slot)
    }
}
