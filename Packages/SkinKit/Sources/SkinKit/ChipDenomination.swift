/// The value printed on a chip. Each chip color stands for one denomination
/// (tdr/0027); the game itself only counts `Chips` and never sees these.
public struct ChipDenomination: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let value: Int

    public init(_ value: Int) { self.value = value }

    /// Every denomination a chip set draws, smallest first: one per color of
    /// the artwork, all multiples of 10 from 10 to 100,000.
    public static let all: [ChipDenomination] = colors.map { $0.denomination }

    /// The artist's color names, in ascending value. "biege" is the artist's
    /// spelling; "beige" is accepted too.
    private static let colors: [(name: String, denomination: ChipDenomination)] = [
        ("white", .init(10)),
        ("red", .init(50)),
        ("blue", .init(100)),
        ("lightblue", .init(250)),
        ("green", .init(500)),
        ("black", .init(1_000)),
        ("purple", .init(5_000)),
        ("yellow", .init(10_000)),
        ("pink", .init(25_000)),
        ("biege", .init(50_000)),
        ("gray", .init(100_000)),
    ]

    /// The denomination a chip color stands for; `nil` for colors the set
    /// does not use.
    public static func color(_ name: String) -> ChipDenomination? {
        let name = name.lowercased() == "beige" ? "biege" : name.lowercased()
        return colors.first { $0.name == name }?.denomination
    }

    /// The chip drawn next to an amount: the largest denomination the amount
    /// covers, and the smallest chip for amounts below it.
    public static func showing(_ amount: Int) -> ChipDenomination {
        all.last { $0.value <= amount } ?? all[0]
    }

    public static func < (lhs: ChipDenomination, rhs: ChipDenomination) -> Bool { lhs.value < rhs.value }
    public var description: String { String(value) }
}

/// Which view of a chip a file shows: seen from above, or lying flat in
/// perspective.
public enum ChipFace: String, CaseIterable, Hashable, Sendable {
    case flat, top
}

/// Each chip view ships at two resolutions: small for inline icons, large
/// for previews and bigger stacks.
public enum ChipSize: String, CaseIterable, Hashable, Sendable {
    case large, small
}
