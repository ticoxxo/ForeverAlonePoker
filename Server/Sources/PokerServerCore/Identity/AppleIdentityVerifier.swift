import AsyncHTTPClient
import Foundation
import JWTKit
import NIOCore

public enum IdentityError: Error, Equatable, Sendable {
    /// The token could not be verified. The reason is for logs, not players.
    case invalidToken(String)
    case notConfigured
}

/// Turns a Sign in with Apple identity token into the player's stable subject.
public protocol IdentityVerifier: Sendable {
    /// Returns the Apple user id (`sub`) when the token is genuine, unexpired
    /// and issued for this app.
    func verify(identityToken: String) async throws -> String
}

/// Verifies identity tokens against Apple's published signing keys. Keys are
/// cached; a token that fails to verify triggers one refetch (rate limited),
/// which is how Apple's key rotation shows up (tdr/0010).
public actor AppleIdentityVerifier: IdentityVerifier {
    public typealias JWKSLoader = @Sendable () async throws -> String

    public static let issuer = "https://appleid.apple.com"
    public static let keysURL = "https://appleid.apple.com/auth/keys"

    private let audience: String
    private let loadKeys: JWKSLoader
    private let minimumReloadInterval: TimeInterval
    private var keys: JWTKeyCollection?
    private var loadedAt: Date = .distantPast

    /// - Parameters:
    ///   - audience: the app's bundle identifier (the token's `aud`).
    ///   - loadKeys: returns Apple's JWKS document as JSON.
    public init(audience: String, minimumReloadInterval: TimeInterval = 60, loadKeys: @escaping JWKSLoader) {
        self.audience = audience
        self.minimumReloadInterval = minimumReloadInterval
        self.loadKeys = loadKeys
    }

    /// Fetches Apple's keys over HTTPS.
    public static func live(audience: String, httpClient: HTTPClient = .shared) -> AppleIdentityVerifier {
        AppleIdentityVerifier(audience: audience) {
            var request = HTTPClientRequest(url: keysURL)
            request.method = .GET
            let response = try await httpClient.execute(request, timeout: .seconds(10))
            guard response.status == .ok else {
                throw IdentityError.invalidToken("Apple keys unavailable (HTTP \(response.status.code))")
            }
            let body = try await response.body.collect(upTo: 1 << 20)
            return String(decoding: body.readableBytesView, as: UTF8.self)
        }
    }

    public func verify(identityToken: String) async throws -> String {
        do {
            return try await check(identityToken, with: currentKeys())
        } catch {
            // An unknown `kid` or a stale cache: refresh once and retry.
            guard Date().timeIntervalSince(loadedAt) >= minimumReloadInterval else {
                throw IdentityError.invalidToken("\(error)")
            }
            do {
                return try await check(identityToken, with: reloadKeys())
            } catch {
                throw IdentityError.invalidToken("\(error)")
            }
        }
    }

    private func currentKeys() async throws -> JWTKeyCollection {
        if let keys { return keys }
        return try await reloadKeys()
    }

    private func reloadKeys() async throws -> JWTKeyCollection {
        let json = try await loadKeys()
        let collection = JWTKeyCollection()
        _ = try await collection.add(jwksJSON: json)
        keys = collection
        loadedAt = Date()
        return collection
    }

    private func check(_ token: String, with keys: JWTKeyCollection) async throws -> String {
        // `AppleIdentityToken.verify` checks the issuer and expiry.
        let payload = try await keys.verify(token, as: AppleIdentityToken.self)
        try payload.audience.verifyIntendedAudience(includes: audience)
        return payload.subject.value
    }
}
