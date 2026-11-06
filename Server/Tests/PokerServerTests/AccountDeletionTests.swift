import Crypto
import Foundation
import Hummingbird
import HummingbirdTesting
import JWTKit
import Testing
import PokerCore
@testable import PokerServerCore

// MARK: - Fixtures

/// Remembers every authorization code it was asked to revoke.
private actor RecordingRevoker: AppleTokenRevoker {
    private(set) var codes: [String] = []

    func revoke(authorizationCode: String) async throws {
        codes.append(authorizationCode)
    }
}

private struct FailingRevoker: AppleTokenRevoker {
    func revoke(authorizationCode: String) async throws {
        throw AppleRevocationError.http(status: 400, body: "invalid_grant")
    }
}

/// Answers Apple's token and revoke endpoints and records each form it got.
private actor AppleEndpoints: HTTPExecutor {
    struct Call: Equatable {
        let url: String
        let form: [String: String]
    }

    private(set) var calls: [Call] = []
    let tokenReply: String

    init(tokenReply: String = #"{"access_token":"a1","token_type":"Bearer","expires_in":3600,"refresh_token":"r1","id_token":"x"}"#) {
        self.tokenReply = tokenReply
    }

    func post(url: String, headers: [String: String], body: Data) async throws -> (status: Int, body: Data) {
        #expect(headers["Content-Type"] == "application/x-www-form-urlencoded")
        let pairs = String(decoding: body, as: UTF8.self).split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? "" }
            return (parts[0], parts.count > 1 ? parts[1] : "")
        }
        calls.append(Call(url: url, form: Dictionary(uniqueKeysWithValues: pairs)))
        return url == AppleSignInTokenRevoker.tokenURL ? (200, Data(tokenReply.utf8)) : (200, Data())
    }
}

private let credentials = SignInWithAppleCredentials(
    teamID: "TEAM123456",
    keyID: "KEY1234567",
    clientID: "Ticoxxo.ForeverAlonePoker",
    privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation
)

private func deletionBody(identityToken: String, authorizationCode: String? = "code-1") throws -> ByteBuffer {
    ByteBuffer(bytes: try JSONEncoder().encode(AccountDeletionRequest(identityToken: identityToken, authorizationCode: authorizationCode)))
}

private let ana = RankedPlayer(playerID: "ana-sub", displayName: "Ana", countryCode: "MX")
private let bruno = RankedPlayer(playerID: "bruno-sub", displayName: "Bruno", countryCode: "AR")

// MARK: - Leaderboard rows

@Suite("Deleting leaderboard rows")
struct LeaderboardDeletionTests {
    @Test("forgetting a player removes only their row")
    func forget() async throws {
        let store = InMemoryLeaderboardStore()
        let rankings = RankingService(store: store)
        _ = try await rankings.record(winner: ana, loser: bruno)

        try await rankings.forget(playerID: "ana-sub")

        let rows = try await store.entries(for: ["ana-sub", "bruno-sub"])
        #expect(rows.keys.sorted() == ["bruno-sub"])
    }

    @Test("CloudKit delete bodies force-delete the player's record by name")
    func deleteBody() throws {
        let body = try CloudKitRecords.deleteBody(playerIDs: ["p1"])
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let operation = (json?["operations"] as? [[String: Any]])?.first
        let record = operation?["record"] as? [String: Any]

        #expect(operation?["operationType"] as? String == "forceDelete")
        #expect(record?["recordName"] as? String == "rating-p1")
    }

