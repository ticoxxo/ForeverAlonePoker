import CoreData
import SkinKit
import SwiftData
import SwiftUI

@main
struct ForeverAlonePokerApp: App {
    /// Finishes skin downloads the system completed while the app was suspended.
    @UIApplicationDelegateAdaptor(SkinDownloadAppDelegate.self) private var appDelegate
    private let container: ModelContainer
    private let isCloudBacked: Bool
    private let identity: IdentityStore
    private let skins: SkinStore

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
        // Skins (tdr/0011, tdr/0012): catalog from the game server, files
        // downloaded in the background, ownership from StoreKit.
        skins = SkinStore(
            loadoutStore: identity,
            catalogClient: HTTPCatalogClient(serverURL: identity.serverURL),
            assets: SkinAssetRepository(downloader: BackgroundSkinDownloader.shared),
            purchases: StoreKitPurchaseService(),
            accountToken: identity.profile.localID
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(identity)
                .environment(skins)
                .task { await reportCloudTier() }
                .task { await followRemoteChanges() }
                // Transaction and storefront listeners run for the app's
                // lifetime so no purchase, refund or currency change is missed.
                .task { await skins.observeTransactions() }
                .task { await skins.observeStorefront() }
                .task { await skins.start() }
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
