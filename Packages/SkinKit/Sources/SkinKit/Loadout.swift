/// Which skin the player chose for each slot. Slots that are absent show the
/// default. Encodes as a flat `{"front.As": "spanish_001", "back": "red_check"}`
/// object, which is also the form sent to opponents (tdr/0012, protocol v3).
public struct Loadout: Hashable, Sendable, Codable {
    public private(set) var selections: [CosmeticSlot: SkinID]

    public init(_ selections: [CosmeticSlot: SkinID] = [:]) {
        self.selections = selections
    }

    /// Builds a loadout from the opaque wire map; keys this build does not
    /// understand are kept and simply never resolved.
    public init(wire: [String: String]) {
        selections = Dictionary(uniqueKeysWithValues: wire.map { (CosmeticSlot(rawValue: $0.key), SkinID($0.value)) })
    }

    public var wire: [String: String] {
        Dictionary(uniqueKeysWithValues: selections.map { ($0.key.rawValue, $0.value.rawValue) })
    }

    public subscript(slot: CosmeticSlot) -> SkinID? {
        get { selections[slot] }
        set { selections[slot] = newValue }
    }

    public mutating func equip(_ item: SkinID, on slots: some Sequence<CosmeticSlot>) {
        for slot in slots { selections[slot] = item }
    }

    /// Back to the default for these slots.
    public mutating func reset(_ slots: some Sequence<CosmeticSlot>) {
        for slot in slots { selections[slot] = nil }
    }

    /// How many slots currently use `item`.
    public func count(of item: SkinID) -> Int {
        selections.values.filter { $0 == item }.count
    }

    public init(from decoder: Decoder) throws {
        self.init(wire: try decoder.singleValueContainer().decode([String: String].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wire)
    }
}
