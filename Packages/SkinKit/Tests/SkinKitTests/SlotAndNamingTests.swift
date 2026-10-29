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
    @Test("sets and single items follow one scheme")
    func scheme() {
        #expect(ProductIDs.set("spanish_001") == "fap.skin.spanish_001.set")
        #expect(ProductIDs.single("red_check") == "fap.skin.red_check")
    }

    @Test("a set is sold as one product, never card by card")
    func allForSet() {
        #expect(ProductIDs.all(for: SkinCatalogBuilder.cardSet("spanish_001")) == ["fap.skin.spanish_001.set"])
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

@Suite("Chip slots")
struct ChipSlotTests {
    @Test("a chip slot is keyed by value, face and size, and has the chips kind")
    func key() {
        let slot = CosmeticSlot.chip(.init(100), face: .top, size: .small)
        #expect(slot.rawValue == "chips.100.top.small")
        #expect(slot.kind == .chips)
        #expect(slot.card == nil)
    }

    @Test("there is one chip slot per denomination, face and size")
    func allChips() {
        let expected = ChipDenomination.all.count * ChipFace.allCases.count * ChipSize.allCases.count
        #expect(CosmeticSlot.allChips.count == expected)
        #expect(Set(CosmeticSlot.allChips).count == expected)
        #expect(CosmeticSlot.allChips.allSatisfy { $0.kind == .chips })
    }

    @Test("denominations are multiples of 10 from 10 to 100,000, ascending")
    func ladder() {
        let values = ChipDenomination.all.map(\.value)
        #expect(values.first == 10)
        #expect(values.last == 100_000)
        #expect(values == values.sorted())
        #expect(values.allSatisfy { $0 % 10 == 0 })
    }

    @Test("an amount shows the largest chip it covers, and never less than the smallest")
    func showing() {
        #expect(ChipDenomination.showing(0).value == 10)
        #expect(ChipDenomination.showing(9).value == 10)
        #expect(ChipDenomination.showing(10).value == 10)
        #expect(ChipDenomination.showing(49).value == 10)
        #expect(ChipDenomination.showing(50).value == 50)
        #expect(ChipDenomination.showing(1_234).value == 1_000)
        #expect(ChipDenomination.showing(250_000).value == 100_000)
    }
}

@Suite("Chip asset naming")
struct ChipAssetNamingTests {
    @Test("default chips belong to the classic set; files without a size suffix are small")
    func defaults() throws {
        let small = try #require(AssetNaming.parseChip(fileStem: "chip_red_top"))
        #expect(small.item == SkinCatalog.defaultChipsID)
        #expect(small.slot == .chip(ChipDenomination.color("red")!, face: .top, size: .small))
        let large = try #require(AssetNaming.parseChip(fileStem: "chip_red_flat_large"))
        #expect(large.slot == .chip(ChipDenomination.color("red")!, face: .flat, size: .large))
    }

    @Test("premium chips belong to their numbered set; a copy is the large file")
    func premium() throws {
        let small = try #require(AssetNaming.parseChip(fileStem: "premium_01_chip_blue_flat"))
        #expect(small.item == "premium_01_chips")
        #expect(small.slot == .chip(ChipDenomination.color("blue")!, face: .flat, size: .small))
        let large = try #require(AssetNaming.parseChip(fileStem: "premium_01_chip_blue_top copy"))
        #expect(large.slot == .chip(ChipDenomination.color("blue")!, face: .top, size: .large))
    }

    @Test("every color maps to a different denomination")
    func colors() {
        let colors = ["white", "red", "blue", "lightblue", "green", "black", "purple", "yellow", "pink", "biege", "gray"]
        let values = colors.compactMap { ChipDenomination.color($0)?.value }
        #expect(values.count == colors.count)
        #expect(Set(values).count == colors.count)
        #expect(ChipDenomination.color("beige") == ChipDenomination.color("biege"))
    }

    @Test("unknown colors, faces and other files are ignored")
    func ignored() {
        #expect(AssetNaming.parseChip(fileStem: "chip_teal_top") == nil)
        #expect(AssetNaming.parseChip(fileStem: "chip_red_side") == nil)
        #expect(AssetNaming.parseChip(fileStem: "spades_10_spanish_001") == nil)
        #expect(AssetNaming.parse(fileStem: "chip_red_top") == nil)
    }

    @Test("published chip files are named after the slot")
    func fileName() {
        #expect(AssetNaming.fileName(for: .chip(.init(500), face: .flat, size: .large)) == "chips.500.flat.large.png")
    }

    @Test("bundled defaults are named after their item and slot")
    func bundledImageName() {
        #expect(AssetNaming.bundledImageName(item: "navy_check", slot: .cardBack) == "skin-navy_check-back")
        #expect(AssetNaming.bundledImageName(item: "default", slot: .cardFront(card("As"))) == "skin-default-front-As")
        #expect(AssetNaming.bundledImageName(item: SkinCatalog.defaultChipsID, slot: .chip(.init(100), face: .top, size: .small))
            == "skin-classic_chips-chips-100-top-small")
    }

    @Test("a chip set is sold whole")
    func productID() {
        #expect(ProductIDs.all(for: SkinCatalogBuilder.chipSet("premium_01_chips")) == ["fap.skin.premium_01_chips.set"])
    }
}
