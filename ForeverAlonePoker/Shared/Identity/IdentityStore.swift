import Foundation
import Observation
import SwiftData
import PokerCore

/// Owns the player's profile and match history. Creates the default user on
/// first launch and is the single place that writes to the store.
@Observable
final class IdentityStore {
    /// How far the player has opted into accounts (tdr/0006).
    enum Tier: Equatable {
        /// Default user, data on this device only.
        case local
        /// Profile and history sync through the player's iCloud account.
        case iCloud
        /// Signed in with Apple for rankings.
        case ranked
    }

    private let context: ModelContext
    private(set) var profile: PlayerProfile
    private(set) var recentMatches: [MatchRecord] = []
    /// Whether the store is mirrored to iCloud (set by the app once CloudKit is enabled).
    var isCloudSyncEnabled = false

    /// - Parameter defaultCountryCode: used when creating the default profile;
    ///   defaults to the device region.
    init(context: ModelContext, defaultCountryCode: String? = nil) throws {
        self.context = context
        var descriptor = FetchDescriptor<PlayerProfile>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            profile = existing
        } else {
            let created = PlayerProfile(
                displayName: "Player",
                countryCode: defaultCountryCode ?? Locale.current.region?.identifier ?? ""
            )
            context.insert(created)
            try context.save()
            profile = created
        }
        refreshRecentMatches()
    }

    var tier: Tier {
        if profile.appleUserID != nil { return .ranked }
        return isCloudSyncEnabled ? .iCloud : .local
    }

    /// The identity presented to opponents and authorities.
    var identity: PlayerIdentity {
        PlayerIdentity(id: profile.localID.uuidString, displayName: profile.displayName)
    }

    // MARK: - Editing

    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != profile.displayName else { return }
        profile.displayName = trimmed
        save()
    }

    func updateCountryCode(_ code: String) {
        guard code != profile.countryCode else { return }
        profile.countryCode = code
        save()
    }

    func updateAvatar(_ data: Data?) {
        profile.avatar = data
        save()
    }

    /// Stores a server address; blank or invalid input reverts to the default.
    func updateServerURL(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = URL(string: trimmed)?.scheme != nil ? trimmed : ""
        guard value != profile.serverURLOverride else { return }
        profile.serverURLOverride = value
        save()
    }

    /// The game server to use for online play.
    var serverURL: URL {
        URL(string: profile.serverURLOverride) ?? HTTPRoomService.defaultBaseURL
    }

    // MARK: - History

    func record(_ summary: MatchSummary, mode: MatchMode) {
        let record = MatchRecord(
            mode: mode,
            opponentName: summary.opponentName,
            didWin: summary.didWin,
            finalStack: summary.myFinalStack,
            opponentFinalStack: summary.opponentFinalStack,
            handsPlayed: summary.handsPlayed
        )
        record.profile = profile
        context.insert(record)
        save()
        refreshRecentMatches()
    }

    var wins: Int { recentMatches.filter(\.didWin).count }
    var losses: Int { recentMatches.count - wins }

    private func refreshRecentMatches() {
        var descriptor = FetchDescriptor<MatchRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 50
        recentMatches = (try? context.fetch(descriptor)) ?? []
    }

    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save profile: \(error)")
        }
    }
}
