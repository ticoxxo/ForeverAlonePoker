import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport
import SkinKit
import SkinKitTestSupport
@testable import ForeverAlonePoker

/// A store over fakes with the Spanish set and the red check back in the remote catalog.
@MainActor
private struct Fixture {
    static let spanish = SkinCatalogBuilder.cardSet("spanish_001")
    static let redCheck = SkinCatalogBuilder.back("red_check")
    static let remote = SkinCatalogBuilder().with(spanish).with(redCheck).build()

    let loadout = InMemoryLoadoutStore()
    let catalog: FakeCatalog
    let assets: FakeAssets
    let purchases = FakePurchases()
    let token = UUID()
    let store: SkinStore

    /// `remote` defaults to `Fixture.remote`.
    init(remote: Result<SkinCatalog?, any Error>? = nil, cached: SkinCatalog? = nil, preinstalled: InstalledAssets = []) {
        catalog = FakeCatalog(cached: cached, latest: remote ?? .success(Fixture.remote))
        assets = FakeAssets(preinstalled: preinstalled)
        purchases.catalogProducts = [
            FakePurchases.product(ProductIDs.set("spanish_001"), price: "0.99"),
            FakePurchases.product(ProductIDs.single("red_check"), price: "0.99"),
        ]
        store = SkinStore(
            loadoutStore: loadout,
            catalogClient: catalog,
            assets: assets,
            purchases: purchases,
            accountToken: token,
            appVersion: AppVersion("1.0")
        )
    }
}

@Suite("SkinStore")
@MainActor
struct SkinStoreTests {
    private let ace = CosmeticSlot.cardFront(card("As"))
    private let king = CosmeticSlot.cardFront(card("Kd"))

    @Test("before anything loads every card is the bundled default")
    func defaultsFirst() {
        let fixture = Fixture()
        #expect(fixture.store.myCardSkin == .standard)
        #expect(fixture.store.myCardSkin.source(for: ace) == .bundled("skin-default-front-As"))
        #expect(fixture.store.myCardSkin.source(for: .cardBack) == .bundled("skin-navy_check-back"))
    }

    @Test("start merges the remote catalog behind the built-in defaults and loads prices")
    func start() async {
        let fixture = Fixture()
        await fixture.store.start()
        #expect(fixture.store.catalog.item("spanish_001") != nil)
        #expect(fixture.store.catalog.item(SkinCatalog.defaultFrontID)?.isDefault == true)
        #expect(fixture.store.product(ProductIDs.set("spanish_001")) == FakePurchases.product(ProductIDs.set("spanish_001"), price: "0.99"))
    }

    @Test("an unreachable catalog keeps the cached one and reports it")
    func offline() async {
        let fixture = Fixture(remote: .failure(URLError(.notConnectedToInternet)), cached: Fixture.remote)
        await fixture.store.start()
        #expect(fixture.store.catalog.item("red_check") != nil)
        #expect(fixture.store.lastError != nil)
    }

    @Test("owned files are downloaded and unowned ones are not")
    func downloadsOwned() async {
        let fixture = Fixture()
        fixture.purchases.entitlements = [ProductIDs.single("red_check")]
        await fixture.store.start()
        #expect(fixture.store.installed == [AssetKey(item: "red_check", slot: .cardBack)])
        #expect(await fixture.assets.requests == [URL(string: "https://cdn.test/red_check/back.png")!])
    }

    @Test("a set that was not bought cannot be equipped")
    func equipUnowned() async {
        let fixture = Fixture()
        await fixture.store.start()

        fixture.store.equipAll(Fixture.spanish)

        #expect(fixture.loadout.loadout[ace] == nil)
        #expect(fixture.store.myCardSkin.source(for: ace) == .bundled("skin-default-front-As"))
    }

    @Test("a bought set downloads and shows every card once equipped")
    func equipOwnedSet() async {
        let fixture = Fixture()
        await fixture.store.start()
        await fixture.store.purchase(ProductIDs.set("spanish_001"))

        fixture.store.equipAll(Fixture.spanish)

        #expect(fixture.store.ownsAll(of: Fixture.spanish))
        #expect(fixture.store.installed.count == 52)
        #expect(fixture.store.myCardSkin.source(for: ace) == .file(URL(filePath: "/skins/spanish_001/front.As.png"), fallback: "skin-default-front-As"))
        #expect(fixture.store.myCardSkin.source(for: king) == .file(URL(filePath: "/skins/spanish_001/front.Kd.png"), fallback: "skin-default-front-Kd"))
    }

