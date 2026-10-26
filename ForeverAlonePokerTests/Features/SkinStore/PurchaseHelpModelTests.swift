import Foundation
import Testing
import SkinKit
import SkinKitTestSupport
@testable import ForeverAlonePoker

/// A help model over a started store with the Spanish set and the red check back.
@MainActor
private struct Fixture {
    static let spanish = SkinCatalogBuilder.cardSet("spanish_001")
    static let redCheck = SkinCatalogBuilder.back("red_check")

    let purchases = FakePurchases()
    let store: SkinStore
    let model: PurchaseHelpModel

    init() {
        purchases.catalogProducts = [
            FakePurchases.product(ProductIDs.set("spanish_001"), price: "0.99"),
            FakePurchases.product(ProductIDs.single("red_check"), price: "0.99"),
        ]
        store = SkinStore(
            loadoutStore: InMemoryLoadoutStore(),
            catalogClient: FakeCatalog(latest: .success(SkinCatalogBuilder().with(Fixture.spanish).with(Fixture.redCheck).build())),
            assets: FakeAssets(),
            purchases: purchases,
            accountToken: UUID(),
            appVersion: AppVersion("1.0")
        )
        model = PurchaseHelpModel(store: store)
    }

    static func record(_ id: UInt64, _ productID: String, daysAgo: Double, revoked: Bool = false) -> PurchaseRecord {
        PurchaseRecord(id: id, productID: productID, purchaseDate: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400), isRevoked: revoked)
    }
}

@Suite("PurchaseHelpModel")
@MainActor
struct PurchaseHelpModelTests {
    @Test("purchases show the catalog name of what they unlocked, newest first")
    func rowsNamedFromCatalog() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.history = [
            Fixture.record(1, ProductIDs.set("spanish_001"), daysAgo: 5),
            Fixture.record(2, ProductIDs.single("red_check"), daysAgo: 1),
        ]

        await fixture.model.load()

        #expect(fixture.model.rows.map(\.name) == ["red_check", "spanish_001"])
        #expect(fixture.model.rows.first?.item?.id == "red_check")
        #expect(fixture.model.hasLoaded)
    }

    @Test("a product this build does not know still shows, under its App Store id")
    func unknownProduct() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.history = [Fixture.record(9, "fap.skin.retired_back", daysAgo: 2)]

        await fixture.model.load()

        #expect(fixture.model.rows.map(\.name) == ["fap.skin.retired_back"])
        #expect(fixture.model.rows.first?.item == nil)
    }

    @Test("a refunded purchase is marked and offers no refund")
    func refundedRow() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.history = [Fixture.record(3, ProductIDs.single("red_check"), daysAgo: 1, revoked: true)]
        await fixture.model.load()
        let row = fixture.model.rows[0]

        await fixture.model.requestRefund(row)

        #expect(!fixture.model.canRequestRefund(row))
        #expect(fixture.purchases.refundRequests.isEmpty)
    }

    @Test("a submitted refund request marks the purchase as requested")
    func submitted() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.history = [Fixture.record(4, ProductIDs.single("red_check"), daysAgo: 1)]
        await fixture.model.load()
        let row = fixture.model.rows[0]

        await fixture.model.requestRefund(row)

        #expect(fixture.purchases.refundRequests == [4])
        #expect(fixture.model.refundStates[4] == .submitted)
        #expect(!fixture.model.canRequestRefund(row))
    }

    @Test("closing the refund sheet leaves the purchase as it was")
    func cancelled() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.history = [Fixture.record(5, ProductIDs.single("red_check"), daysAgo: 1)]
        fixture.purchases.refundResult = .success(.cancelled)
        await fixture.model.load()
        let row = fixture.model.rows[0]

        await fixture.model.requestRefund(row)

        #expect(fixture.model.refundStates[5] == nil)
        #expect(fixture.model.canRequestRefund(row))
    }

    @Test("a refund the App Store will not open shows a message and can be retried")
    func failed() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.history = [Fixture.record(6, ProductIDs.single("red_check"), daysAgo: 1)]
        fixture.purchases.refundResult = .failure(.refundUnavailable)
        await fixture.model.load()
        let row = fixture.model.rows[0]

        await fixture.model.requestRefund(row)

        guard case .failed = fixture.model.refundStates[6] else {
            Issue.record("expected a failure, got \(String(describing: fixture.model.refundStates[6]))")
            return
        }
        #expect(fixture.model.canRequestRefund(row))
    }

    @Test("a missing purchase restores from the App Store and reloads the list")
    func missingPurchase() async {
        let fixture = Fixture()
        await fixture.store.start()
        await fixture.model.load()
        #expect(fixture.model.rows.isEmpty)
        fixture.purchases.entitlements = [ProductIDs.single("red_check")]
        fixture.purchases.history = [Fixture.record(7, ProductIDs.single("red_check"), daysAgo: 1)]

        await fixture.model.recoverMissingPurchase()

        #expect(fixture.purchases.syncCount == 1)
        #expect(fixture.store.owns(.cardBack, of: Fixture.redCheck))
        #expect(fixture.model.rows.map(\.id) == [7])
    }
}

@Suite("SupportContact")
struct SupportContactTests {
    @Test("mail goes to the support address with an encoded subject and the app details")
    func mailURL() throws {
        let url = SupportContact.mailURL(.feedback, appVersion: "1.2", system: "iOS 27.0")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "mailto")
        #expect(components.path == "jalmeidatorres18@gmail.com")
        #expect(components.queryItems?.first { $0.name == "subject" }?.value == "ForeverAlonePoker feedback")
        #expect(components.queryItems?.first { $0.name == "body" }?.value?.contains("App 1.2, iOS 27.0") == true)
        #expect(!url.absoluteString.contains(" "))
    }

    @Test("support and feedback have different subjects")
    func subjects() {
        #expect(SupportContact.Topic.support.subject != SupportContact.Topic.feedback.subject)
    }
}
