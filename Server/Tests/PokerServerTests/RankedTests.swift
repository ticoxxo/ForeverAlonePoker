import _CryptoExtras
import Crypto
import Foundation
import Hummingbird
import HummingbirdTesting
import JWTKit
import Testing
import PokerCore
import PokerCoreTestSupport
@testable import PokerServerCore

// MARK: - Fixtures

/// A throwaway RSA key pair standing in for Apple's signing keys.
private struct FakeApple {
    static let audience = "Ticoxxo.ForeverAlonePoker"
    let kid = "fake-apple-kid"
    let privateKey: JWTKit.Insecure.RSA.PrivateKey
    let signer: JWTKeyCollection

    init() async throws {
        privateKey = try JWTKit.Insecure.RSA.PrivateKey(backing: _RSA.Signing.PrivateKey(keySize: .bits2048))
        signer = JWTKeyCollection()
        await signer.add(rsa: privateKey, digestAlgorithm: .sha256, kid: JWKIdentifier(string: kid))
    }

    /// Apple's `/auth/keys` document for this key, optionally under another id.
    func jwksJSON(kid override: String? = nil) throws -> String {
        let primitives = try privateKey.publicKey.getKeyPrimitives()
        let jwk = JWK.rsa(
            .rs256,
            identifier: JWKIdentifier(string: override ?? kid),
            modulus: base64URL(primitives.modulus),
            exponent: base64URL(primitives.publicExponent)
        )
        return String(decoding: try JSONEncoder().encode(JWKS(keys: [jwk])), as: UTF8.self)
    }

    func token(
        subject: String = "001234.abc",
        audience: String = FakeApple.audience,
        issuer: String = AppleIdentityVerifier.issuer,
        expiresIn: TimeInterval = 300
    ) async throws -> String {
        try await signer.sign(
            AppleIdentityToken(
                issuer: IssuerClaim(value: issuer),
                audience: AudienceClaim(value: [audience]),
                expires: ExpirationClaim(value: Date().addingTimeInterval(expiresIn)),
                issuedAt: IssuedAtClaim(value: Date()),
                subject: SubjectClaim(value: subject)
            ),
            kid: JWKIdentifier(string: kid)
        )
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Accepts tokens of the form `apple:<subject>`.
private struct FakeVerifier: IdentityVerifier {
    func verify(identityToken: String) async throws -> String {
        guard identityToken.hasPrefix("apple:") else { throw IdentityError.invalidToken("fake") }
        return String(identityToken.dropFirst("apple:".count))
    }
}

private func makeRanked(store: InMemoryLeaderboardStore = InMemoryLeaderboardStore()) async -> RankedServices {
    RankedServices(
        verifier: FakeVerifier(),
        sessions: await SessionTokenService(secret: "test-secret"),
        rankings: RankingService(store: store)
    )
}

private let ana = RankedPlayer(playerID: "ana-sub", displayName: "Ana", countryCode: "MX")
private let bruno = RankedPlayer(playerID: "bruno-sub", displayName: "Bruno", countryCode: "AR")

// MARK: - Identity

@Suite("AppleIdentityVerifier")
struct AppleIdentityVerifierTests {
    @Test("a token signed with Apple's key for our bundle id yields the subject")
    func valid() async throws {
        let apple = try await FakeApple()
        let jwks = try apple.jwksJSON()
        let verifier = AppleIdentityVerifier(audience: FakeApple.audience) { jwks }
        #expect(try await verifier.verify(identityToken: try await apple.token()) == "001234.abc")
    }

    @Test("tokens for another app, another issuer or already expired are rejected")
    func rejected() async throws {
        let apple = try await FakeApple()
        let jwks = try apple.jwksJSON()
        let verifier = AppleIdentityVerifier(audience: FakeApple.audience) { jwks }
        let bad = [
            try await apple.token(audience: "com.example.other"),
            try await apple.token(issuer: "https://accounts.example.com"),
            try await apple.token(expiresIn: -60),
            "not.a.jwt",
        ]
        for token in bad {
            await #expect(throws: IdentityError.self) {
                try await verifier.verify(identityToken: token)
            }
        }
    }

    @Test("a token signed with a rotated key triggers one key refresh")
    func refresh() async throws {
        let apple = try await FakeApple()
        // The cached document still carries the previous key under the same id.
        let stale = try await FakeApple().jwksJSON(kid: apple.kid)
        let fresh = try apple.jwksJSON()
        let loads = Counter()
        let verifier = AppleIdentityVerifier(audience: FakeApple.audience, minimumReloadInterval: 0) {
            loads.next() == 0 ? stale : fresh
        }
        #expect(try await verifier.verify(identityToken: try await apple.token()) == "001234.abc")
        #expect(loads.next() == 2, "stale document, then one reload")
    }
}

@Suite("SessionTokenService")
struct SessionTokenServiceTests {
    @Test("issued tokens verify back to the player id")
    func roundTrip() async throws {
        let service = await SessionTokenService(secret: "s3cret")
        let token = try await service.issue(playerID: "001234.abc")
        #expect(try await service.verify(token) == "001234.abc")
    }

