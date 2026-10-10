import CloudKit
import Foundation

/// The part of a ranked player's profile everyone may see (tdr/0006 tier 2).
nonisolated struct PublicProfileSnapshot: Equatable, Sendable {
    let playerID: String
    let displayName: String
    let countryCode: String
    let avatar: Data?

    static let recordType = "PublicProfile"
    static func recordName(for playerID: String) -> String { "profile-\(playerID)" }
}

nonisolated protocol PublicProfilePublishing: Sendable {
    func publish(_ snapshot: PublicProfileSnapshot) async throws
}

/// Writes `PublicProfile` records to the public CloudKit database. The record
/// is owned by the signed-in iCloud user, which is who may update it.
nonisolated struct CloudKitPublicProfilePublisher: PublicProfilePublishing {
    let containerID: String

    init(containerID: String = Persistence.cloudContainerID) {
        self.containerID = containerID
    }

    func publish(_ snapshot: PublicProfileSnapshot) async throws {
        let database = CKContainer(identifier: containerID).publicCloudDatabase
        let recordID = CKRecord.ID(recordName: PublicProfileSnapshot.recordName(for: snapshot.playerID))
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: PublicProfileSnapshot.recordType, recordID: recordID)
        }
        record["displayName"] = snapshot.displayName
        record["countryCode"] = snapshot.countryCode
        if let avatar = snapshot.avatar {
            let url = FileManager.default.temporaryDirectory.appending(path: "avatar-\(UUID().uuidString).jpg")
            try avatar.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            record["avatar"] = CKAsset(fileURL: url)
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        } else {
            record["avatar"] = nil
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        }
    }
}
