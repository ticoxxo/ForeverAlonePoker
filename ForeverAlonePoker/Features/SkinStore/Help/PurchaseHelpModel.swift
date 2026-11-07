import Foundation
import Observation
import SkinKit

/// State for the purchase-help screens (tdr/0022): the player's purchases
/// as the refund list shows them, and the refund requests made from it.
@Observable
final class PurchaseHelpModel {
    /// One purchase in the refund list.
    struct Row: Identifiable, Equatable {
        let record: PurchaseRecord
        /// The catalog name, or the App Store's when the catalog no longer
        /// carries the item.
        let name: String
        /// For the thumbnail; `nil` for products this build does not know.
        let item: SkinItem?

        var id: UInt64 { record.id }
    }

    enum RefundState: Equatable {
        case requesting
        /// The sheet was submitted. Apple decides later; a granted refund
        /// removes the item through `SkinStore.observeTransactions`.
        case submitted
        case failed(String)
    }

    private(set) var rows: [Row] = []
    private(set) var refundStates: [UInt64: RefundState] = [:]
    /// The transaction whose system refund sheet is up, if any. The sheet's
    /// binding clears it on dismissal.
    var presentedRefund: UInt64?
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    private let store: SkinStore

    init(store: SkinStore) {
        self.store = store
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let language = Locale.current.language.languageCode?.identifier
        rows = await store.purchaseHistory().map { record in
            let item = store.item(forProduct: record.productID)
            let name = item?.name(for: language) ?? store.product(record.productID)?.displayName ?? record.productID
            return Row(record: record, name: name, item: item)
        }.sorted(by: { $0.record.purchaseDate > $1.record.purchaseDate})
        hasLoaded = true
    }

    func canRequestRefund(_ row: Row) -> Bool {
        guard !row.record.isRevoked else { return false }
        switch refundStates[row.id] {
        case .requesting, .submitted: return false
        case .failed, nil: return true
        }
    }

    /// Opens the system refund sheet straight away: no confirmation of our
    /// own stands between the player and the request (HIG). The view shows
    /// it with `refundRequestSheet` while `presentedRefund` is set (tdr/0036).
    func requestRefund(_ row: Row) {
        guard canRequestRefund(row) else { return }
        refundStates[row.id] = .requesting
        presentedRefund = row.id
    }

    /// Apple's refund sheet for `transactionID` was dismissed with `result`.
    func refundSheetClosed(for transactionID: UInt64, with result: Result<RefundOutcome, PurchaseError>) {
        if presentedRefund == transactionID { presentedRefund = nil }
        switch result {
        case .success(.submitted): refundStates[transactionID] = .submitted
        case .success(.cancelled): refundStates[transactionID] = nil
        case .failure:
            refundStates[transactionID] = .failed(String(localized: "The refund request could not be opened. You can also request one at reportaproblem.apple.com."))
        }
    }

    /// "Missing a Purchase": re-sync with the App Store, download what came
    /// back and refresh the list.
    func recoverMissingPurchase() async {
        await store.restorePurchases()
        await load()
    }
}
