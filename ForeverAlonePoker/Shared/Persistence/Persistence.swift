import Foundation
import SwiftData

/// Builds the app's single `ModelContainer`. CloudKit mirroring is switched on
/// here in a later step (tdr/0006); the schema is already compatible.
enum Persistence {
    static let schema = Schema([PlayerProfile.self, MatchRecord.self])

    /// On-disk store for the app.
    static func container() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Throwaway store for tests and previews.
    static func inMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
