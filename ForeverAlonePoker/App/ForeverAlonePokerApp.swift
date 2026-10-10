import CoreData
import SwiftData
import SwiftUI

@main
struct ForeverAlonePokerApp: App {
    private let container: ModelContainer
    private let isCloudBacked: Bool
    private let identity: IdentityStore

    init() {
        // Fall back to an in-memory store rather than crash on a corrupt
        // database; the player can still play, just without history.
        let store: Persistence.Store
        do {
            store = try Persistence.store()
        } catch {
            assertionFailure("Persistent store unavailable: \(error)")
            store = Persistence.Store(container: try! Persistence.inMemoryContainer(), isCloudBacked: false)
        }
        container = store.container
        isCloudBacked = store.isCloudBacked
        identity = try! IdentityStore(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(identity)
                .task { await reportCloudTier() }
                .task { await followRemoteChanges() }
        }
        .modelContainer(container)
    }

    /// Tier 1 (tdr/0006): the store syncs only when the device has an iCloud
    /// account for our container.
    private func reportCloudTier() async {
        guard isCloudBacked else { return }
        identity.isCloudSyncEnabled = await CloudAccount.isAvailable()
    }

    /// CloudKit imports bypass `IdentityStore`; re-read after each one.
    private func followRemoteChanges() async {
        guard isCloudBacked else { return }
        for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
            identity.refresh()
        }
    }
}

#if DEBUG
/// Shared in-memory identity for previews.
enum PreviewIdentity {
    static let store: IdentityStore = {
        let container = try! Persistence.inMemoryContainer()
        return try! IdentityStore(context: container.mainContext, defaultCountryCode: "MX")
    }()
}
#endif
