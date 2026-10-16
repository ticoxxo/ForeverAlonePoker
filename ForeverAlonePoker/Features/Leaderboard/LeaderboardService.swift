import CloudKit
import Foundation
import PokerCore

/// One row of the public leaderboard (server-written `LeaderboardEntry`, tdr/0010).
nonisolated struct LeaderboardRow: Identifiable, Equatable, Sendable {
    let playerID: String
    let displayName: String
    let countryCode: String
    let rating: Rating
    let wins: Int
    let losses: Int

    var id: String { playerID }
}

nonisolated enum LeaderboardScope: Hashable, Sendable {
    case world
    case country(String)
}

/// Reads rankings. Behind a protocol so the model is tested without CloudKit.
nonisolated protocol LeaderboardService: Sendable {
    /// Highest ratings first.
    func top(_ scope: LeaderboardScope, limit: Int) async throws -> [LeaderboardRow]
    /// A single player's row, `nil` when they have never played ranked.
    func entry(for playerID: String) async throws -> LeaderboardRow?
    /// Profile pictures from `PublicProfile` records, keyed by player id.
    func avatars(for playerIDs: [String]) async throws -> [String: Data]
}

/// `CKQuery` against the public database of the app's container.
nonisolated struct CloudKitLeaderboardService: LeaderboardService {
    static let recordType = "LeaderboardEntry"
    let containerID: String

    init(containerID: String = Persistence.cloudContainerID) {
        self.containerID = containerID
    }

    private var database: CKDatabase { CKContainer(identifier: containerID).publicCloudDatabase }

    func top(_ scope: LeaderboardScope, limit: Int) async throws -> [LeaderboardRow] {
        let predicate: NSPredicate
        switch scope {
        case .world:
            predicate = NSPredicate(value: true)
        case .country(let code):
            predicate = NSPredicate(format: "countryCode == %@", code)
        }
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "rating", ascending: false)]
        let (results, _) = try await database.records(matching: query, resultsLimit: limit)
        return results.compactMap { _, result in
            (try? result.get()).flatMap(Self.row(from:))
        }
    }

    func entry(for playerID: String) async throws -> LeaderboardRow? {
        do {
            return Self.row(from: try await database.record(for: CKRecord.ID(recordName: "rating-\(playerID)")))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func avatars(for playerIDs: [String]) async throws -> [String: Data] {
        try await CloudKitAvatarProvider(containerID: containerID).avatars(for: playerIDs)
    }

    static func row(from record: CKRecord) -> LeaderboardRow? {
        guard record.recordID.recordName.hasPrefix("rating-"),
              let rating = record["rating"] as? Int
        else { return nil }
        return LeaderboardRow(
            playerID: String(record.recordID.recordName.dropFirst("rating-".count)),
            displayName: record["displayName"] as? String ?? "",
            countryCode: record["countryCode"] as? String ?? "",
            rating: Rating(value: rating, matchesPlayed: record["matchesPlayed"] as? Int ?? 0),
            wins: record["wins"] as? Int ?? 0,
            losses: record["losses"] as? Int ?? 0
        )
    }
}
