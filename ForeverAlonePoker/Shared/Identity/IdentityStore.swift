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
        if let existing = try Self.resolveProfile(in: context) {
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

    /// The identity presented to opponents and authorities. Ranked players are
    /// known by their Apple user id so the server can tie them to a token.
    var identity: PlayerIdentity {
        PlayerIdentity(
            id: profile.appleUserID ?? profile.localID.uuidString,
            displayName: profile.displayName,
            countryCode: profile.countryCode
        )
    }

    /// Sent with online joins; `nil` plays unranked.
    var rankedSessionToken: String? {
        profile.appleUserID == nil ? nil : profile.rankedSessionToken
    }

    /// What the public leaderboard may show about this player; `nil` unless ranked.
    var publicProfileSnapshot: PublicProfileSnapshot? {
        guard let playerID = profile.appleUserID else { return nil }
        return PublicProfileSnapshot(
            playerID: playerID,
            displayName: profile.displayName,
            countryCode: profile.countryCode,
            avatar: profile.avatar
        )
    }

    // MARK: - Sync

    /// Re-reads the store after changes that did not go through this object
    /// (CloudKit import). Merges duplicate profiles that two devices created
    /// before their first sync: the oldest wins and keeps every match.
    func refresh() {
        if let resolved = try? Self.resolveProfile(in: context), resolved !== profile {
            profile = resolved
        }
        refreshRecentMatches()
    }

    private static func resolveProfile(in context: ModelContext) throws -> PlayerProfile? {
        let profiles = try context.fetch(FetchDescriptor<PlayerProfile>(sortBy: [SortDescriptor(\.createdAt)]))
        guard let keeper = profiles.first else { return nil }
        guard profiles.count > 1 else { return keeper }
        for duplicate in profiles.dropFirst() {
            for match in duplicate.matches ?? [] {
                match.profile = keeper
            }
            if keeper.appleUserID == nil, let appleUserID = duplicate.appleUserID {
                keeper.appleUserID = appleUserID
                keeper.rankedSessionToken = duplicate.rankedSessionToken
            }
            if keeper.avatar == nil { keeper.avatar = duplicate.avatar }
            context.delete(duplicate)
        }
        try context.save()
        return keeper
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

    // MARK: - Ranked identity (tier 2)

    /// Records a completed Sign in with Apple exchange (tdr/0010).
    func linkAppleAccount(userID: String, sessionToken: String) {
        profile.appleUserID = userID
        profile.rankedSessionToken = sessionToken
        save()
    }

    /// Back to the local or iCloud tier. History is kept.
    func unlinkAppleAccount() {
        guard profile.appleUserID != nil else { return }
        profile.appleUserID = nil
        profile.rankedSessionToken = nil
        save()
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

    /// The server rated the match that was just recorded.
    func markLatestOnlineMatchRanked() {
        guard let latest = recentMatches.first(where: { $0.mode == .online }), !latest.wasRanked else { return }
        latest.wasRanked = true
        save()
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
