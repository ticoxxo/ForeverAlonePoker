/// The reactions a player can send to the table (tdr/0015). A closed set, so
/// there is no free text to moderate: anything else fails to decode and never
/// reaches the room.
public enum Emote: String, Codable, Sendable, Hashable, CaseIterable {
    case smile = "😃"
    case melting = "🫠"
    case laughing = "😂"
    case upsideDown = "🙃"
    case cursing = "🤬"
    case freezing = "🥶"
    case poop = "💩"
    case cool = "😎"
    case eyes = "👀"

    public var symbol: String { rawValue }
}
