import Foundation
import PokerCore

/// A seated player whose session token verified: the referee knows who they are.
public struct RankedPlayer: Sendable, Hashable {
    public let playerID: String
    public let displayName: String
    public let countryCode: String

    public init(playerID: String, displayName: String, countryCode: String) {
        self.playerID = playerID
        self.displayName = displayName
        self.countryCode = countryCode
    }

    public init(_ identity: PlayerIdentity) {
        self.init(playerID: identity.id, displayName: identity.displayName, countryCode: identity.countryCode)
    }
}

/// Applies Elo (PokerCore, tdr/0009) to finished ranked matches and publishes
/// the result. An actor so two matches finishing at once cannot interleave
/// their read-modify-write of the same player's row.
public actor RankingService {
    private let store: any LeaderboardStore

    public init(store: any LeaderboardStore) {
        self.store = store
    }

    /// Rates one finished heads-up match and stores both rows. Returns what
    /// each player should be told.
    public func record(winner: RankedPlayer, loser: RankedPlayer) async throws -> (winner: RatingUpdate, loser: RatingUpdate) {
        let result = try await record(winner: winner, losers: [loser])
        return (result.winner, result.losers[0])
    }

    /// Rates one finished match of any size (tdr/0013): the winner gains and
    /// every loser drops. Stores every row and returns what each player should
    /// be told, losers in the order given.
    public func record(winner: RankedPlayer, losers: [RankedPlayer]) async throws -> (winner: RatingUpdate, losers: [RatingUpdate]) {
        let existing = try await store.entries(for: [winner.playerID] + losers.map(\.playerID))
        func entry(for player: RankedPlayer) -> LeaderboardEntry {
            var entry = existing[player.playerID]
                ?? LeaderboardEntry(playerID: player.playerID, displayName: player.displayName, countryCode: player.countryCode)
            entry.displayName = player.displayName
            entry.countryCode = player.countryCode
            return entry
        }
        var winnerEntry = entry(for: winner)
        var loserEntries = losers.map(entry(for:))

        let updated = EloCalculator.updateMultiway(winner: winnerEntry.rating, losers: loserEntries.map(\.rating))
        let winnerUpdate = RatingUpdate(rating: updated.winner, delta: updated.winner.value - winnerEntry.rating.value)
        winnerEntry.rating = updated.winner
        winnerEntry.wins += 1

        var loserUpdates: [RatingUpdate] = []
        for index in loserEntries.indices {
            let rating = updated.losers[index]
            loserUpdates.append(RatingUpdate(rating: rating, delta: rating.value - loserEntries[index].rating.value))
            loserEntries[index].rating = rating
            loserEntries[index].losses += 1
        }

        try await store.save([winnerEntry] + loserEntries)
        return (winnerUpdate, loserUpdates)
    }

    /// Deletes the player's leaderboard row: their ranked account is gone
    /// (tdr/0034). A later ranked match would start them again at 1200.
    public func forget(playerID: String) async throws {
        try await store.delete(playerIDs: [playerID])
    }
}

/// Everything ranked play needs. `nil` on a server without the secrets, in
/// which case every match is unranked and `/auth/apple` answers 503.
public struct RankedServices: Sendable {
    public let verifier: any IdentityVerifier
    public let sessions: SessionTokenService
    public let rankings: RankingService
    /// Revokes Sign in with Apple tokens when a player deletes their account
    /// (tdr/0034); `nil` without the Sign in with Apple key.
    public let revoker: (any AppleTokenRevoker)?

    public init(
        verifier: any IdentityVerifier,
        sessions: SessionTokenService,
        rankings: RankingService,
        revoker: (any AppleTokenRevoker)? = nil
    ) {
        self.verifier = verifier
        self.sessions = sessions
        self.rankings = rankings
        self.revoker = revoker
    }

    public enum EnvironmentKey {
        public static let sessionSecret = "SESSION_SECRET"
        public static let bundleID = "APPLE_BUNDLE_ID"
        public static let container = "CLOUDKIT_CONTAINER"
        public static let environment = "CLOUDKIT_ENVIRONMENT"
        public static let keyID = "CLOUDKIT_KEY_ID"
        public static let privateKey = "CLOUDKIT_PRIVATE_KEY"
        public static let privateKeyPath = "CLOUDKIT_PRIVATE_KEY_PATH"
        public static let teamID = "APPLE_TEAM_ID"
        public static let signInKeyID = "APPLE_SIGNIN_KEY_ID"
        public static let signInPrivateKey = "APPLE_SIGNIN_PRIVATE_KEY"
        public static let signInPrivateKeyPath = "APPLE_SIGNIN_PRIVATE_KEY_PATH"
    }

    public static let defaultBundleID = "Ticoxxo.ForeverAlonePoker"
    public static let defaultContainer = "iCloud.Ticoxxo.ForeverAlonePoker"

    /// Builds the services from process environment variables. Returns `nil`
    /// without `SESSION_SECRET`. Without a CloudKit key the leaderboard stays
    /// in memory (development only); `usesCloudKit` says which.
    public static func fromEnvironment(_ env: [String: String]) async throws -> (services: RankedServices, usesCloudKit: Bool)? {
        guard let secret = env[EnvironmentKey.sessionSecret], !secret.isEmpty else { return nil }
        let bundleID = env[EnvironmentKey.bundleID] ?? defaultBundleID

        let store: any LeaderboardStore
        let usesCloudKit: Bool
        if let keyID = env[EnvironmentKey.keyID], !keyID.isEmpty, let pem = try privateKeyPEM(from: env) {
            store = try CloudKitLeaderboardStore(
                configuration: CloudKitConfiguration(
                    container: env[EnvironmentKey.container] ?? defaultContainer,
                    environment: env[EnvironmentKey.environment] ?? "development",
                    keyID: keyID,
                    privateKeyPEM: pem
                ),
                http: AsyncHTTPClientExecutor()
            )
            usesCloudKit = true
        } else {
            store = InMemoryLeaderboardStore()
            usesCloudKit = false
        }

        var revoker: (any AppleTokenRevoker)?
        if let teamID = env[EnvironmentKey.teamID], !teamID.isEmpty,
           let keyID = env[EnvironmentKey.signInKeyID], !keyID.isEmpty,
           let pem = try pem(from: env, inline: EnvironmentKey.signInPrivateKey, path: EnvironmentKey.signInPrivateKeyPath) {
            revoker = try await AppleSignInTokenRevoker(
                credentials: SignInWithAppleCredentials(teamID: teamID, keyID: keyID, clientID: bundleID, privateKeyPEM: pem),
                http: AsyncHTTPClientExecutor()
            )
        }

        let services = RankedServices(
            verifier: AppleIdentityVerifier.live(audience: bundleID),
            sessions: await SessionTokenService(secret: secret),
            rankings: RankingService(store: store),
            revoker: revoker
        )
        return (services, usesCloudKit)
    }

    private static func privateKeyPEM(from env: [String: String]) throws -> String? {
        try pem(from: env, inline: EnvironmentKey.privateKey, path: EnvironmentKey.privateKeyPath)
    }

    /// A PEM given inline or as a file path.
    private static func pem(from env: [String: String], inline: String, path pathKey: String) throws -> String? {
        if let pem = env[inline], !pem.isEmpty { return pem }
        if let path = env[pathKey], !path.isEmpty {
            return try String(contentsOfFile: path, encoding: .utf8)
        }
        return nil
    }
}
