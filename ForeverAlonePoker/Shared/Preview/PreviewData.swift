#if DEBUG
import Foundation
import SkinKit
import SwiftData
import SwiftUI

// Mock data for SwiftUI previews only: no server, no App Store, no iCloud.

/// In-memory identities for previews.
enum PreviewIdentity {
    /// A player with a country and a short match history.
    static let store: IdentityStore = {
        let identity = makeIdentity()
        identity.updateDisplayName("Ticoxxo")
        for (summary, mode) in PreviewMatches.history {
            identity.record(summary, mode: mode)
        }
        identity.markLatestOnlineMatchRanked()
        // `record` stamps every match with "now"; spread them over the last
        // few days so the rows read like a real history (newest first).
        for (index, match) in identity.recentMatches.enumerated() {
            match.date = .now.addingTimeInterval(-Double(index) * 5 * 3600)
        }
        return identity
    }()

    /// A first launch: default name, no matches.
    static let newPlayer: IdentityStore = makeIdentity()

    /// Containers stay alive for the whole preview: a model whose container
    /// was released asserts on property access.
    private static var containers: [ModelContainer] = []

    private static func makeIdentity() -> IdentityStore {
        let container = try! Persistence.inMemoryContainer()
        containers.append(container)
        return try! IdentityStore(context: container.mainContext, defaultCountryCode: "MX")
    }
}

/// Finished matches to seed a preview identity with.
enum PreviewMatches {
    static let history: [(MatchSummary, MatchMode)] = [
        (MatchSummary(didWin: true, opponentName: "Lucía", myFinalStack: 4000, opponentFinalStack: 0, handsPlayed: 23), .local),
        (MatchSummary(didWin: false, opponentName: "Bob, Carol and Dave", myFinalStack: 0, opponentFinalStack: 7200, handsPlayed: 41, place: 3, playerCount: 4), .online),
        (MatchSummary(didWin: true, opponentName: "PracticeBot", myFinalStack: 4000, opponentFinalStack: 0, handsPlayed: 12), .practice),
        (MatchSummary(didWin: false, opponentName: "Mateo", myFinalStack: 0, opponentFinalStack: 4000, handsPlayed: 35), .local),
        (MatchSummary(didWin: true, opponentName: "Sofía", myFinalStack: 4000, opponentFinalStack: 0, handsPlayed: 18), .online),
    ]
}

/// Skin stores backed by a fixed catalog and a scripted App Store.
enum PreviewSkins {
    /// Paid sets and backs with prices; the red back is already owned.
    static let store = makeStore(
        identity: PreviewIdentity.store,
        catalog: catalog,
        products: products,
        owned: [ProductIDs.single(redBack)]
    )

    /// Only the free, bundled skins: what the store shows offline.
    static let empty = makeStore(identity: PreviewIdentity.newPlayer, catalog: nil, products: [], owned: [])

    static let spanishSet: SkinID = "spanish_001"
    static let neonSet: SkinID = "neon_001"
    static let redBack: SkinID = "red_check"
    static let greenBack: SkinID = "green_felt"

    static let catalog = SkinCatalog(
        catalogVersion: 1,
        assetBaseURL: "/skins/",
        items: [
            cardSet(spanishSet, names: ["en": "Spanish deck", "es": "Baraja española"], badge: "New"),
            cardSet(neonSet, names: ["en": "Neon nights", "es": "Noches de neón"]),
            back(redBack, names: ["en": "Red check", "es": "Cuadros rojos"]),
            back(greenBack, names: ["en": "Green felt", "es": "Fieltro verde"], badge: "Sale"),
        ]
    )

    static let products: [StoreProduct] = [
        product(ProductIDs.set(spanishSet), name: "Spanish deck", price: "2.99"),
        product(ProductIDs.set(neonSet), name: "Neon nights", price: "3.99"),
        product(ProductIDs.single(redBack), name: "Red check", price: "0.99"),
        product(ProductIDs.single(greenBack), name: "Green felt", price: "0.99"),
    ]

