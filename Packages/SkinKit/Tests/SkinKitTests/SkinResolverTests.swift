import Testing
import PokerCore
import PokerCoreTestSupport
@testable import SkinKit
import SkinKitTestSupport

@Suite("SkinResolver")
struct SkinResolverTests {
    private let ace = CosmeticSlot.cardFront(card("As"))
    private let king = CosmeticSlot.cardFront(card("Kd"))
    private let resolver = SkinResolver(catalog: SkinCatalog.builtIn.merging(
        SkinCatalogBuilder()
            .with(SkinCatalogBuilder.cardSet("spanish_001", sellsSingleCards: true))
            .with(SkinCatalogBuilder.back("red_check"))
            .build()
    ))
    private let spanishInstalled = InstalledAssets.all(of: SkinCatalogBuilder.cardSet("spanish_001"))
        .union(InstalledAssets.all(of: SkinCatalogBuilder.back("red_check")))

    @Test("with nothing selected every slot is the default")
    func emptyLoadout() {
        let resolved = resolver.resolve(ace, loadout: Loadout(), ownership: .none, installed: [])
        #expect(resolved?.item.id == SkinCatalog.defaultFrontID)
        #expect(resolved?.isDefault == true)
        #expect(resolver.resolve(.cardBack, loadout: Loadout(), ownership: .none, installed: [])?.item.id == SkinCatalog.defaultBackID)
    }

    @Test("an owned, installed selection is shown")
    func ownedSet() {
        let loadout = LoadoutBuilder().equip("spanish_001", on: [ace]).build()
        let ownership = Ownership(productIDs: [ProductIDs.set("spanish_001")])
        let resolved = resolver.resolve(ace, loadout: loadout, ownership: ownership, installed: spanishInstalled)
        #expect(resolved?.item.id == "spanish_001")
        #expect(resolved?.isDefault == false)
    }

    @Test("a single card purchase unlocks only that card")
    func singleCard() {
        let loadout = LoadoutBuilder().equip("spanish_001", on: [ace, king]).build()
        let ownership = Ownership(productIDs: [ProductIDs.card("spanish_001", card("As"))])
        #expect(resolver.resolve(ace, loadout: loadout, ownership: ownership, installed: spanishInstalled)?.item.id == "spanish_001")
        #expect(resolver.resolve(king, loadout: loadout, ownership: ownership, installed: spanishInstalled)?.item.id == SkinCatalog.defaultFrontID)
    }

    @Test("a selection that is not owned, for example after a refund, falls back to the default")
    func notOwned() {
        let loadout = LoadoutBuilder().equip("red_check", on: [.cardBack]).build()
        #expect(resolver.resolve(.cardBack, loadout: loadout, ownership: .none, installed: spanishInstalled)?.item.id == SkinCatalog.defaultBackID)
    }

    @Test("an owned selection whose files are missing falls back to the default")
    func notInstalled() {
        let loadout = LoadoutBuilder().equip("red_check", on: [.cardBack]).build()
        let ownership = Ownership(productIDs: [ProductIDs.single("red_check")])
        #expect(resolver.resolve(.cardBack, loadout: loadout, ownership: ownership, installed: [])?.item.id == SkinCatalog.defaultBackID)
    }

    @Test("an item missing from the catalog or of the wrong kind falls back to the default")
    func unknownOrWrongKind() {
        let loadout = LoadoutBuilder()
            .equip("retired_999", on: [ace])
            .equip("red_check", on: [king])
            .build()
        #expect(resolver.resolve(ace, loadout: loadout, ownership: .everything, installed: spanishInstalled)?.isDefault == true)
        #expect(resolver.resolve(king, loadout: loadout, ownership: .everything, installed: spanishInstalled)?.isDefault == true)
    }

    @Test("an opponent's skin is shown only when this device already has its files")
    func opponent() {
        let opponent = Loadout(wire: ["back": "red_check", "front.As": "spanish_001"])
        #expect(resolver.resolve(.cardBack, loadout: opponent, ownership: .everything, installed: spanishInstalled)?.item.id == "red_check")
        #expect(resolver.resolve(ace, loadout: opponent, ownership: .everything, installed: [])?.isDefault == true)
    }

    @Test("a slot kind with no default has nothing to show")
    func noDefault() {
        #expect(resolver.resolve(.mat, loadout: Loadout(), ownership: .everything, installed: []) == nil)
    }

    @Test("owned slots of a set reflect set and single card purchases")
    func ownedSlots() {
        let set = SkinCatalogBuilder.cardSet("spanish_001", sellsSingleCards: true)
        #expect(Ownership.none.ownedSlots(of: set).isEmpty)
        #expect(Ownership(productIDs: [ProductIDs.card("spanish_001", card("As"))]).ownedSlots(of: set) == [ace])
        #expect(Ownership(productIDs: [ProductIDs.set("spanish_001")]).ownedSlots(of: set).count == 52)
    }
}
