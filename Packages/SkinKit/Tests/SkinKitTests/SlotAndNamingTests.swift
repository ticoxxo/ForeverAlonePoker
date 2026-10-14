import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport
@testable import SkinKit
import SkinKitTestSupport

@Suite("CosmeticSlot")
struct CosmeticSlotTests {
    @Test("a card front slot is keyed by the card's notation")
    func frontKey() {
        let slot = CosmeticSlot.cardFront(card("Ts"))
        #expect(slot.rawValue == "front.Ts")
        #expect(slot.kind == .cardFront)
        #expect(slot.card == card("Ts"))
    }

    @Test("the back slot has no card")
    func back() {
        #expect(CosmeticSlot.cardBack.rawValue == "back")
        #expect(CosmeticSlot.cardBack.kind == .cardBack)
        #expect(CosmeticSlot.cardBack.card == nil)
    }

    @Test("there is one front slot per card of the deck")
    func allFronts() {
        #expect(CosmeticSlot.allCardFronts.count == 52)
        #expect(Set(CosmeticSlot.allCardFronts).count == 52)
    }

    @Test("slots of kinds this build does not know keep their kind")
    func unknownKind() {
        #expect(CosmeticSlot(rawValue: "mat").kind == .mat)
        #expect(CosmeticSlot(rawValue: "chips.100").kind == CosmeticKind(rawValue: "chips"))
    }
}

@Suite("AssetNaming")
struct AssetNamingTests {
    @Test("artist file names map to the item and the card, with 10 as T")
    func faces() throws {
        let parsed = try #require(AssetNaming.parse(fileStem: "spades_10_spanish_001"))
        #expect(parsed.item == "spanish_001")
        #expect(parsed.slot == .cardFront(card("Ts")))
        #expect(AssetNaming.parse(fileStem: "hearts_A_default")?.slot == .cardFront(card("Ah")))
        #expect(AssetNaming.parse(fileStem: "clubs_2_default")?.slot == .cardFront(card("2c")))
    }

    @Test("card backs drop the back prefix and the default marker")
    func backs() {
        #expect(AssetNaming.parse(fileStem: "back_red_check")?.item == "red_check")
        #expect(AssetNaming.parse(fileStem: "back_navy_check_default")?.item == "navy_check")
        #expect(AssetNaming.parse(fileStem: "back_red_rosette")?.slot == .cardBack)
    }

    @Test("jokers and unknown files are ignored")
    func ignored() {
        #expect(AssetNaming.parse(fileStem: "joker_black_default") == nil)
        #expect(AssetNaming.parse(fileStem: "joker_red_spanish_001") == nil)
        #expect(AssetNaming.parse(fileStem: "default_set_preview") == nil)
        #expect(AssetNaming.parse(fileStem: "spades_1_default") == nil)
    }

    @Test("published files are named after the slot")
    func fileName() {
        #expect(AssetNaming.fileName(for: .cardFront(card("Qd"))) == "front.Qd.png")
        #expect(AssetNaming.fileName(for: .cardBack) == "back.png")
    }
}

@Suite("ProductIDs")
struct ProductIDsTests {
    @Test("sets, single cards and single items follow one scheme")
    func scheme() {
        #expect(ProductIDs.set("spanish_001") == "fap.skin.spanish_001.set")
        #expect(ProductIDs.card("spanish_001", card("Ts")) == "fap.skin.spanish_001.card.Ts")
        #expect(ProductIDs.single("red_check") == "fap.skin.red_check")
    }

    @Test("a set that sells single cards offers 53 products")
    func allForSet() {
        let item = SkinCatalogBuilder.cardSet("spanish_001", sellsSingleCards: true)
        let ids = ProductIDs.all(for: item)
        #expect(ids.count == 53)
        #expect(ids.first == "fap.skin.spanish_001.set")
        #expect(ids.contains("fap.skin.spanish_001.card.As"))
    }

    @Test("a free item has no products")
    func free() {
        #expect(ProductIDs.all(for: SkinCatalog.builtIn.items[0]).isEmpty)
    }
}

@Suite("AppVersion")
struct AppVersionTests {
    @Test("compares numerically, component by component")
    func ordering() {
        #expect(AppVersion("1.10") > AppVersion("1.9"))
        #expect(AppVersion("2") == AppVersion("2.0.0"))
        #expect(AppVersion("1.2.3") < AppVersion("1.3"))
    }
}

@Suite("SetPricing")
struct SetPricingTests {
    @Test("the set saves the difference over the cards still missing")
    func savings() {
        #expect(SetPricing.savings(setPrice: 0.99, cardPrice: 0.29, cardsRemaining: 52) == Decimal(string: "14.09"))
    }

    @Test("no savings when the remaining cards are cheaper than the set")
    func noSavings() {
        #expect(SetPricing.savings(setPrice: 0.99, cardPrice: 0.29, cardsRemaining: 3) == 0)
    }
}
