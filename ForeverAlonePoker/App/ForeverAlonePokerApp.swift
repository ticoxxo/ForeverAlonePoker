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

#if DEBUG
/// A skin store with no server, no App Store and no downloads, for previews.
enum PreviewSkins {
    static let store = SkinStore(
        loadoutStore: PreviewIdentity.store,
        catalogClient: NoCatalog(),
        assets: NoAssets(),
        purchases: NoPurchases(),
        accountToken: UUID()
    )

    private nonisolated struct NoCatalog: CatalogProviding {
        func cachedCatalog() async -> SkinCatalog? { nil }
        func fetchLatest() async throws -> SkinCatalog? { nil }
        func assetURL(for asset: AssetRef, in catalog: SkinCatalog) -> URL? { nil }
    }

    private nonisolated struct NoAssets: SkinAssetStoring {
        func fileURL(for key: AssetKey) -> URL { URL.temporaryDirectory.appending(path: key.slot.rawValue) }
        func installed(matching catalog: SkinCatalog) async -> InstalledAssets { [] }
        func install(_ key: AssetKey, from remote: URL, sha256: String) async throws {}
    }

    private nonisolated struct NoPurchases: PurchaseService {
        func products(for ids: [String]) async throws -> [StoreProduct] { [] }
        func purchase(_ productID: String, accountToken: UUID) async throws -> PurchaseOutcome { .cancelled }
        func currentEntitlements() async -> Set<String> { [] }
        func sync() async throws {}
        var updates: AsyncStream<EntitlementUpdate> { AsyncStream { $0.finish() } }
        var storefrontChanges: AsyncStream<String> { AsyncStream { $0.finish() } }
    }
}

/// Shared in-memory identity for previews.
enum PreviewIdentity {
    static let store: IdentityStore = {
        let container = try! Persistence.inMemoryContainer()
        return try! IdentityStore(context: container.mainContext, defaultCountryCode: "MX")
    }()
}
#endif
