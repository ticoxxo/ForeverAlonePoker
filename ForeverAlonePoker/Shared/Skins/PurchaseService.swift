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

/// A past purchase for the purchase-help screens (tdr/0022): the latest
/// verified transaction of each product, refunded ones included.
nonisolated struct PurchaseRecord: Identifiable, Equatable, Sendable {
    /// The App Store transaction id, which the refund sheet takes.
    let id: UInt64
    let productID: String
    let purchaseDate: Date
    /// Refunded or revoked.
    let isRevoked: Bool
}

/// How the system refund sheet was closed. Whether Apple grants the refund
/// is decided later; a granted one arrives through `PurchaseService.updates`.
nonisolated enum RefundOutcome: Equatable, Sendable {
    case submitted
    case cancelled
}

nonisolated enum PurchaseError: Error, Equatable {
    case unknownProduct
    case failedVerification
    case noActiveScene
    /// The App Store would not open a refund request for this transaction.
    case refundUnavailable
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
    /// `false` when purchases are turned off (Screen Time, parental controls).
    var canMakePayments: Bool { get }
    /// The latest verified transaction per product, newest first.
    func purchaseHistory() async -> [PurchaseRecord]
    /// Presents the system refund sheet for one transaction.
    func requestRefund(for transactionID: UInt64) async throws -> RefundOutcome
}

/// StoreKit 2 implementation. Transactions are JWS signed by the App Store
/// and verified by StoreKit, then pinned to the bundled root certificate
/// (tdr/0022); any that fail are finished and never granted.
nonisolated final class StoreKitPurchaseService: PurchaseService {
    private let cache = ProductCache()
    private let validator: TransactionCertificateValidator

    init(validator: TransactionCertificateValidator = .bundled()) {
        self.validator = validator
    }

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
        case .success(let verification):
            guard let transaction = trusted(verification) else {
                await verification.unsafePayloadValue.finish()
                throw PurchaseError.failedVerification
            }
            return .purchased(finish: { await transaction.finish() })
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
            if let transaction = trusted(result), transaction.revocationDate == nil {
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
            let task = Task { [self] in
                for await result in Transaction.updates {
                    guard let transaction = trusted(result) else {
                        await result.unsafePayloadValue.finish()
                        continue
                    }
                    continuation.yield(EntitlementUpdate(
                        productID: transaction.productID,
                        isRevoked: transaction.revocationDate != nil,
                        finish: { await transaction.finish() }
                    ))
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

    var canMakePayments: Bool { AppStore.canMakePayments }

    func purchaseHistory() async -> [PurchaseRecord] {
        var latest: [String: Transaction] = [:]
        for await result in Transaction.all {
            guard let transaction = trusted(result) else { continue }
            if let known = latest[transaction.productID], known.purchaseDate >= transaction.purchaseDate { continue }
            latest[transaction.productID] = transaction
        }
        return latest.values
            .sorted { $0.purchaseDate > $1.purchaseDate }
            .map { PurchaseRecord(id: $0.id, productID: $0.productID, purchaseDate: $0.purchaseDate, isRevoked: $0.revocationDate != nil) }
    }

    func requestRefund(for transactionID: UInt64) async throws -> RefundOutcome {
        try await Self.refund(transactionID)
    }

    /// Verified by StoreKit and chained to the pinned root, or `nil`.
    private func trusted(_ result: VerificationResult<Transaction>) -> Transaction? {
        guard case .verified(let transaction) = result,
              validator.validate(jws: result.jwsRepresentation, environment: transaction.environment) else { return nil }
        return transaction
    }

    /// The App Store sheet is presented over the active window scene.
    @MainActor
    private static func purchase(_ product: Product, options: Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult {
        try await product.purchase(confirmIn: activeScene(), options: options)
    }

    /// The system refund sheet, over the active window scene (tdr/0022).
    @MainActor
    private static func refund(_ transactionID: UInt64) async throws -> RefundOutcome {
        let scene = try activeScene()
        do {
            switch try await Transaction.beginRefundRequest(for: transactionID, in: scene) {
            case .success: return .submitted
            case .userCancelled: return .cancelled
            @unknown default: return .cancelled
            }
        } catch is Transaction.RefundRequestError {
            throw PurchaseError.refundUnavailable
        }
    }

    @MainActor
    private static func activeScene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            throw PurchaseError.noActiveScene
        }
        return scene
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
