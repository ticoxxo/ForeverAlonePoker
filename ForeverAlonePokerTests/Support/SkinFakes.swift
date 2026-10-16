import Foundation
import SkinKit
@testable import ForeverAlonePoker

/// Keeps the loadout in memory instead of on a SwiftData profile.
@MainActor
final class InMemoryLoadoutStore: LoadoutPersisting {
    var loadout = Loadout()
    func updateLoadout(_ loadout: Loadout) { self.loadout = loadout }
}

/// Serves a fixed catalog; assets resolve under https://cdn.test/.
final class FakeCatalog: CatalogProviding, @unchecked Sendable {
    var cached: SkinCatalog?
    var latest: Result<SkinCatalog?, any Error>

    init(cached: SkinCatalog? = nil, latest: Result<SkinCatalog?, any Error> = .success(nil)) {
        self.cached = cached
        self.latest = latest
    }

    func cachedCatalog() async -> SkinCatalog? { cached }
    func fetchLatest() async throws -> SkinCatalog? { try latest.get() }
    func assetURL(for asset: AssetRef, in catalog: SkinCatalog) -> URL? {
        URL(string: "https://cdn.test/\(asset.path)")
    }
}

/// Installs instantly, recording what was asked, and can be told to fail.
actor FakeAssets: SkinAssetStoring {
    private(set) var installedKeys: InstalledAssets = []
    private(set) var requests: [URL] = []
    var failing: Set<AssetKey> = []

    init(preinstalled: InstalledAssets = []) {
        installedKeys = preinstalled
    }

    nonisolated func fileURL(for key: AssetKey) -> URL {
        URL(filePath: "/skins/\(key.item)/\(key.slot).png")
    }

    func installed(matching catalog: SkinCatalog) -> InstalledAssets { installedKeys }

    func install(_ key: AssetKey, from remote: URL, sha256: String) async throws {
        requests.append(remote)
        if failing.contains(key) { throw SkinAssetError.checksumMismatch }
        installedKeys.insert(key)
    }

    func fail(_ key: AssetKey) { failing.insert(key) }
}

/// A scripted App Store.
final class FakePurchases: PurchaseService, @unchecked Sendable {
    var catalogProducts: [StoreProduct] = []
    var entitlements: Set<String> = []
    var nextOutcome: PurchaseOutcomeScript = .purchase
    /// `false` mimics StoreKit leaving a just-verified purchase out of
    /// `currentEntitlements` for a while (seen in Xcode's StoreKit testing).
    var listsPurchasesImmediately = true
    private(set) var finishedTransactions: [String] = []
    private(set) var purchasedTokens: [UUID] = []
    private(set) var syncCount = 0
    let updates: AsyncStream<EntitlementUpdate>
    let storefrontChanges: AsyncStream<String>
    private let updatesContinuation: AsyncStream<EntitlementUpdate>.Continuation
    private let storefrontContinuation: AsyncStream<String>.Continuation

    enum PurchaseOutcomeScript {
        case purchase, pending, cancel, fail
    }

    init() {
        (updates, updatesContinuation) = AsyncStream.makeStream(of: EntitlementUpdate.self)
        (storefrontChanges, storefrontContinuation) = AsyncStream.makeStream(of: String.self)
    }

    func products(for ids: [String]) async throws -> [StoreProduct] {
        catalogProducts.filter { ids.contains($0.id) }
    }

    func purchase(_ productID: String, accountToken: UUID) async throws -> PurchaseOutcome {
        purchasedTokens.append(accountToken)
        switch nextOutcome {
        case .purchase:
            if listsPurchasesImmediately { entitlements.insert(productID) }
            return .purchased(finish: { [weak self] in self?.finishedTransactions.append(productID) })
        case .pending: return .pending
        case .cancel: return .cancelled
        case .fail: throw PurchaseError.failedVerification
        }
    }

    func currentEntitlements() async -> Set<String> { entitlements }
    func sync() async throws { syncCount += 1 }

    /// Simulates a transaction arriving outside a purchase (refund, Ask to Buy).
    func deliverUpdate(productID: String, isRevoked: Bool = false) {
        updatesContinuation.yield(EntitlementUpdate(productID: productID, isRevoked: isRevoked, finish: { [weak self] in
            self?.finishedTransactions.append(productID)
        }))
    }

    func changeStorefront(to country: String) { storefrontContinuation.yield(country) }

    /// Prices as strings: Decimal float literals are not exact.
    static func product(_ id: String, price text: String) -> StoreProduct {
        let price = Decimal(string: text)!
        return StoreProduct(
            id: id,
            displayName: id,
            displayPrice: price.formatted(.currency(code: "USD")),
            price: price,
            priceFormatStyle: .currency(code: "USD")
        )
    }
}
