import CloudKit
import Foundation
import Observation

/// Profile pictures of other players, from their `PublicProfile` records
/// (tdr/0006, tdr/0013). Only players who published a ranked profile have one.
nonisolated protocol AvatarProviding: Sendable {
    /// Pictures keyed by player id; ids without a picture are simply absent.
    func avatars(for playerIDs: [String]) async throws -> [String: Data]
}

/// Reads `PublicProfile` avatars from the public database of the app's container.
nonisolated struct CloudKitAvatarProvider: AvatarProviding {
    let containerID: String

    init(containerID: String = Persistence.cloudContainerID) {
        self.containerID = containerID
    }

    func avatars(for playerIDs: [String]) async throws -> [String: Data] {
        // Without iCloud (tests, opted out) there is nothing to read.
        guard !playerIDs.isEmpty, Persistence.isCloudEligible else { return [:] }
        let database = CKContainer(identifier: containerID).publicCloudDatabase
        let ids = playerIDs.map { CKRecord.ID(recordName: PublicProfileSnapshot.recordName(for: $0)) }
        let results = try await database.records(for: ids, desiredKeys: ["avatar"])
        var avatars: [String: Data] = [:]
        let prefix = PublicProfileSnapshot.recordName(for: "")
        for (id, result) in results {
            guard let record = try? result.get(),
                  let asset = record["avatar"] as? CKAsset,
                  let url = asset.fileURL,
                  let data = try? Data(contentsOf: url)
            else { continue }
            avatars[String(id.recordName.dropFirst(prefix.count))] = data
        }
        return avatars
    }
}

/// Fetches and caches pictures for the players at a table. Each player is
/// asked for once; a lookup that fails or takes longer than `timeout` leaves
/// them without a picture, and the UI falls back to their initials.
@Observable
final class AvatarLoader {
    private(set) var avatars: [String: Data] = [:]
    private var requested: Set<String> = []
    private let provider: any AvatarProviding
    private let timeout: Duration

    init(provider: any AvatarProviding = CloudKitAvatarProvider(), timeout: Duration = .seconds(3)) {
        self.provider = provider
        self.timeout = timeout
    }

    func avatar(for playerID: String) -> Data? {
        avatars[playerID]
    }

    /// Looks up any of `playerIDs` not asked for yet.
    func load(_ playerIDs: [String]) async {
        let missing = Array(Set(playerIDs.filter { !$0.isEmpty && !requested.contains($0) }))
        guard !missing.isEmpty else { return }
        requested.formUnion(missing)
        let found = await Self.fetch(missing, from: provider, timeout: timeout)
        avatars.merge(found) { _, new in new }
    }

    /// Races the lookup against the timeout without waiting for a lookup that
    /// ignores cancellation: whichever finishes first answers.
    private nonisolated static func fetch(_ ids: [String], from provider: any AvatarProviding, timeout: Duration) async -> [String: Data] {
        await withCheckedContinuation { continuation in
            let answer = FirstAnswer(continuation)
            let lookup = Task {
                answer.resume(with: (try? await provider.avatars(for: ids)) ?? [:])
            }
            Task {
                try? await Task.sleep(for: timeout)
                lookup.cancel()
                answer.resume(with: [:])
            }
        }
    }
}

/// Resumes a continuation exactly once, from whichever caller gets there first.
private nonisolated final class FirstAnswer: @unchecked Sendable {
    private var continuation: CheckedContinuation<[String: Data], Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<[String: Data], Never>) {
        self.continuation = continuation
    }

    func resume(with value: [String: Data]) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