    @Test("a single-card entitlement unlocks nothing: cards are sold only with the set")
    func singleCardEntitlementIgnored() async {
        let fixture = Fixture()
        fixture.purchases.entitlements = ["fap.skin.spanish_001.card.As"]
        await fixture.store.start()
        #expect(!fixture.store.owns(ace, of: Fixture.spanish))
        #expect(fixture.store.installed.isEmpty)
    }

    @Test("a file that failed to download shows the default until a later sync")
    func failedDownload() async {
        let fixture = Fixture()
        fixture.purchases.entitlements = [ProductIDs.single("red_check")]
        await fixture.assets.fail(AssetKey(item: "red_check", slot: .cardBack))
        await fixture.store.start()
        fixture.store.equip(Fixture.redCheck, on: [.cardBack])
        #expect(fixture.store.myCardSkin.source(for: .cardBack) == .bundled("skin-navy_check-back"))
    }

    @Test("a verified purchase grants, finishes the transaction and downloads")
    func purchase() async {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.store.purchase(ProductIDs.single("red_check"))

        #expect(fixture.store.owns(.cardBack, of: Fixture.redCheck))
        #expect(fixture.purchases.finishedTransactions == [ProductIDs.single("red_check")])
        #expect(fixture.purchases.purchasedTokens == [fixture.token])
        #expect(fixture.store.installed.contains(AssetKey(item: "red_check", slot: .cardBack)))
        #expect(fixture.store.purchaseStates.isEmpty)
    }

    @Test("a bought card back shows as owned at once, even before StoreKit lists it")
    func purchaseBeforeListed() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.listsPurchasesImmediately = false

        await fixture.store.purchase(ProductIDs.single("red_check"))

