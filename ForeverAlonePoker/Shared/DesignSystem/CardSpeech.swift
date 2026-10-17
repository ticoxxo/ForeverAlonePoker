import Foundation
import PokerCore

/// What VoiceOver says for cards (tdr/0018). Notation like "Td" means nothing
/// spoken aloud, so every card is read in words: "10 of diamonds".
extension Rank {
    nonisolated var spokenName: String {
        switch self {
        case .ace: String(localized: "Ace", comment: "Card rank read by VoiceOver")
        case .king: String(localized: "King", comment: "Card rank read by VoiceOver")
        case .queen: String(localized: "Queen", comment: "Card rank read by VoiceOver")
        case .jack: String(localized: "Jack", comment: "Card rank read by VoiceOver")
        default: rawValue.formatted()
        }
    }
}

extension Suit {
    nonisolated var spokenName: String {
        switch self {
        case .clubs: String(localized: "clubs", comment: "Card suit read by VoiceOver")
        case .diamonds: String(localized: "diamonds", comment: "Card suit read by VoiceOver")
        case .hearts: String(localized: "hearts", comment: "Card suit read by VoiceOver")
        case .spades: String(localized: "spades", comment: "Card suit read by VoiceOver")
        }
    }
}

extension Card {
    nonisolated var spokenName: String {
        String(localized: "\(rank.spokenName) of \(suit.spokenName)", comment: "A card read by VoiceOver, e.g. Ace of spades")
    }
}

extension Array where Element == Card {
    /// The cards one after another, as VoiceOver should read a row of them.
    nonisolated var spokenList: String {
        map(\.spokenName).joined(separator: ", ")
    }
}
