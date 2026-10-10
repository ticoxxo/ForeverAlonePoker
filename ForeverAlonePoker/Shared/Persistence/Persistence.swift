import Foundation
import SwiftData

/// Builds the app's single `ModelContainer`.
enum Persistence {
    static let schema = Schema([PlayerProfile.self, MatchRecord.self])
    /// The iCloud container from the app's entitlements (tdr/0006, tdr/0010).
    static let cloudContainerID = "iCloud.Ticoxxo.ForeverAlonePoker"

    struct Store {
        let container: ModelContainer
        /// Whether the store mirrors to the player's private CloudKit database.
        let isCloudBacked: Bool
    }

    /// Whether this process may set up CloudKit mirroring. Core Data traps
    /// (it does not throw) when the iCloud entitlement is missing, which is
    /// the case for unit-test hosts and unsigned builds, so those stay local.
    /// `defaults write Ticoxxo.ForeverAlonePoker disableCloudSync -bool YES`
    /// (or the launch argument `-disableCloudSync YES`) forces local as well.
    static var isCloudEligible: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestSessionIdentifier"] != nil || environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
        return !UserDefaults.standard.bool(forKey: "disableCloudSync")
    }

    /// On-disk store mirrored to iCloud (tier 1) when eligible; otherwise the
    /// same file without mirroring, so the data is identical either way.
    static func store(cloudEligible: Bool = isCloudEligible) throws -> Store {
        if cloudEligible {
            let mirrored = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
            if let container = try? ModelContainer(for: schema, configurations: [mirrored]) {
                return Store(container: container, isCloudBacked: true)
            }
        }
        return Store(container: try localContainer(), isCloudBacked: false)
    }

    /// On-disk store that never talks to CloudKit.
    static func localContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Throwaway store for tests and previews.
    static func inMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
