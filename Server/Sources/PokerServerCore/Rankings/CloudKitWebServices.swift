import AsyncHTTPClient
import Crypto
import Foundation
import NIOCore
import PokerCore

public enum CloudKitError: Error, Equatable, Sendable {
    case http(status: Int, body: String)
    case server(code: String, reason: String)
    case malformedResponse
}

public struct CloudKitConfiguration: Sendable {
    public var container: String
    /// `development` or `production`.
    public var environment: String
    public var keyID: String
    public var privateKeyPEM: String

    public init(container: String, environment: String, keyID: String, privateKeyPEM: String) {
        self.container = container
        self.environment = environment
        self.keyID = keyID
        self.privateKeyPEM = privateKeyPEM
    }
}

/// Signs server-to-server requests the way CloudKit Web Services expects
/// ("Composing Web Service Requests"): an ECDSA P-256 signature over
/// `date:base64(sha256(body)):path`, sent in three headers.
public struct CloudKitRequestSigner: Sendable {
    public let keyID: String
    private let privateKey: P256.Signing.PrivateKey

    public init(keyID: String, privateKeyPEM: String) throws {
        self.keyID = keyID
        privateKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
    }

    public var publicKey: P256.Signing.PublicKey { privateKey.publicKey }

    public static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    public static func bodyHash(_ body: Data) -> String {
        Data(SHA256.hash(data: body)).base64EncodedString()
    }

    public static func message(date: String, bodyHash: String, path: String) -> String {
        "\(date):\(bodyHash):\(path)"
    }

    public func headers(path: String, body: Data, date: Date = Date()) throws -> [String: String] {
        let dateString = Self.dateString(date)
        let message = Self.message(date: dateString, bodyHash: Self.bodyHash(body), path: path)
        let signature = try privateKey.signature(for: Data(message.utf8))
        return [
            "X-Apple-CloudKit-Request-KeyID": keyID,
            "X-Apple-CloudKit-Request-ISO8601Date": dateString,
            "X-Apple-CloudKit-Request-SignatureV1": signature.derRepresentation.base64EncodedString(),
        ]
    }
}

/// One player's row in the public leaderboard, as stored in the CloudKit
/// public database. Written only by the server (tdr/0006, tdr/0010).
public struct LeaderboardEntry: Sendable, Hashable, Codable {
    public static let recordType = "LeaderboardEntry"

    /// Sign in with Apple subject.
    public var playerID: String
    public var displayName: String
    public var countryCode: String
    public var rating: Rating
    public var wins: Int
    public var losses: Int

    public init(playerID: String, displayName: String, countryCode: String, rating: Rating = .initial, wins: Int = 0, losses: Int = 0) {
        self.playerID = playerID
        self.displayName = displayName
        self.countryCode = countryCode
        self.rating = rating
        self.wins = wins
        self.losses = losses
    }

    public static func recordName(for playerID: String) -> String { "rating-\(playerID)" }
    public var recordName: String { Self.recordName(for: playerID) }

    /// Reverses `recordName(for:)`; `nil` for records of another shape.
    public static func playerID(fromRecordName name: String) -> String? {
        guard name.hasPrefix("rating-") else { return nil }
        return String(name.dropFirst("rating-".count))
    }
}

/// Where leaderboard rows live.
public protocol LeaderboardStore: Sendable {
    /// Existing rows keyed by player id; players without a row are absent.
    func entries(for playerIDs: [String]) async throws -> [String: LeaderboardEntry]
    func save(_ entries: [LeaderboardEntry]) async throws
}

/// Development and test store; the server uses it when no CloudKit key is set.
public actor InMemoryLeaderboardStore: LeaderboardStore {
    private var rows: [String: LeaderboardEntry] = [:]

    public init() {}

    public func entries(for playerIDs: [String]) -> [String: LeaderboardEntry] {
        rows.filter { playerIDs.contains($0.key) }
    }

    public func save(_ entries: [LeaderboardEntry]) {
        for entry in entries { rows[entry.playerID] = entry }
    }

    public var all: [LeaderboardEntry] { Array(rows.values) }
}

/// The JSON bodies and responses of the `records/lookup` and `records/modify`
/// endpoints, kept as pure functions so they are testable without a network.
public enum CloudKitRecords {
    struct StringField: Codable {
        var value: String
        var type: String? = "STRING"
    }

    struct IntField: Codable {
        var value: Int
        var type: String? = "INT64"
    }

    struct Fields: Codable {
        var displayName: StringField
        var countryCode: StringField
        var rating: IntField
        var matchesPlayed: IntField
        var wins: IntField
        var losses: IntField
        var updatedAt: IntField?
    }

    struct Record: Codable {
        var recordType: String
        var recordName: String
        var fields: Fields
    }

    struct ModifyOperation: Codable {
        var operationType: String
        var record: Record
    }

    struct ModifyBody: Codable {
        var operations: [ModifyOperation]
    }

    struct LookupBody: Codable {
        struct Reference: Codable {
            var recordName: String
        }
        var records: [Reference]
    }

    struct RecordsResponse: Decodable {
        struct Item: Decodable {
            var recordName: String
            var fields: Fields?
            var serverErrorCode: String?
            var reason: String?
        }
        var records: [Item]?
        var serverErrorCode: String?
        var reason: String?
    }

    public static func lookupBody(playerIDs: [String]) throws -> Data {
        try JSONEncoder().encode(LookupBody(records: playerIDs.map { .init(recordName: LeaderboardEntry.recordName(for: $0)) }))
    }

