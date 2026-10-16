import Foundation
import StoreKit
import UIKit

/// An App Store product as the store UI needs it. Prices and currency come
/// from the player's App Store storefront, never from our catalog or the
/// device locale (tdr/0012).
nonisolated struct StoreProduct: Equatable, Sendable {
    let id: String
    let displayName: String
    /// Localized in the storefront's currency, e.g. "$0.99", "19,00 MXN".
    let displayPrice: String
    let price: Decimal
    let priceFormatStyle: Decimal.FormatStyle.Currency
}

/// The result of asking the App Store to buy something.
nonisolated enum PurchaseOutcome: Sendable {
    /// Verified. Call `finish` once the purchase is reflected in the app.
    case purchased(finish: @Sendable () async -> Void)
    /// Waiting on Ask to Buy or Strong Customer Authentication; it arrives
    /// later through `PurchaseService.updates`.
    case pending
    case cancelled
}

/// A verified transaction delivered outside a purchase call: another device,
/// an Ask to Buy approval, a refund or revocation.
nonisolated struct EntitlementUpdate: Sendable {
    let productID: String
    /// Refunded or revoked: the product is no longer owned.
    let isRevoked: Bool
    let finish: @Sendable () async -> Void
}

nonisolated enum PurchaseError: Error, Equatable {
    case unknownProduct
    case failedVerification
    case noActiveScene
}

/// Everything the app needs from in-app purchase, behind a protocol so the
/// store logic is tested without StoreKit. There is no payment-method code
/// anywhere: the App Store sheet offers every method on the player's Apple
/// Account (cards incl. Apple Pay cards, balance, carrier billing…), and App
/// Review 3.1.1 forbids Apple Pay for digital goods.
nonisolated protocol PurchaseService: Sendable {
    func products(for ids: [String]) async throws -> [StoreProduct]
    /// `accountToken` ties the transaction to this player for server-side checks.
    func purchase(_ productID: String, accountToken: UUID) async throws -> PurchaseOutcome
    /// Product ids of verified, unrevoked non-consumables: the only source of
    /// truth for ownership. Refunds disappear from here automatically.
    func currentEntitlements() async -> Set<String>
    /// "Restore purchases": re-syncs this Apple Account's transactions.
    func sync() async throws
    var updates: AsyncStream<EntitlementUpdate> { get }
    /// Emits the storefront's country when the player's App Store region changes.
    var storefrontChanges: AsyncStream<String> { get }
}

/// StoreKit 2 implementation. Transactions are JWS signed by the App Store
/// and verified by StoreKit; unverified ones are finished and never granted.
nonisolated final class StoreKitPurchaseService: PurchaseService {
    private let cache = ProductCache()

    func products(for ids: [String]) async throws -> [StoreProduct] {
        // One product per item; ask in parallel batches as the catalog grows.
        let batches = stride(from: 0, to: ids.count, by: 50).map { Array(ids[$0..<min($0 + 50, ids.count)]) }
        let found = try await withThrowingTaskGroup(of: [Product].self) { group in
            for batch in batches {
                group.addTask { try await Product.products(for: batch) }
            }
            var all: [Product] = []
            for try await batch in group { all += batch }
            return all
        }
        await cache.store(found)
        return found.map(StoreProduct.init)
    }

    func purchase(_ productID: String, accountToken: UUID) async throws -> PurchaseOutcome {
        var product = await cache.product(productID)
        if product == nil { product = try await Product.products(for: [productID]).first }
        guard let product else { throw PurchaseError.unknownProduct }

        let result = try await Self.purchase(product, options: [.appAccountToken(accountToken)])
        switch result {
        case .success(.verified(let transaction)):
            return .purchased(finish: { await transaction.finish() })
        case .success(.unverified(let transaction, _)):
            await transaction.finish()
            throw PurchaseError.failedVerification
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func currentEntitlements() async -> Set<String> {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                owned.insert(transaction.productID)
            }
        }
        return owned
    }

    func sync() async throws {
        try await AppStore.sync()
    }

    var updates: AsyncStream<EntitlementUpdate> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    switch result {
                    case .verified(let transaction):
                        continuation.yield(EntitlementUpdate(
                            productID: transaction.productID,
                            isRevoked: transaction.revocationDate != nil,
                            finish: { await transaction.finish() }
                        ))
                    case .unverified(let transaction, _):
                        await transaction.finish()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    var storefrontChanges: AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                for await storefront in Storefront.updates {
                    continuation.yield(storefront.countryCode)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The App Store sheet is presented over the active window scene.
    @MainActor
    private static func purchase(_ product: Product, options: Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) else {
            throw PurchaseError.noActiveScene
        }
        return try await product.purchase(confirmIn: scene, options: options)
    }
}

private actor ProductCache {
    private var products: [String: Product] = [:]

    func store(_ found: [Product]) {
        for product in found { products[product.id] = product }
    }

    func product(_ id: String) -> Product? { products[id] }
}

private extension StoreProduct {
    nonisolated init(_ product: Product) {
        self.init(
            id: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            price: product.price,
            priceFormatStyle: product.priceFormatStyle
        )
    }
}