        #expect(fixture.store.owns(.cardBack, of: Fixture.redCheck))
        #expect(fixture.store.installed.contains(AssetKey(item: "red_check", slot: .cardBack)))
    }

    @Test("a bought set unlocks and downloads every card at once, even before StoreKit lists it")
    func setPurchaseBeforeListed() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.listsPurchasesImmediately = false

        await fixture.store.purchase(ProductIDs.set("spanish_001"))

        #expect(fixture.store.ownsAll(of: Fixture.spanish))
        #expect(fixture.store.installed.count == 52)
    }

    @Test("a purchase is equipped on every slot it covers")
    func purchaseEquips() async {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.store.purchase(ProductIDs.set("spanish_001"))

        #expect(fixture.store.isShowing(Fixture.spanish, in: ace))
        #expect(fixture.store.myCardSkin.source(for: king) == .file(URL(filePath: "/skins/spanish_001/front.Kd.png"), fallback: "skin-default-front-Kd"))
    }

    @Test("a completed purchase is announced once, with what it unlocked")
    func purchaseAnnounced() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.store.purchase(ProductIDs.single("red_check"))

        let unlock = try #require(fixture.store.lastUnlock)
        #expect(unlock.productID == ProductIDs.single("red_check"))
        #expect(unlock.items.map(\.id) == [Fixture.redCheck.id])
        fixture.store.acknowledgeUnlock()
        #expect(fixture.store.lastUnlock == nil)
    }

    @Test("a cancelled, failed or pending purchase announces nothing")
    func nothingAnnounced() async {
        let fixture = Fixture()
        await fixture.store.start()
        for outcome in [FakePurchases.PurchaseOutcomeScript.cancel, .fail, .pending] {
            fixture.purchases.nextOutcome = outcome
            await fixture.store.purchase(ProductIDs.single("red_check"))
        }
        #expect(fixture.store.lastUnlock == nil)
    }

    @Test("an approved update grants at once, even before StoreKit lists it")
    func updateBeforeListed() async {
        let fixture = Fixture()
        await fixture.store.start()
        let observing = Task { await fixture.store.observeTransactions() }
        defer { observing.cancel() }

        fixture.purchases.deliverUpdate(productID: ProductIDs.single("red_check"))

        #expect(await eventually { fixture.store.owns(.cardBack, of: Fixture.redCheck) })
        #expect(await eventually { fixture.store.installed.contains(AssetKey(item: "red_check", slot: .cardBack)) })
    }

    @Test("a refund revokes a purchase StoreKit had not listed yet")
    func refundBeforeListed() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.listsPurchasesImmediately = false
        await fixture.store.purchase(ProductIDs.single("red_check"))
        let observing = Task { await fixture.store.observeTransactions() }
        defer { observing.cancel() }

        fixture.purchases.deliverUpdate(productID: ProductIDs.single("red_check"), isRevoked: true)

        #expect(await eventually { !fixture.store.owns(.cardBack, of: Fixture.redCheck) })
    }

    @Test("Ask to Buy leaves the purchase pending until the App Store approves it")
    func pending() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.nextOutcome = .pending

        await fixture.store.purchase(ProductIDs.single("red_check"))
        #expect(fixture.store.purchaseStates[ProductIDs.single("red_check")] == .pending)
        #expect(!fixture.store.owns(.cardBack, of: Fixture.redCheck))

        let observing = Task { await fixture.store.observeTransactions() }
        defer { observing.cancel() }
        fixture.purchases.entitlements.insert(ProductIDs.single("red_check"))
        fixture.purchases.deliverUpdate(productID: ProductIDs.single("red_check"))
        #expect(await eventually { fixture.store.owns(.cardBack, of: Fixture.redCheck) })
        #expect(await eventually { fixture.purchases.finishedTransactions == [ProductIDs.single("red_check")] })
    }

    @Test("cancelling clears the state and a failure is reported")
    func cancelAndFail() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.nextOutcome = .cancel
        await fixture.store.purchase(ProductIDs.single("red_check"))
        #expect(fixture.store.purchaseStates.isEmpty)

        fixture.purchases.nextOutcome = .fail
        await fixture.store.purchase(ProductIDs.single("red_check"))
        #expect({
            if case .failed = fixture.store.purchaseStates[ProductIDs.single("red_check")] { return true }
            return false
        }())
    }

    @Test("a refund reverts the card to the default without touching the loadout")
    func refund() async {
        let fixture = Fixture()
        fixture.purchases.entitlements = [ProductIDs.single("red_check")]
        await fixture.store.start()
        fixture.store.equip(Fixture.redCheck, on: [.cardBack])
        #expect(fixture.store.isShowing(Fixture.redCheck, in: .cardBack))

        let observing = Task { await fixture.store.observeTransactions() }
        defer { observing.cancel() }
        fixture.purchases.entitlements = []
        fixture.purchases.deliverUpdate(productID: ProductIDs.single("red_check"), isRevoked: true)

        #expect(await eventually { fixture.store.myCardSkin.source(for: .cardBack) == .bundled("skin-navy_check-back") })
        #expect(fixture.loadout.loadout[.cardBack] == "red_check", "it comes back if the player buys it again")
    }

    @Test("an opponent we know nothing about is drawn with the defaults")
    func unknownOpponent() {
        #expect(Fixture().store.opponentCardSkin(nil) == .standard)
    }

    @Test("an opponent's skin shows only where this device has the files")
    func knownOpponent() async {
        let fixture = Fixture(preinstalled: [AssetKey(item: "red_check", slot: .cardBack)])
        await fixture.store.start()
        let skin = fixture.store.opponentCardSkin(["back": "red_check", "front.As": "spanish_001"])
        #expect(skin.source(for: .cardBack) == .file(URL(filePath: "/skins/red_check/back.png"), fallback: "skin-navy_check-back"))
        #expect(skin.source(for: ace) == .bundled("skin-default-front-As"))
    }

    @Test("a storefront change reloads prices")
    func storefront() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.catalogProducts = [FakePurchases.product(ProductIDs.single("red_check"), price: "19")]
        let observing = Task { await fixture.store.observeStorefront() }
        defer { observing.cancel() }
        fixture.purchases.changeStorefront(to: "MEX")
        #expect(await eventually { fixture.store.product(ProductIDs.single("red_check"))?.price == Decimal(19) })
    }

    @Test("restore re-syncs with the App Store and downloads what came back")
    func restore() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.purchases.entitlements = [ProductIDs.set("spanish_001")]
        await fixture.store.restorePurchases()
        #expect(fixture.purchases.syncCount == 1)
        #expect(fixture.store.installed.count == 52)
        #expect(!fixture.store.isRestoring)
    }

    @Test("items of kinds this build cannot draw are not offered")
    func unsupportedKinds() async {
        let mat = SkinItem(id: "felt_green", kind: .mat, productID: "fap.skin.felt_green", assets: [.mat: SkinCatalogBuilder.asset("felt_green", .mat)])
        let fixture = Fixture(remote: .success(SkinCatalogBuilder().with(mat).build()))
        await fixture.store.start()
        #expect(fixture.store.catalog.item("felt_green") == nil)
    }

    @Test("purchases turned off on the device are reported once the store starts")
    func paymentsDisabled() async {
        let fixture = Fixture()
        fixture.purchases.canMakePayments = false
        await fixture.store.start()
        #expect(!fixture.store.canMakePayments)
    }

    @Test("a product id finds the catalog item it unlocks")
    func itemForProduct() async {
        let fixture = Fixture()
        await fixture.store.start()
        #expect(fixture.store.item(forProduct: ProductIDs.set("spanish_001"))?.id == "spanish_001")
        #expect(fixture.store.item(forProduct: "fap.skin.unknown") == nil)
    }
}
