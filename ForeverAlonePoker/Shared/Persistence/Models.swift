import Foundation
import SwiftData

/// The player on this device. There is exactly one; it is the default user on
/// first launch and becomes an iCloud-backed account later without migration.
///
/// Schema rules for CloudKit compatibility (tdr/0006): every property has a
/// default, relationships are optional, no `@Attribute(.unique)`.
@Model
final class PlayerProfile {
    var localID: UUID = UUID()
    var displayName: String = "Player"
    /// ISO 3166-1 alpha-2 region code, e.g. "MX". Empty when unknown.
    var countryCode: String = ""
    @Attribute(.externalStorage) var avatar: Data? = nil
    /// Sign in with Apple subject, set when the player opts into ranked play.
    var appleUserID: String? = nil
    /// Server-issued bearer token sent on ranked joins (tdr/0010). Synced so
    /// every device of the player is ranked after one sign-in; encrypted in
    /// CloudKit because it is a credential.
    @Attribute(.allowsCloudEncryption) var rankedSessionToken: String? = nil
    /// Base URL of the game server; empty means the built-in default (tdr/0008).
    var serverURLOverride: String = ""
    /// JSON `Loadout` (SkinKit): the skin chosen for each card face and the
    /// back (tdr/0011). Synced so every device shows the same cards. Ownership
    /// is never stored here; it comes from App Store entitlements.
    var cosmeticLoadout: Data? = nil
    /// When the loadout last changed; the newest wins when duplicate profiles merge.
    var cosmeticLoadoutUpdatedAt: Date = Date.distantPast
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \MatchRecord.profile)
    var matches: [MatchRecord]? = nil

    init(displayName: String = "Player", countryCode: String = "") {
        self.displayName = displayName
        self.countryCode = countryCode
    }
}

/// How a match was played. Stored as a raw string so new modes never break
/// decoding of synced records.
nonisolated enum MatchMode: String, Codable, CaseIterable, Sendable {
    case local
    case online
    case practice

    var displayName: String {
        switch self {
        case .local: "Local"
        case .online: "Online"
        case .practice: "Practice"
        }
    }
}

/// One finished match from this player's point of view.
@Model
final class MatchRecord {
    var modeRawValue: String = MatchMode.local.rawValue
    var opponentName: String = ""
    var didWin: Bool = false
    var finalStack: Int = 0
    var opponentFinalStack: Int = 0
    var handsPlayed: Int = 0
    var date: Date = Date()
    var wasRanked: Bool = false
    /// Finishing position (1 for a win); 0 for records from before tables
    /// of more than two (tdr/0013).
    var place: Int = 0
    var playerCount: Int = 2
    var profile: PlayerProfile? = nil

    init(
        mode: MatchMode,
        opponentName: String,
        didWin: Bool,
        finalStack: Int,
        opponentFinalStack: Int,
        handsPlayed: Int,
        place: Int = 0,
        playerCount: Int = 2,
        date: Date = Date()
    ) {
        modeRawValue = mode.rawValue
        self.opponentName = opponentName
        self.didWin = didWin
        self.finalStack = finalStack
        self.opponentFinalStack = opponentFinalStack
        self.handsPlayed = handsPlayed
        self.place = place
        self.playerCount = playerCount
        self.date = date
    }

    var mode: MatchMode {
        get { MatchMode(rawValue: modeRawValue) ?? .local }
        set { modeRawValue = newValue.rawValue }
    }
}
