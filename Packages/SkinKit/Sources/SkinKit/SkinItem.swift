/// One downloadable file of a skin, relative to the catalog's asset base URL.
public struct AssetRef: Codable, Hashable, Sendable {
    public let path: String
    /// Lowercase hex SHA-256 of the file; the app discards files that do not match.
    public let sha256: String
    public let bytes: Int

    public init(path: String, sha256: String, bytes: Int) {
        self.path = path
        self.sha256 = sha256
        self.bytes = bytes
    }
}

/// A sellable skin: a card-front set, a card back, later a mat or chips.
/// A card-front set covers up to 52 front slots and, when `sellsSingleCards`,
/// each of its cards is also sold on its own (`ProductIDs.card`).
///
/// Prices never appear here: App Store Connect owns them (tdr/0012).
public struct SkinItem: Codable, Hashable, Sendable, Identifiable {
    public let id: SkinID
    public let kind: CosmeticKind
    /// Display name by language code ("en", "es"); "en" is the fallback.
    public let names: [String: String]
    /// The App Store product that unlocks the whole item; `nil` means free.
    public let productID: String?
    public let sellsSingleCards: Bool
    public let assets: [CosmeticSlot: AssetRef]
    /// Small image for the store list; defaults to one of the item's assets.
    public let preview: AssetRef?
    /// The oldest app version that can render this item.
    public let minAppVersion: AppVersion?
    /// Bundled in the app, free and always installed. Never downloaded.
    public let isDefault: Bool
    /// Optional marketing label from the catalog ("New", "Sale"). Never a price.
    public let badge: String?

    public init(
        id: SkinID,
        kind: CosmeticKind,
        names: [String: String] = [:],
        productID: String? = nil,
        sellsSingleCards: Bool = false,
        assets: [CosmeticSlot: AssetRef] = [:],
        preview: AssetRef? = nil,
        minAppVersion: AppVersion? = nil,
        isDefault: Bool = false,
        badge: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.names = names
        self.productID = productID
        self.sellsSingleCards = sellsSingleCards
        self.assets = assets
        self.preview = preview
        self.minAppVersion = minAppVersion
        self.isDefault = isDefault
        self.badge = badge
    }

    /// The slots this item can fill, in a stable order.
    public var slots: [CosmeticSlot] { assets.keys.sorted() }

    public func name(for languageCode: String?) -> String {
        if let languageCode, let name = names[languageCode] { return name }
        return names["en"] ?? names.values.sorted().first ?? id.rawValue
    }

    // MARK: Codable (lenient: everything but id and kind is optional)

    private enum CodingKeys: String, CodingKey {
        case id, kind, names, productID, sellsSingleCards, assets, preview, minAppVersion, isDefault, badge
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SkinID.self, forKey: .id)
        kind = try container.decode(CosmeticKind.self, forKey: .kind)
        names = try container.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
        productID = try container.decodeIfPresent(String.self, forKey: .productID)
        sellsSingleCards = try container.decodeIfPresent(Bool.self, forKey: .sellsSingleCards) ?? false
        let rawAssets = try container.decodeIfPresent([String: AssetRef].self, forKey: .assets) ?? [:]
        assets = Dictionary(uniqueKeysWithValues: rawAssets.map { (CosmeticSlot(rawValue: $0.key), $0.value) })
        preview = try container.decodeIfPresent(AssetRef.self, forKey: .preview)
        minAppVersion = try container.decodeIfPresent(AppVersion.self, forKey: .minAppVersion)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        badge = try container.decodeIfPresent(String.self, forKey: .badge)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        if !names.isEmpty { try container.encode(names, forKey: .names) }
        try container.encodeIfPresent(productID, forKey: .productID)
        if sellsSingleCards { try container.encode(true, forKey: .sellsSingleCards) }
        try container.encode(
            Dictionary(uniqueKeysWithValues: assets.map { ($0.key.rawValue, $0.value) }),
            forKey: .assets
        )
        try container.encodeIfPresent(preview, forKey: .preview)
        try container.encodeIfPresent(minAppVersion, forKey: .minAppVersion)
        if isDefault { try container.encode(true, forKey: .isDefault) }
        try container.encodeIfPresent(badge, forKey: .badge)
    }
}
