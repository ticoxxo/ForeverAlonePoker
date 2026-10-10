import Foundation
import JWTKit

/// Issues and checks the bearer tokens the app sends on ranked joins
/// (tdr/0010). HS256 with a server secret; the subject is the Sign in with
/// Apple user id, so a verified token is proof of who is sitting down.
public struct SessionTokenService: Sendable {
    struct Claims: JWTPayload {
        var iss: IssuerClaim
        var sub: SubjectClaim
        var exp: ExpirationClaim

        func verify(using _: some JWTAlgorithm) throws {
            guard iss.value == SessionTokenService.issuer else {
                throw JWTError.claimVerificationFailure(failedClaim: iss, reason: "Not one of our session tokens")
            }
            try exp.verifyNotExpired()
        }
    }

    public static let issuer = "ForeverAlonePoker"
    public static let defaultLifetime: TimeInterval = 30 * 24 * 60 * 60

    private let keys: JWTKeyCollection
    public let lifetime: TimeInterval

    public init(secret: String, lifetime: TimeInterval = defaultLifetime) async {
        keys = JWTKeyCollection()
        await keys.add(hmac: HMACKey(from: secret), digestAlgorithm: .sha256)
        self.lifetime = lifetime
    }

    public func issue(playerID: String, now: Date = Date()) async throws -> String {
        try await keys.sign(Claims(
            iss: IssuerClaim(value: Self.issuer),
            sub: SubjectClaim(value: playerID),
            exp: ExpirationClaim(value: now.addingTimeInterval(lifetime))
        ))
    }

    /// Returns the player id the token was issued for.
    public func verify(_ token: String) async throws -> String {
        do {
            return try await keys.verify(token, as: Claims.self).sub.value
        } catch {
            throw IdentityError.invalidToken("\(error)")
        }
    }
}