    @Test("tampered, foreign and expired tokens are rejected")
    func rejected() async throws {
        let service = await SessionTokenService(secret: "s3cret")
        let other = await SessionTokenService(secret: "another")
        let expired = await SessionTokenService(secret: "s3cret", lifetime: -1)
        let bad = [
            try await service.issue(playerID: "x") + "x",
            try await other.issue(playerID: "x"),
            try await expired.issue(playerID: "x"),
            "",
        ]
        for token in bad {
            await #expect(throws: IdentityError.self) {
                try await service.verify(token)
            }
        }
    }
}

// MARK: - CloudKit Web Services

@Suite("CloudKitRequestSigner")
struct CloudKitRequestSignerTests {
    @Test("signs date, body hash and path with the server-to-server key")
    func headers() throws {
        let key = P256.Signing.PrivateKey()
        let signer = try CloudKitRequestSigner(keyID: "KEY123", privateKeyPEM: key.pemRepresentation)
        let body = Data(#"{"records":[]}"#.utf8)
        let path = "/database/1/iCloud.Test/development/public/records/lookup"
        let headers = try signer.headers(path: path, body: body, date: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(headers["X-Apple-CloudKit-Request-KeyID"] == "KEY123")
        #expect(headers["X-Apple-CloudKit-Request-ISO8601Date"] == "2027-01-15T08:00:00Z")

        let message = CloudKitRequestSigner.message(
            date: "2027-01-15T08:00:00Z",
            bodyHash: Data(SHA256.hash(data: body)).base64EncodedString(),
            path: path
        )
        let encoded = try #require(headers["X-Apple-CloudKit-Request-SignatureV1"].flatMap { Data(base64Encoded: $0) })
        let signature = try P256.Signing.ECDSASignature(derRepresentation: encoded)
        #expect(key.publicKey.isValidSignature(signature, for: Data(message.utf8)))
    }
}

@Suite("CloudKit records")
struct CloudKitRecordsTests {
    @Test("modify bodies force-update one LeaderboardEntry per player")
    func modifyBody() throws {
        let entry = LeaderboardEntry(playerID: "p1", displayName: "Ana", countryCode: "MX", rating: Rating(value: 1220, matchesPlayed: 1), wins: 1, losses: 0)
        let body = try CloudKitRecords.modifyBody([entry], now: Date(timeIntervalSince1970: 1_800_000_000))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let operation = (json?["operations"] as? [[String: Any]])?.first
        let record = operation?["record"] as? [String: Any]
        let fields = record?["fields"] as? [String: [String: Any]]

        #expect(operation?["operationType"] as? String == "forceUpdate")
        #expect(record?["recordType"] as? String == "LeaderboardEntry")
        #expect(record?["recordName"] as? String == "rating-p1")
        #expect(fields?["displayName"]?["value"] as? String == "Ana")
        #expect(fields?["countryCode"]?["value"] as? String == "MX")
        #expect(fields?["rating"]?["value"] as? Int == 1220)
        #expect(fields?["matchesPlayed"]?["value"] as? Int == 1)
        #expect(fields?["wins"]?["value"] as? Int == 1)
        #expect(fields?["losses"]?["value"] as? Int == 0)
        #expect(fields?["updatedAt"]?["value"] as? Int == 1_800_000_000_000)
        #expect(fields?["updatedAt"]?["type"] as? String == "TIMESTAMP")
    }

    @Test("lookup responses map found rows and skip missing ones")
    func parseLookup() throws {
        let response = """
        {"records":[
          {"recordName":"rating-p1","recordType":"LeaderboardEntry","fields":{
            "displayName":{"value":"Ana","type":"STRING"},"countryCode":{"value":"MX","type":"STRING"},
            "rating":{"value":1220,"type":"INT64"},"matchesPlayed":{"value":1,"type":"INT64"},
            "wins":{"value":1,"type":"INT64"},"losses":{"value":0,"type":"INT64"},
            "updatedAt":{"value":1800000000000,"type":"TIMESTAMP"}}},
          {"recordName":"rating-p2","reason":"Record not found","serverErrorCode":"NOT_FOUND"}
        ]}
        """
        let entries = try CloudKitRecords.parseLookup(Data(response.utf8))
        #expect(entries.count == 1)
        #expect(entries["p1"] == LeaderboardEntry(playerID: "p1", displayName: "Ana", countryCode: "MX", rating: Rating(value: 1220, matchesPlayed: 1), wins: 1, losses: 0))
    }

    @Test("server errors other than NOT_FOUND are surfaced")
    func errors() throws {
        let topLevel = Data(#"{"uuid":"x","serverErrorCode":"AUTHENTICATION_FAILED","reason":"bad key"}"#.utf8)
        #expect(throws: CloudKitError.server(code: "AUTHENTICATION_FAILED", reason: "bad key")) {
            try CloudKitRecords.parseLookup(topLevel)
        }
        let perRecord = Data(#"{"records":[{"recordName":"rating-p1","serverErrorCode":"ACCESS_DENIED","reason":"no"}]}"#.utf8)
        #expect(throws: CloudKitError.server(code: "ACCESS_DENIED", reason: "no")) {
            try CloudKitRecords.checkModify(perRecord)
        }
        #expect(throws: CloudKitError.malformedResponse) {
            try CloudKitRecords.parseLookup(Data("<html>".utf8))
        }
    }

    @Test("the store posts signed requests to the container's public database")
    func storePaths() throws {
        let store = try CloudKitLeaderboardStore(
            configuration: CloudKitConfiguration(container: "iCloud.Test", environment: "production", keyID: "K", privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation),
            http: RecordingHTTP()
        )
        #expect(store.path("modify") == "/database/1/iCloud.Test/production/public/records/modify")
    }
}

private struct RecordingHTTP: HTTPExecutor {
    func post(url: String, headers: [String: String], body: Data) async throws -> (status: Int, body: Data) {
        (200, Data(#"{"records":[]}"#.utf8))
    }
}

// MARK: - Ratings

@Suite("RankingService")
struct RankingServiceTests {
    @Test("the first match between two new players moves twenty points each way")
    func firstMatch() async throws {
        let store = InMemoryLeaderboardStore()
        let service = RankingService(store: store)
        let result = try await service.record(winner: ana, loser: bruno)

        #expect(result.winner == RatingUpdate(rating: Rating(value: 1220, matchesPlayed: 1), delta: 20))
        #expect(result.loser == RatingUpdate(rating: Rating(value: 1180, matchesPlayed: 1), delta: -20))
        let rows = try await store.entries(for: ["ana-sub", "bruno-sub"])
        #expect(rows["ana-sub"] == LeaderboardEntry(playerID: "ana-sub", displayName: "Ana", countryCode: "MX", rating: Rating(value: 1220, matchesPlayed: 1), wins: 1, losses: 0))
        #expect(rows["bruno-sub"] == LeaderboardEntry(playerID: "bruno-sub", displayName: "Bruno", countryCode: "AR", rating: Rating(value: 1180, matchesPlayed: 1), wins: 0, losses: 1))
    }

    @Test("later matches start from the stored ratings and refresh name and country")
    func laterMatch() async throws {
        let store = InMemoryLeaderboardStore()
        let service = RankingService(store: store)
        _ = try await service.record(winner: ana, loser: bruno)
        let renamed = RankedPlayer(playerID: "bruno-sub", displayName: "Bruno G.", countryCode: "UY")
        let result = try await service.record(winner: renamed, loser: ana)

        // Underdog at 1180 beats 1220: expected 0.443, K 40 -> +22.
        #expect(result.winner == RatingUpdate(rating: Rating(value: 1202, matchesPlayed: 2), delta: 22))
        #expect(result.loser == RatingUpdate(rating: Rating(value: 1198, matchesPlayed: 2), delta: -22))
        let bruno = try await store.entries(for: ["bruno-sub"])["bruno-sub"]
        #expect(bruno?.displayName == "Bruno G.")
        #expect(bruno?.countryCode == "UY")
        #expect(bruno?.wins == 1)
        #expect(bruno?.losses == 1)
    }

    @Test("services come from the environment; no secret means no ranked play")
    func environment() async throws {
        #expect(try await RankedServices.fromEnvironment([:]) == nil)
        let inMemory = try await RankedServices.fromEnvironment(["SESSION_SECRET": "x"])
        #expect(inMemory?.usesCloudKit == false)
        let cloud = try await RankedServices.fromEnvironment([
            "SESSION_SECRET": "x",
            "CLOUDKIT_KEY_ID": "K",
            "CLOUDKIT_PRIVATE_KEY": P256.Signing.PrivateKey().pemRepresentation,
        ])
        #expect(cloud?.usesCloudKit == true)
    }
}

// MARK: - Rooms

private func nextRated(_ iterator: inout AsyncStream<ServerMessage>.AsyncIterator) async -> RatingUpdate? {
    while let message = await iterator.next() {
        if case .rated(let update) = message { return update }
    }
    return nil
}

private func lastRejection(_ iterator: inout AsyncStream<ServerMessage>.AsyncIterator) async -> String? {
    while let message = await iterator.next() {
        if case .rejected(let reason) = message { return reason }
    }
    return nil
}

/// Seat one wins the first all-in: Ah Kh over Qs Qd on an ace-high board.
private let decisiveDeck: MatchRoom.DeckProvider = { _ in
    HandStateBuilder().holeCards(.one, "Ah Kh").holeCards(.two, "Qs Qd").board("Ac 7d Ts 4h 9s").deck()
}

@Suite("Ranked rooms")
struct RankedRoomTests {
    private let anaIdentity = PlayerIdentity(id: "ana-sub", displayName: "Ana", countryCode: "MX")
    private let brunoIdentity = PlayerIdentity(id: "bruno-sub", displayName: "Bruno", countryCode: "AR")

    @Test("a finished match between two signed-in players is published and both learn their rating")
    func publishes() async throws {
        let store = InMemoryLeaderboardStore()
        let ranked = await makeRanked(store: store)
        let room = Room(code: "RANK01", deckProvider: decisiveDeck, ranked: ranked)
        var anaMessages = await room.attach(TestPlayers.aliceConnection).makeAsyncIterator()
        var brunoMessages = await room.attach(TestPlayers.bobConnection).makeAsyncIterator()

        await room.receive(.join(anaIdentity, sessionToken: try await ranked.sessions.issue(playerID: "ana-sub")), from: TestPlayers.aliceConnection)
        await room.receive(.join(brunoIdentity, sessionToken: try await ranked.sessions.issue(playerID: "bruno-sub")), from: TestPlayers.bobConnection)
        #expect(await room.rankedSeatCount == 2)
        await room.receive(.ready, from: TestPlayers.aliceConnection)
        await room.receive(.ready, from: TestPlayers.bobConnection)
        await room.receive(.act(.allIn), from: TestPlayers.aliceConnection)
        await room.receive(.act(.call), from: TestPlayers.bobConnection)

        #expect(await nextRated(&anaMessages) == RatingUpdate(rating: Rating(value: 1220, matchesPlayed: 1), delta: 20))
        #expect(await nextRated(&brunoMessages) == RatingUpdate(rating: Rating(value: 1180, matchesPlayed: 1), delta: -20))
        #expect(try await store.entries(for: ["ana-sub"])["ana-sub"]?.wins == 1)
    }

    @Test("a bad session token is rejected before the seat is taken")
    func badToken() async throws {
        let ranked = await makeRanked()
        let room = Room(code: "RANK02", deckProvider: decisiveDeck, ranked: ranked)
        var messages = await room.attach(TestPlayers.aliceConnection).makeAsyncIterator()
        await room.receive(.join(anaIdentity, sessionToken: "garbage"), from: TestPlayers.aliceConnection)
        #expect(await lastRejection(&messages) == "Your ranked sign-in has expired. Sign in again from your profile.")
        #expect(await room.authority.room.isEmpty)
    }

    @Test("a token for another player is rejected")
    func mismatchedIdentity() async throws {
        let ranked = await makeRanked()
        let room = Room(code: "RANK03", deckProvider: decisiveDeck, ranked: ranked)
        var messages = await room.attach(TestPlayers.aliceConnection).makeAsyncIterator()
        let token = try await ranked.sessions.issue(playerID: "bruno-sub")
        await room.receive(.join(anaIdentity, sessionToken: token), from: TestPlayers.aliceConnection)
        #expect(await lastRejection(&messages) == "The signed-in account does not match this player.")
        #expect(await room.authority.room.isEmpty)
    }

    @Test("matches with an unsigned player are never published")
    func unranked() async throws {
        let store = InMemoryLeaderboardStore()
        let ranked = await makeRanked(store: store)
        let room = Room(code: "RANK04", deckProvider: decisiveDeck, ranked: ranked)
        _ = await room.attach(TestPlayers.aliceConnection)
        _ = await room.attach(TestPlayers.bobConnection)
        await room.receive(.join(anaIdentity, sessionToken: try await ranked.sessions.issue(playerID: "ana-sub")), from: TestPlayers.aliceConnection)
        await room.receive(.join(brunoIdentity), from: TestPlayers.bobConnection)
        #expect(await room.rankedSeatCount == 1)
        await room.receive(.ready, from: TestPlayers.aliceConnection)
        await room.receive(.ready, from: TestPlayers.bobConnection)
        await room.receive(.act(.allIn), from: TestPlayers.aliceConnection)
        await room.receive(.act(.call), from: TestPlayers.bobConnection)

        let phase = await room.authority.room.match.phase
        #expect(phase == .finished(winner: .one))
        await Task.yield()
        #expect(try await store.entries(for: ["ana-sub", "bruno-sub"]).isEmpty)
    }

    @Test("tokens are ignored on a server without ranked play")
    func notConfigured() async throws {
        let room = Room(code: "RANK05", deckProvider: decisiveDeck)
        _ = await room.attach(TestPlayers.aliceConnection)
        await room.receive(.join(anaIdentity, sessionToken: "anything"), from: TestPlayers.aliceConnection)
        #expect(await room.authority.room.isFull == false)
        #expect(await room.authority.room.players[.one]?.identity == anaIdentity)
        #expect(await room.rankedSeatCount == 0)
    }
}

@Suite("Auth route")
struct AuthRouteTests {
    @Test("exchanges a valid Apple identity token for a session token")
    func exchange() async throws {
        let ranked = await makeRanked()
        let app = buildApplication(registry: RoomRegistry(ranked: ranked))
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(AppleSignInRequest(identityToken: "apple:ana-sub"))
            try await client.execute(uri: "/auth/apple", method: .post, headers: [.contentType: "application/json"], body: ByteBuffer(bytes: body)) { response in
                #expect(response.status == .ok)
                let issued = try JSONDecoder().decode(SessionIssued.self, from: response.body)
                #expect(issued.playerID == "ana-sub")
                #expect(try await ranked.sessions.verify(issued.token) == "ana-sub")
            }
            let bad = try JSONEncoder().encode(AppleSignInRequest(identityToken: "forged"))
            try await client.execute(uri: "/auth/apple", method: .post, headers: [.contentType: "application/json"], body: ByteBuffer(bytes: bad)) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("answers 503 when ranked play is not configured")
    func unavailable() async throws {
        let app = buildApplication(registry: RoomRegistry())
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(AppleSignInRequest(identityToken: "apple:ana-sub"))
            try await client.execute(uri: "/auth/apple", method: .post, headers: [.contentType: "application/json"], body: ByteBuffer(bytes: body)) { response in
                #expect(response.status == .serviceUnavailable)
            }
        }
    }
}