    private static func makeStore(
        identity: IdentityStore,
        catalog: SkinCatalog?,
        products: [StoreProduct],
        owned: Set<String>
    ) -> SkinStore {
        let store = SkinStore(
            loadoutStore: identity,
            catalogClient: FixedCatalog(catalog: catalog),
            assets: NoAssets(),
            purchases: ScriptedPurchases(catalogProducts: products, entitlements: owned),
            accountToken: UUID()
        )
        // Load catalog, entitlements and prices right away so the first
        // preview frames already show them.
        Task { await store.start() }
        return store
    }

    private static func cardSet(_ id: SkinID, names: [String: String], badge: String? = nil) -> SkinItem {
        SkinItem(
            id: id,
            kind: .cardFront,
            names: names,
            productID: ProductIDs.set(id),
            assets: Dictionary(uniqueKeysWithValues: CosmeticSlot.allCardFronts.map { ($0, asset(id, $0)) }),
            badge: badge
        )
    }

    private static func back(_ id: SkinID, names: [String: String], badge: String? = nil) -> SkinItem {
        SkinItem(
            id: id,
            kind: .cardBack,
            names: names,
            productID: ProductIDs.single(id),
            assets: [.cardBack: asset(id, .cardBack)],
            badge: badge
        )
    }

    private static func asset(_ id: SkinID, _ slot: CosmeticSlot) -> AssetRef {
        AssetRef(path: "\(id)/\(AssetNaming.fileName(for: slot))", sha256: "00", bytes: 1)
    }

    /// Prices as strings: Decimal float literals are not exact.
    private static func product(_ id: String, name: String, price text: String) -> StoreProduct {
        let price = Decimal(string: text) ?? 0
        return StoreProduct(
            id: id,
            displayName: name,
            displayPrice: price.formatted(.currency(code: "USD")),
            price: price,
            priceFormatStyle: .currency(code: "USD")
        )
    }

    /// Serves the same catalog from cache and network. No asset URLs, so
    /// nothing is downloaded and cards draw with the bundled artwork.
    private nonisolated struct FixedCatalog: CatalogProviding {
        let catalog: SkinCatalog?
        func cachedCatalog() async -> SkinCatalog? { catalog }
        func fetchLatest() async throws -> SkinCatalog? { catalog }
        func assetURL(for asset: AssetRef, in catalog: SkinCatalog) -> URL? { nil }
    }

    private nonisolated struct NoAssets: SkinAssetStoring {
        func fileURL(for key: AssetKey) -> URL { URL.temporaryDirectory.appending(path: key.slot.rawValue) }
        func installed(matching catalog: SkinCatalog) async -> InstalledAssets { [] }
        func install(_ key: AssetKey, from remote: URL, sha256: String) async throws {}
    }

    /// Answers with fixed prices and entitlements; purchases are cancelled.
    private nonisolated struct ScriptedPurchases: PurchaseService {
        let catalogProducts: [StoreProduct]
        let entitlements: Set<String>
        func products(for ids: [String]) async throws -> [StoreProduct] { catalogProducts.filter { ids.contains($0.id) } }
        func purchase(_ productID: String, accountToken: UUID) async throws -> PurchaseOutcome { .cancelled }
        func currentEntitlements() async -> Set<String> { entitlements }
        func sync() async throws {}
        var updates: AsyncStream<EntitlementUpdate> { AsyncStream { $0.finish() } }
        var storefrontChanges: AsyncStream<String> { AsyncStream { $0.finish() } }
    }
}

extension View {
    /// Injects a preview identity and skin store and applies the player's
    /// card skin.
    func previewEnvironment(
        identity: IdentityStore = PreviewIdentity.store,
        skins: SkinStore = PreviewSkins.store
    ) -> some View {
        environment(\.cardSkin, skins.myCardSkin)
            .environment(identity)
            .environment(skins)
    }
}
#endif
