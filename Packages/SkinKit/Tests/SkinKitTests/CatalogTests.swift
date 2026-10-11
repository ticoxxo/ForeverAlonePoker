import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport
@testable import SkinKit
import SkinKitTestSupport

@Suite("SkinCatalog")
struct SkinCatalogTests {
    private let json = #"""
    {
      "schemaVersion": 1,
      "catalogVersion": 7,
      "publishedAt": "2026-10-11T00:00:00Z",
      "assetBaseURL": "/skins/",
      "items": [
        {
          "id": "spanish_001",
          "kind": "cardFront",
          "names": { "en": "Spanish", "es": "Española" },
          "productID": "fap.skin.spanish_001.set",
          "sellsSingleCards": true,
          "assets": { "front.As": { "path": "spanish_001/front.As.png", "sha256": "ab", "bytes": 10 } },
          "futureField": [1, 2, 3]
        },
        { "id": "felt_green", "kind": "mat", "assets": {} },
        { "id": "broken", "kind": 42 },
        { "id": "red_check", "kind": "cardBack", "minAppVersion": "9.0",
          "assets": { "back": { "path": "red_check/back.png", "sha256": "cd", "bytes": 5 } } }
      ]
    }
    """#

    @Test("unknown fields are ignored and malformed items are skipped, not fatal")
    func lenient() throws {
        let catalog = try SkinCatalog.decode(from: Data(json.utf8))
        #expect(catalog.catalogVersion == 7)
        #expect(catalog.items.map(\.id) == ["spanish_001", "felt_green", "red_check"])
        let spanish = try #require(catalog.item("spanish_001"))
        #expect(spanish.name(for: "es") == "Española")
        #expect(spanish.name(for: "fr") == "Spanish", "falls back to English")
        #expect(spanish.sellsSingleCards)
        #expect(spanish.assets[.cardFront(card("As"))]?.path == "spanish_001/front.As.png")
    }

    @Test("only kinds this build renders and items it is new enough for are offered")
    func availability() throws {
        let catalog = try SkinCatalog.decode(from: Data(json.utf8))
        let offered = catalog.available(kinds: [.cardFront, .cardBack], appVersion: AppVersion("1.0"))
        #expect(offered.items.map(\.id) == ["spanish_001"])
        let newer = catalog.available(kinds: [.cardFront, .cardBack], appVersion: AppVersion("9.1"))
        #expect(newer.items.map(\.id) == ["spanish_001", "red_check"])
    }

    @Test("a newer schema is refused rather than misread")
    func newerSchema() {
        let future = #"{"schemaVersion": 99, "catalogVersion": 1, "assetBaseURL": "/", "items": []}"#
        #expect(throws: SkinCatalog.DecodingFailure.unsupportedSchema(99)) {
            try SkinCatalog.decode(from: Data(future.utf8))
        }
    }

    @Test("encoding then decoding gives the same catalog")
    func roundTrip() throws {
        let catalog = SkinCatalogBuilder()
            .with(SkinCatalogBuilder.cardSet("spanish_001", sellsSingleCards: true))
            .with(SkinCatalogBuilder.back("red_check"))
            .build()
        let decoded = try SkinCatalog.decode(from: catalog.encoded())
        #expect(decoded == catalog)
    }

    @Test("built-in defaults always win over a remote item with the same id")
    func merging() {
        let remote = SkinCatalogBuilder()
            .with(SkinCatalogBuilder.cardSet("default", productID: "fap.skin.default.set"))
            .with(SkinCatalogBuilder.back("red_check"))
            .build()
        let merged = SkinCatalog.builtIn.merging(remote)
        #expect(merged.item("default")?.isDefault == true)
        #expect(merged.item("default")?.productID == nil)
        #expect(merged.item("red_check") != nil)
        #expect(merged.assetBaseURL == remote.assetBaseURL)
    }

    @Test("the built-in catalog has a free default for every card front and the back")
    func builtIn() throws {
        let builtIn = SkinCatalog.builtIn
        let front = try #require(builtIn.item(SkinCatalog.defaultFrontID))
        #expect(front.isDefault)
        #expect(front.slots.count == 52)
        let back = try #require(builtIn.item(SkinCatalog.defaultBackID))
        #expect(back.slots == [.cardBack])
    }
}

@Suite("Loadout")
struct LoadoutTests {
    @Test("encodes as a flat slot to skin dictionary")
    func flatJSON() throws {
        var loadout = Loadout()
        loadout[.cardBack] = "red_check"
        loadout[.cardFront(card("As"))] = "spanish_001"
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(loadout)) as? [String: String]
        #expect(object == ["back": "red_check", "front.As": "spanish_001"])
        #expect(try JSONDecoder().decode(Loadout.self, from: JSONEncoder().encode(loadout)) == loadout)
    }

    @Test("equipping a set covers the given slots and resetting removes them")
    func equipAndReset() {
        var loadout = Loadout()
        loadout.equip("spanish_001", on: CosmeticSlot.allCardFronts)
        #expect(loadout.count(of: "spanish_001") == 52)
        loadout.reset([.cardFront(card("As"))])
        #expect(loadout[.cardFront(card("As"))] == nil)
        #expect(loadout.count(of: "spanish_001") == 51)
    }

    @Test("the wire form round-trips and drops nothing it does not understand")
    func wire() {
        let loadout = Loadout(wire: ["back": "red_check", "mat": "felt_green"])
        #expect(loadout[.cardBack] == "red_check")
        #expect(loadout.wire == ["back": "red_check", "mat": "felt_green"])
    }
}
