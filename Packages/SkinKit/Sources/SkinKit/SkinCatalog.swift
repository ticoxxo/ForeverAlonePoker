import Foundation

/// Everything the store can show, as published by the catalog server
/// (`GET /store/catalog`, tdr/0012). Adding a set, a back or a sale badge is a
/// new catalog, never an app update.
public struct SkinCatalog: Codable, Hashable, Sendable {
    /// The manifest shape this build understands. Bumped only for breaking changes;
    /// additive fields and kinds never bump it.
    public static let currentSchemaVersion = 1

    public enum DecodingFailure: Error, Equatable {
        case unsupportedSchema(Int)
    }

    public let schemaVersion: Int
    /// Increases with every publish; useful for logs and cache keys.
    public let catalogVersion: Int
    /// ISO 8601 publish time, informational.
    public let publishedAt: String?
    /// Base for every `AssetRef.path`: absolute ("https://cdn…/skins/") or
    /// relative to the catalog URL ("/skins/").
    public let assetBaseURL: String
    public let items: [SkinItem]

    public init(
        schemaVersion: Int = SkinCatalog.currentSchemaVersion,
        catalogVersion: Int,
        publishedAt: String? = nil,
        assetBaseURL: String,
        items: [SkinItem]
    ) {
        self.schemaVersion = schemaVersion
        self.catalogVersion = catalogVersion
        self.publishedAt = publishedAt
        self.assetBaseURL = assetBaseURL
        self.items = items
    }

    public func item(_ id: SkinID) -> SkinItem? {
        items.first { $0.id == id }
    }

    public func items(of kind: CosmeticKind) -> [SkinItem] {
        items.filter { $0.kind == kind }
    }

    /// The items this build can render and is new enough for.
    public func available(kinds: Set<CosmeticKind>, appVersion: AppVersion) -> SkinCatalog {
        replacingItems(items.filter { item in
            kinds.contains(item.kind) && (item.minAppVersion.map { $0 <= appVersion } ?? true)
        })
    }

    /// Adds `other`'s items after this catalog's; items with an id already
    /// present here are ignored, so bundled defaults can never be replaced
    /// remotely. Versions and the asset base come from `other`.
    public func merging(_ other: SkinCatalog) -> SkinCatalog {
        let known = Set(items.map(\.id))
        return SkinCatalog(
            schemaVersion: other.schemaVersion,
            catalogVersion: other.catalogVersion,
            publishedAt: other.publishedAt,
            assetBaseURL: other.assetBaseURL,
            items: items + other.items.filter { !known.contains($0.id) }
        )
    }

    private func replacingItems(_ newItems: [SkinItem]) -> SkinCatalog {
        SkinCatalog(
            schemaVersion: schemaVersion,
            catalogVersion: catalogVersion,
            publishedAt: publishedAt,
            assetBaseURL: assetBaseURL,
            items: newItems
        )
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, catalogVersion, publishedAt, assetBaseURL, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw DecodingFailure.unsupportedSchema(schemaVersion)
        }
        catalogVersion = try container.decode(Int.self, forKey: .catalogVersion)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        assetBaseURL = try container.decode(String.self, forKey: .assetBaseURL)
        // One malformed item must not take the whole store down.
        items = try container.decode([Lossy<SkinItem>].self, forKey: .items).compactMap(\.value)
    }

    public static func decode(from data: Data) throws -> SkinCatalog {
        try JSONDecoder().decode(SkinCatalog.self, from: data)
    }

    /// Stable JSON (sorted keys) so the same catalog always hashes and signs the same.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// Decodes a value, or `nil` when that element is malformed.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Built-in defaults

public extension SkinCatalog {
    static let defaultFrontID: SkinID = "default"
    static let defaultBackID: SkinID = "navy_check"
    static let defaultChipsID: SkinID = "classic_chips"

    /// The free skins bundled in the app binary. They are always installed and
    /// are what every slot falls back to (tdr/0011).
    static let builtIn = SkinCatalog(
        catalogVersion: 0,
        assetBaseURL: "",
        items: [
            SkinItem(
                id: defaultFrontID,
                kind: .cardFront,
                names: ["en": "Classic", "es": "Clásica"],
                assets: Dictionary(uniqueKeysWithValues: CosmeticSlot.allCardFronts.map {
                    ($0, AssetRef(path: AssetNaming.fileName(for: $0), sha256: "", bytes: 0))
                }),
                isDefault: true
            ),
            SkinItem(
                id: defaultBackID,
                kind: .cardBack,
                names: ["en": "Navy check", "es": "Cuadros azul marino"],
                assets: [.cardBack: AssetRef(path: AssetNaming.fileName(for: .cardBack), sha256: "", bytes: 0)],
                isDefault: true
            ),
            SkinItem(
                id: defaultChipsID,
                kind: .chips,
                names: ["en": "Classic chips", "es": "Fichas clásicas"],
                assets: Dictionary(uniqueKeysWithValues: CosmeticSlot.allChips.map {
                    ($0, AssetRef(path: AssetNaming.fileName(for: $0), sha256: "", bytes: 0))
                }),
                isDefault: true
            ),
        ] + bundledAvatars
    )

    /// Profile pictures shipped in the app (tdr/0030): free ones, and premium
    /// ones sold one by one. Every opponent can draw every one of them, so
    /// even premium pictures are bundled rather than downloaded.
    private static let bundledAvatars: [SkinItem] = [
        ("avatar_dwarf", "Dwarf", "Enano", false),
        ("avatar_goblin", "Goblin", "Duende", false),
        ("avatar_eyepatch_bear", "Eyepatch bear", "Oso con parche", false),
        ("avatar_seal", "Seal", "Foca", false),
        ("avatar_dino", "Dino", "Dino", false),
        ("avatar_rabbit", "Rabbit", "Conejo", false),
        ("avatar_pig", "Pig", "Cerdo", false),
        ("avatar_scarred_pup", "Scarred pup", "Cachorro con cicatriz", false),
        ("avatar_yellow_cat", "Yellow cat", "Gato amarillo", true),
        ("avatar_zombie_cat", "Zombie cat", "Gato zombi", true),
        ("avatar_stitched_cat", "Stitched cat", "Gato cosido", true),
        ("avatar_cigs", "Cigarettes", "Cigarros", true),
        ("avatar_wine", "Wine", "Vino", true),
        ("avatar_girl", "Girl", "Chica", true),
    ].map { id, english, spanish, isPremium in
        let id = SkinID(rawValue: id)
        return SkinItem(
            id: id,
            kind: .avatar,
            names: ["en": english, "es": spanish],
            productID: isPremium ? ProductIDs.single(id) : nil,
            assets: [.avatar: AssetRef(path: AssetNaming.fileName(for: .avatar), sha256: "", bytes: 0)],
            isBundled: true
        )
    }
}
