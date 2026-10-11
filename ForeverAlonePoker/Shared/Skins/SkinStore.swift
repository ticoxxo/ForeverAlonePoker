import Foundation
import Observation
import PokerCore
import SkinKit

/// Persists the player's skin choices. `IdentityStore` implements it so the
/// loadout lives on the synced profile (tdr/0011).
protocol LoadoutPersisting: AnyObject {
    var loadout: Loadout { get }
    func updateLoadout(_ loadout: Loadout)
}

/// The app's skin state, put in the environment at the root: the catalog,
/// what the player owns and has downloaded, their loadout, and the App Store
/// products. It turns all of that into `CardSkin` values for the card views
/// and runs purchases. Nothing in the game or the table logic depends on it
/// (tdr/0011, tdr/0012).
@Observable
final class SkinStore {
    enum PurchaseState: Equatable {
        case purchasing
        /// Ask to Buy or bank authentication; completes through `observeTransactions`.
        case pending
        case failed(String)
    }

    /// Kinds this build can draw. Supporting the mat or chips means adding
    /// their renderer and listing them here; catalogs can carry them earlier.
    static let supportedKinds: Set<CosmeticKind> = [.cardFront, .cardBack]

    private(set) var catalog: SkinCatalog = .builtIn {
        didSet { resolver = SkinResolver(catalog: catalog) }
    }
    private(set) var ownership: Ownership = .none
    private(set) var installed: InstalledAssets = []
    private(set) var products: [String: StoreProduct] = [:]
    private(set) var purchaseStates: [String: PurchaseState] = [:]
    private(set) var isRestoring = false
    /// The latest catalog or restore problem, for a non-blocking message.
    private(set) var lastError: String?

    private var resolver = SkinResolver(catalog: .builtIn)
    private let loadoutStore: any LoadoutPersisting
    private let catalogClient: any CatalogProviding
    private let assets: any SkinAssetStoring
    private let purchases: any PurchaseService
    private let appVersion: AppVersion
    private let accountToken: UUID
    private let maxConcurrentDownloads = 4

    init(
        loadoutStore: any LoadoutPersisting,
        catalogClient: any CatalogProviding,
        assets: any SkinAssetStoring,
        purchases: any PurchaseService,
        accountToken: UUID,
        appVersion: AppVersion = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
    ) {
        self.loadoutStore = loadoutStore
        self.catalogClient = catalogClient
        self.assets = assets
        self.purchases = purchases
        self.accountToken = accountToken
        self.appVersion = appVersion
    }

    var loadout: Loadout { loadoutStore.loadout }

    // MARK: - Rendering

    /// How the player's own cards look.
    var myCardSkin: CardSkin { cardSkin(loadout: loadout, ownership: ownership) }

    /// How an opponent's cards look: their choices where this device already
    /// has the files, the default everywhere else, including when we know
    /// nothing about them (`nil`).
    func opponentCardSkin(_ wire: [String: String]?) -> CardSkin {
        guard let wire else { return .standard }
        return cardSkin(loadout: Loadout(wire: wire), ownership: .everything)
    }

    /// Every slot of `item`, for store previews: installed files where present,
    /// remote previews otherwise.
    func previewSkin(for item: SkinItem) -> CardSkin {
        guard !item.isDefault else { return .standard }
        var overrides: [CosmeticSlot: SkinImageSource] = [:]
        for (slot, asset) in item.assets {
            let key = AssetKey(item: item.id, slot: slot)
            let fallback = BundledSkin.imageName(for: slot)
            if installed.contains(key) {
                overrides[slot] = .file(assets.fileURL(for: key), fallback: fallback)
            } else if let url = catalogClient.assetURL(for: asset, in: catalog) {
                overrides[slot] = .remote(url, fallback: fallback)
            }
        }
        return CardSkin(overrides: overrides)
    }

    func previewURL(for item: SkinItem) -> URL? {
        guard let preview = item.preview else { return nil }
        if let slot = item.assets.first(where: { $0.value == preview })?.key,
           installed.contains(AssetKey(item: item.id, slot: slot)) {
            return assets.fileURL(for: AssetKey(item: item.id, slot: slot))
        }
        return catalogClient.assetURL(for: preview, in: catalog)
    }

    private func cardSkin(loadout: Loadout, ownership: Ownership) -> CardSkin {
        var overrides: [CosmeticSlot: SkinImageSource] = [:]
        for slot in CosmeticSlot.allCardFronts + [.cardBack] {
            guard let resolved = resolver.resolve(slot, loadout: loadout, ownership: ownership, installed: installed),
                  !resolved.isDefault else { continue }
            let key = AssetKey(item: resolved.item.id, slot: slot)
            overrides[slot] = .file(assets.fileURL(for: key), fallback: BundledSkin.imageName(for: slot))
        }
        return CardSkin(overrides: overrides)
    }

    // MARK: - Catalog queries for the store UI

    /// Items of a kind this build can render, defaults first.
    func items(of kind: CosmeticKind) -> [SkinItem] {
        catalog.items(of: kind).sorted { ($0.isDefault ? 0 : 1, $0.id) < ($1.isDefault ? 0 : 1, $1.id) }
    }

    func owns(_ slot: CosmeticSlot, of item: SkinItem) -> Bool { ownership.owns(slot, of: item) }
    func ownsAll(of item: SkinItem) -> Bool { ownership.ownsAll(of: item) }
    func ownedCount(of item: SkinItem) -> Int { ownership.ownedSlots(of: item).count }

