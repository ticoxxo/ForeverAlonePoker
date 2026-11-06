import Foundation
import JWTKit

public enum AppleRevocationError: Error, Equatable, Sendable {
    case http(status: Int, body: String)
    case malformedResponse
}

/// Revokes a player's Sign in with Apple tokens when they delete their
/// account (App Review Guideline 5.1.1(v), tdr/0034).
public protocol AppleTokenRevoker: Sendable {
    /// Redeems a fresh authorization code from the app and revokes the
    /// tokens it yields, which removes the app from the player's Apple Account.
    func revoke(authorizationCode: String) async throws
}

/// The Sign in with Apple key the server signs its client secret with
/// (Certificates, Identifiers & Profiles > Keys, "Sign in with Apple").
public struct SignInWithAppleCredentials: Sendable {
    public var teamID: String
    public var keyID: String
    /// The app's bundle identifier.
    public var clientID: String
    public var privateKeyPEM: String

    public init(teamID: String, keyID: String, clientID: String, privateKeyPEM: String) {
        self.teamID = teamID
        self.keyID = keyID
        self.clientID = clientID
        self.privateKeyPEM = privateKeyPEM
    }
}

/// Apple's REST flow: `POST /auth/token` turns the authorization code into
/// tokens, `POST /auth/revoke` revokes the refresh token (or the access token
/// when Apple sent no refresh token). The server keeps no Apple tokens, so the
/// app signs in once more to hand over a fresh code.
public struct AppleSignInTokenRevoker: AppleTokenRevoker {
    public static let tokenURL = "https://appleid.apple.com/auth/token"
    public static let revokeURL = "https://appleid.apple.com/auth/revoke"
    static let audience = "https://appleid.apple.com"
    /// Apple accepts client secrets valid for up to six months; ours lives
    /// only for the two calls it signs.
    static let secretLifetime: TimeInterval = 5 * 60

    struct ClientSecret: JWTPayload {
        var iss: IssuerClaim
        var sub: SubjectClaim
        var aud: AudienceClaim
        var iat: IssuedAtClaim
        var exp: ExpirationClaim

        func verify(using _: some JWTAlgorithm) throws {}
    }

    private struct TokenReply: Decodable {
        var access_token: String?
        var refresh_token: String?
    }

    private let credentials: SignInWithAppleCredentials
    private let keys: JWTKeyCollection
    private let http: any HTTPExecutor

    public init(credentials: SignInWithAppleCredentials, http: any HTTPExecutor) async throws {
        self.credentials = credentials
        self.http = http
        keys = JWTKeyCollection()
        await keys.add(ecdsa: try ES256PrivateKey(pem: credentials.privateKeyPEM), kid: JWKIdentifier(string: credentials.keyID))
    }

    func clientSecret(now: Date = Date()) async throws -> String {
        // Apple wants whole seconds in iat and exp.
        let issued = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        return try await keys.sign(
            ClientSecret(
                iss: IssuerClaim(value: credentials.teamID),
                sub: SubjectClaim(value: credentials.clientID),
                aud: AudienceClaim(value: Self.audience),
                iat: IssuedAtClaim(value: issued),
                exp: ExpirationClaim(value: issued.addingTimeInterval(Self.secretLifetime))
            ),
            kid: JWKIdentifier(string: credentials.keyID)
        )
    }

    public func revoke(authorizationCode: String) async throws {
        let secret = try await clientSecret()
        let reply = try await postForm(Self.tokenURL, [
            ("client_id", credentials.clientID),
            ("client_secret", secret),
            ("code", authorizationCode),
            ("grant_type", "authorization_code"),
        ])
        guard let tokens = try? JSONDecoder().decode(TokenReply.self, from: reply) else {
            throw AppleRevocationError.malformedResponse
        }
        let token: (value: String, hint: String)
        if let refresh = tokens.refresh_token {
            token = (refresh, "refresh_token")
        } else if let access = tokens.access_token {
            token = (access, "access_token")
        } else {
            throw AppleRevocationError.malformedResponse
        }
        _ = try await postForm(Self.revokeURL, [
            ("client_id", credentials.clientID),
            ("client_secret", secret),
            ("token", token.value),
            ("token_type_hint", token.hint),
        ])
    }

    private func postForm(_ url: String, _ fields: [(String, String)]) async throws -> Data {
        let body = fields.map { "\(Self.formEncode($0.0))=\(Self.formEncode($0.1))" }.joined(separator: "&")
        let (status, data) = try await http.post(
            url: url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(body.utf8)
        )
        guard (200..<300).contains(status) else {
            throw AppleRevocationError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    /// `application/x-www-form-urlencoded` leaves only unreserved characters bare.
    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
