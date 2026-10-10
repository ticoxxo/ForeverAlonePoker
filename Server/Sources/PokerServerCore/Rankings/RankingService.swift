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

    /// Rates one finished match and stores both rows. Returns what each player
    /// should be told.
    public func record(winner: RankedPlayer, loser: RankedPlayer) async throws -> (winner: RatingUpdate, loser: RatingUpdate) {
        let existing = try await store.entries(for: [winner.playerID, loser.playerID])
        var winnerEntry = existing[winner.playerID] ?? LeaderboardEntry(playerID: winner.playerID, displayName: winner.displayName, countryCode: winner.countryCode)
        var loserEntry = existing[loser.playerID] ?? LeaderboardEntry(playerID: loser.playerID, displayName: loser.displayName, countryCode: loser.countryCode)

        let updated = EloCalculator.update(player: winnerEntry.rating, opponent: loserEntry.rating, outcome: .win)
        let winnerDelta = updated.player.value - winnerEntry.rating.value
        let loserDelta = updated.opponent.value - loserEntry.rating.value

        winnerEntry.rating = updated.player
        winnerEntry.wins += 1
        winnerEntry.displayName = winner.displayName
        winnerEntry.countryCode = winner.countryCode

        loserEntry.rating = updated.opponent
        loserEntry.losses += 1
        loserEntry.displayName = loser.displayName
        loserEntry.countryCode = loser.countryCode

        try await store.save([winnerEntry, loserEntry])
        return (
            RatingUpdate(rating: winnerEntry.rating, delta: winnerDelta),
            RatingUpdate(rating: loserEntry.rating, delta: loserDelta)
        )
    }
}

/// Everything ranked play needs. `nil` on a server without the secrets, in
/// which case every match is unranked and `/auth/apple` answers 503.
public struct RankedServices: Sendable {
    public let verifier: any IdentityVerifier
    public let sessions: SessionTokenService
    public let rankings: RankingService

    public init(verifier: any IdentityVerifier, sessions: SessionTokenService, rankings: RankingService) {
        self.verifier = verifier
        self.sessions = sessions
        self.rankings = rankings
    }

    public enum EnvironmentKey {
        public static let sessionSecret = "SESSION_SECRET"
        public static let bundleID = "APPLE_BUNDLE_ID"
        public static let container = "CLOUDKIT_CONTAINER"
        public static let environment = "CLOUDKIT_ENVIRONMENT"
        public static let keyID = "CLOUDKIT_KEY_ID"
        public static let privateKey = "CLOUDKIT_PRIVATE_KEY"
        public static let privateKeyPath = "CLOUDKIT_PRIVATE_KEY_PATH"
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

        let services = RankedServices(
            verifier: AppleIdentityVerifier.live(audience: bundleID),
            sessions: await SessionTokenService(secret: secret),
            rankings: RankingService(store: store)
        )
        return (services, usesCloudKit)
    }

    private static func privateKeyPEM(from env: [String: String]) throws -> String? {
        if let pem = env[EnvironmentKey.privateKey], !pem.isEmpty { return pem }
        if let path = env[EnvironmentKey.privateKeyPath], !path.isEmpty {
            return try String(contentsOfFile: path, encoding: .utf8)
        }
        return nil
    }
}