    @Test("deleting a record that never existed is not an error; other failures are")
    func deleteResponses() throws {
        let missing = Data(#"{"records":[{"recordName":"rating-p1","serverErrorCode":"NOT_FOUND","reason":"gone"}]}"#.utf8)
        try CloudKitRecords.checkDelete(missing)

        let denied = Data(#"{"records":[{"recordName":"rating-p1","serverErrorCode":"ACCESS_DENIED","reason":"no"}]}"#.utf8)
        #expect(throws: CloudKitError.server(code: "ACCESS_DENIED", reason: "no")) {
            try CloudKitRecords.checkDelete(denied)
        }
    }
}

// MARK: - Sign in with Apple revocation

@Suite("AppleSignInTokenRevoker")
struct AppleSignInTokenRevokerTests {
    @Test("the client secret is an ES256 JWT from the team, for our app, addressed to Apple")
    func clientSecret() async throws {
        let revoker = try await AppleSignInTokenRevoker(credentials: credentials, http: AppleEndpoints())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let secret = try await revoker.clientSecret(now: now)

        let parts = secret.split(separator: ".")
        #expect(parts.count == 3)
        let header = try JSONSerialization.jsonObject(with: try #require(Data(base64URL: String(parts[0])))) as? [String: Any]
        let claims = try JSONSerialization.jsonObject(with: try #require(Data(base64URL: String(parts[1])))) as? [String: Any]
        #expect(header?["alg"] as? String == "ES256")
        #expect(header?["kid"] as? String == "KEY1234567")
        #expect(claims?["iss"] as? String == "TEAM123456")
        #expect(claims?["sub"] as? String == "Ticoxxo.ForeverAlonePoker")
        #expect(claims?["aud"] as? String == "https://appleid.apple.com")
        #expect(claims?["iat"] as? Double == 1_800_000_000)
        #expect((claims?["exp"] as? Double ?? 0) > 1_800_000_000)
    }

    @Test("revoking redeems the authorization code, then revokes the refresh token")
    func revoke() async throws {
        let apple = AppleEndpoints()
        let revoker = try await AppleSignInTokenRevoker(credentials: credentials, http: apple)
        try await revoker.revoke(authorizationCode: "code-1")

        let calls = await apple.calls
        #expect(calls.map(\.url) == [AppleSignInTokenRevoker.tokenURL, AppleSignInTokenRevoker.revokeURL])
        #expect(calls[0].form["grant_type"] == "authorization_code")
        #expect(calls[0].form["code"] == "code-1")
        #expect(calls[0].form["client_id"] == "Ticoxxo.ForeverAlonePoker")
        #expect(calls[0].form["client_secret"]?.isEmpty == false)
        #expect(calls[1].form["token"] == "r1")
        #expect(calls[1].form["token_type_hint"] == "refresh_token")
        #expect(calls[1].form["client_id"] == "Ticoxxo.ForeverAlonePoker")
    }

    @Test("without a refresh token the access token is revoked")
    func accessTokenOnly() async throws {
        let apple = AppleEndpoints(tokenReply: #"{"access_token":"a1","token_type":"Bearer","expires_in":3600}"#)
        let revoker = try await AppleSignInTokenRevoker(credentials: credentials, http: apple)
        try await revoker.revoke(authorizationCode: "code-1")

        let revoke = await apple.calls.last
        #expect(revoke?.form["token"] == "a1")
        #expect(revoke?.form["token_type_hint"] == "access_token")
    }

    @Test("revocation is configured only with the team, key id and private key")
    func environment() async throws {
        let base = ["SESSION_SECRET": "x"]
        #expect(try await RankedServices.fromEnvironment(base)?.services.revoker == nil)
        let configured = try await RankedServices.fromEnvironment(base.merging([
            "APPLE_TEAM_ID": "TEAM123456",
            "APPLE_SIGNIN_KEY_ID": "KEY1234567",
            "APPLE_SIGNIN_PRIVATE_KEY": P256.Signing.PrivateKey().pemRepresentation,
        ]) { $1 })
        #expect(configured?.services.revoker != nil)
    }
}

// MARK: - Route

@Suite("Account deletion route")
struct AccountDeletionRouteTests {
    @Test("a verified player loses their leaderboard row and their Apple token is revoked")
    func deletes() async throws {
        let store = InMemoryLeaderboardStore()
        let revoker = RecordingRevoker()
        let ranked = await makeRanked(store: store, revoker: revoker)
        _ = try await ranked.rankings.record(winner: ana, loser: bruno)
        let app = buildApplication(registry: RoomRegistry(ranked: ranked))

        try await app.test(.router) { client in
            try await client.execute(uri: "/account/delete", method: .post, headers: [.contentType: "application/json"], body: try deletionBody(identityToken: "apple:ana-sub")) { response in
                #expect(response.status == .noContent)
            }
        }
        #expect(try await store.entries(for: ["ana-sub", "bruno-sub"]).keys.sorted() == ["bruno-sub"])
        #expect(await revoker.codes == ["code-1"])
    }

    @Test("a forged identity token deletes nothing")
    func forged() async throws {
        let store = InMemoryLeaderboardStore()
        let ranked = await makeRanked(store: store)
        _ = try await ranked.rankings.record(winner: ana, loser: bruno)
        let app = buildApplication(registry: RoomRegistry(ranked: ranked))

        try await app.test(.router) { client in
            try await client.execute(uri: "/account/delete", method: .post, headers: [.contentType: "application/json"], body: try deletionBody(identityToken: "forged")) { response in
                #expect(response.status == .unauthorized)
            }
        }
        #expect(try await store.entries(for: ["ana-sub"]).count == 1)
    }

    @Test("a failed revocation still deletes the row")
    func revocationFails() async throws {
        let store = InMemoryLeaderboardStore()
        let ranked = await makeRanked(store: store, revoker: FailingRevoker())
        _ = try await ranked.rankings.record(winner: ana, loser: bruno)
        let app = buildApplication(registry: RoomRegistry(ranked: ranked))

        try await app.test(.router) { client in
            try await client.execute(uri: "/account/delete", method: .post, headers: [.contentType: "application/json"], body: try deletionBody(identityToken: "apple:ana-sub")) { response in
                #expect(response.status == .noContent)
            }
        }
        #expect(try await store.entries(for: ["ana-sub"]).isEmpty)
    }

    @Test("answers 503 when ranked play is not configured")
    func unavailable() async throws {
        let app = buildApplication(registry: RoomRegistry())
        try await app.test(.router) { client in
            try await client.execute(uri: "/account/delete", method: .post, headers: [.contentType: "application/json"], body: try deletionBody(identityToken: "apple:ana-sub")) { response in
                #expect(response.status == .serviceUnavailable)
            }
        }
    }
}

// MARK: - Privacy policy

@Suite("Privacy policy route")
struct PrivacyPolicyRouteTests {
    @Test("the policy is served as HTML and explains how to delete the ranked account")
    func served() async throws {
        let app = buildApplication()
        try await app.test(.router) { client in
            try await client.execute(uri: "/privacy", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType]?.hasPrefix("text/html") == true)
                let html = String(buffer: response.body)
                #expect(html.contains("Delete ranked account"))
            }
        }
    }
}

private extension Data {
    init?(base64URL: String) {
        var base64 = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
