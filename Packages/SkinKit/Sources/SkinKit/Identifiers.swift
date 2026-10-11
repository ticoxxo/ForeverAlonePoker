/// Identifies one skin item in the catalog, e.g. "spanish_001" or "red_check".
/// A plain string on the wire so the catalog can grow without app updates.
public struct SkinID: RawRepresentable, Hashable, Comparable, Sendable, Codable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: SkinID, rhs: SkinID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }
}

/// What a skin decorates. Open on purpose (not an enum): a catalog may list
/// kinds a given app build cannot render yet, and that build simply does not
/// offer them (`SkinCatalog.available(kinds:appVersion:)`).
public struct CosmeticKind: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public static let cardFront = CosmeticKind(rawValue: "cardFront")
    public static let cardBack = CosmeticKind(rawValue: "cardBack")
    public static let mat = CosmeticKind(rawValue: "mat")
    public static let chips = CosmeticKind(rawValue: "chips")

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}