    /// `forceUpdate` creates the record when it does not exist and overwrites
    /// it otherwise, which is exactly "the referee's word is final".
    public static func modifyBody(_ entries: [LeaderboardEntry], now: Date = Date()) throws -> Data {
        let timestamp = Int(now.timeIntervalSince1970 * 1000)
        let operations = entries.map { entry in
            ModifyOperation(
                operationType: "forceUpdate",
                record: Record(
                    recordType: LeaderboardEntry.recordType,
                    recordName: entry.recordName,
                    fields: Fields(
                        displayName: StringField(value: entry.displayName),
                        countryCode: StringField(value: entry.countryCode),
                        rating: IntField(value: entry.rating.value),
                        matchesPlayed: IntField(value: entry.rating.matchesPlayed),
                        wins: IntField(value: entry.wins),
                        losses: IntField(value: entry.losses),
                        updatedAt: IntField(value: timestamp, type: "TIMESTAMP")
                    )
                )
            )
        }
        return try JSONEncoder().encode(ModifyBody(operations: operations))
    }

    /// Rows found by a lookup, keyed by player id. Missing records are
    /// skipped; any other per-record or top-level error is thrown.
    public static func parseLookup(_ data: Data) throws -> [String: LeaderboardEntry] {
        let response = try decode(data)
        var entries: [String: LeaderboardEntry] = [:]
        for item in response.records ?? [] {
            if let code = item.serverErrorCode {
                if code == "NOT_FOUND" { continue }
                throw CloudKitError.server(code: code, reason: item.reason ?? "")
            }
            guard let fields = item.fields, let playerID = LeaderboardEntry.playerID(fromRecordName: item.recordName) else { continue }
            entries[playerID] = LeaderboardEntry(
                playerID: playerID,
                displayName: fields.displayName.value,
                countryCode: fields.countryCode.value,
                rating: Rating(value: fields.rating.value, matchesPlayed: fields.matchesPlayed.value),
                wins: fields.wins.value,
                losses: fields.losses.value
            )
        }
        return entries
    }

    /// Throws if any operation in a modify response failed.
    public static func checkModify(_ data: Data) throws {
        let response = try decode(data)
        for item in response.records ?? [] {
            if let code = item.serverErrorCode {
                throw CloudKitError.server(code: code, reason: item.reason ?? "")
            }
        }
    }

    private static func decode(_ data: Data) throws -> RecordsResponse {
        guard let response = try? JSONDecoder().decode(RecordsResponse.self, from: data) else {
            throw CloudKitError.malformedResponse
        }
        if let code = response.serverErrorCode {
            throw CloudKitError.server(code: code, reason: response.reason ?? "")
        }
        return response
    }
}

/// The one HTTP call the store needs, behind a protocol so tests never touch
/// the network.
public protocol HTTPExecutor: Sendable {
    func post(url: String, headers: [String: String], body: Data) async throws -> (status: Int, body: Data)
}

public struct AsyncHTTPClientExecutor: HTTPExecutor {
    private let client: HTTPClient

    public init(client: HTTPClient = .shared) {
        self.client = client
    }

    public func post(url: String, headers: [String: String], body: Data) async throws -> (status: Int, body: Data) {
        var request = HTTPClientRequest(url: url)
        request.method = .POST
        for (name, value) in headers {
            request.headers.add(name: name, value: value)
        }
        request.body = .bytes(ByteBuffer(bytes: body))
        let response = try await client.execute(request, timeout: .seconds(15))
        let buffer = try await response.body.collect(upTo: 4 << 20)
        return (Int(response.status.code), Data(buffer.readableBytesView))
    }
}

/// Leaderboard rows in the CloudKit public database, written with a
/// server-to-server key through CloudKit Web Services.
public struct CloudKitLeaderboardStore: LeaderboardStore {
    public static let endpoint = "https://api.apple-cloudkit.com"

    private let configuration: CloudKitConfiguration
    private let signer: CloudKitRequestSigner
    private let http: any HTTPExecutor

    public init(configuration: CloudKitConfiguration, http: any HTTPExecutor) throws {
        self.configuration = configuration
        signer = try CloudKitRequestSigner(keyID: configuration.keyID, privateKeyPEM: configuration.privateKeyPEM)
        self.http = http
    }

    public func entries(for playerIDs: [String]) async throws -> [String: LeaderboardEntry] {
        guard !playerIDs.isEmpty else { return [:] }
        let data = try await post("lookup", body: try CloudKitRecords.lookupBody(playerIDs: playerIDs))
        return try CloudKitRecords.parseLookup(data)
    }

    public func save(_ entries: [LeaderboardEntry]) async throws {
        guard !entries.isEmpty else { return }
        let data = try await post("modify", body: try CloudKitRecords.modifyBody(entries))
        try CloudKitRecords.checkModify(data)
    }

    public func path(_ operation: String) -> String {
        "/database/1/\(configuration.container)/\(configuration.environment)/public/records/\(operation)"
    }

    private func post(_ operation: String, body: Data) async throws -> Data {
        let path = path(operation)
        var headers = try signer.headers(path: path, body: body)
        headers["Content-Type"] = "application/json"
        let (status, data) = try await http.post(url: Self.endpoint + path, headers: headers, body: body)
        guard (200..<300).contains(status) else {
            throw CloudKitError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }
}