    /// Whether the slot currently shows this item for the player.
    func isShowing(_ item: SkinItem, in slot: CosmeticSlot) -> Bool {
        resolver.resolve(slot, loadout: loadout, ownership: ownership, installed: installed)?.item.id == item.id
    }

    func product(_ id: String?) -> StoreProduct? { id.flatMap { products[$0] } }

    func cardProduct(_ item: SkinItem, _ card: Card) -> StoreProduct? {
        item.sellsSingleCards ? products[ProductIDs.card(item.id, card)] : nil
    }

    /// "Save $13.10 over buying the cards you're missing", in the storefront currency.
    func setSavings(for item: SkinItem) -> String? {
        guard let set = product(item.productID),
              let single = item.slots.lazy.compactMap(\.card).compactMap({ self.cardProduct(item, $0) }).first
        else { return nil }
        let remaining = item.slots.count - ownedCount(of: item)
        let savings = SetPricing.savings(setPrice: set.price, cardPrice: single.price, cardsRemaining: remaining)
        return savings > 0 ? savings.formatted(set.priceFormatStyle) : nil
    }

    // MARK: - Choosing skins

    /// Shows `item` in the given slots the player owns. Choosing a default item
    /// clears the slots back to the default.
    func equip(_ item: SkinItem, on slots: [CosmeticSlot]) {
        var updated = loadout
        if item.isDefault {
            updated.reset(slots)
        } else {
            updated.equip(item.id, on: slots.filter { ownership.owns($0, of: item) })
        }
        loadoutStore.updateLoadout(updated)
    }

    func equipAll(_ item: SkinItem) {
        equip(item, on: item.slots)
    }

    // MARK: - Lifecycle

    /// Call once at launch: shows the cached catalog immediately, then
    /// refreshes catalog and entitlements in parallel, loads prices and
    /// downloads whatever the player owns but does not have yet.
    func start() async {
        if let cached = await catalogClient.cachedCatalog() { apply(cached) }
        async let catalogRefreshed: Void = refreshCatalog()
        async let entitlementsRefreshed: Void = refreshEntitlements()
        _ = await (catalogRefreshed, entitlementsRefreshed)
        await loadProducts()
        await syncAssets()
    }

    /// Long-running: purchases from other devices, Ask to Buy approvals and
    /// refunds. Start it at launch so no transaction is missed.
    func observeTransactions() async {
        for await update in purchases.updates {
            await refreshEntitlements()
            await update.finish()
            await syncAssets()
        }
    }

    /// Long-running: the App Store region (and so currency) changed.
    func observeStorefront() async {
        for await _ in purchases.storefrontChanges {
            await loadProducts()
        }
    }

    func refreshCatalog() async {
        do {
            if let latest = try await catalogClient.fetchLatest() { apply(latest) }
        } catch {
            // Offline or server down: keep the cached catalog and the defaults.
            lastError = "The skin store could not be updated."
        }
    }

    func refreshEntitlements() async {
        ownership = Ownership(productIDs: await purchases.currentEntitlements())
    }

    func loadProducts() async {
        let ids = catalog.items.flatMap(ProductIDs.all(for:))
        guard !ids.isEmpty else { return }
        do {
            let loaded = try await purchases.products(for: ids)
            products = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        } catch {
            lastError = "Prices are unavailable right now."
        }
    }

    /// Downloads every owned file that is missing or outdated, a few at a time.
    func syncAssets() async {
        installed = await assets.installed(matching: catalog)
        var missing: [(AssetKey, URL, String)] = []
        for item in catalog.items where !item.isDefault {
            for slot in ownership.ownedSlots(of: item) {
                let key = AssetKey(item: item.id, slot: slot)
                guard !installed.contains(key),
                      let asset = item.assets[slot],
                      let url = catalogClient.assetURL(for: asset, in: catalog) else { continue }
                missing.append((key, url, asset.sha256))
            }
        }
        guard !missing.isEmpty else { return }

        let assets = self.assets
        await withTaskGroup(of: AssetKey?.self) { group in
            var pending = missing.makeIterator()
            func addNext() {
                guard let (key, url, sha) = pending.next() else { return }
                group.addTask {
                    do {
                        try await assets.install(key, from: url, sha256: sha)
                        return key
                    } catch {
                        return nil  // Shown as the default; retried on the next sync.
                    }
                }
            }
            for _ in 0..<maxConcurrentDownloads { addNext() }
            for await key in group {
                if let key { installed.insert(key) }
                addNext()
            }
        }
    }

    // MARK: - Buying

    func purchase(_ productID: String) async {
        guard purchaseStates[productID] != .purchasing else { return }
        purchaseStates[productID] = .purchasing
        do {
            switch try await purchases.purchase(productID, accountToken: accountToken) {
            case .purchased(let finish):
                await refreshEntitlements()
                await finish()
                purchaseStates[productID] = nil
                await syncAssets()
            case .pending:
                purchaseStates[productID] = .pending
            case .cancelled:
                purchaseStates[productID] = nil
            }
        } catch {
            purchaseStates[productID] = .failed("The purchase could not be completed.")
        }
    }

    /// Required for non-consumables (App Review): re-syncs and re-downloads.
    func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await purchases.sync()
        } catch {
            lastError = "Purchases could not be restored."
        }
        await refreshEntitlements()
        await syncAssets()
    }

    private func apply(_ remote: SkinCatalog) {
        catalog = SkinCatalog.builtIn.merging(remote.available(kinds: Self.supportedKinds, appVersion: appVersion))
        // Pending purchases for items that left the catalog would never resolve.
        let known = Set(catalog.items.flatMap(ProductIDs.all(for:)))
        purchaseStates = purchaseStates.filter { known.contains($0.key) }
    }
}
