import Foundation
import Testing
import SkinKit
import SkinKitTestSupport

@Suite("Avatar slot")
struct AvatarSlotTests {
    @Test("the profile picture is one slot of the avatar kind")
    func slot() {
        #expect(CosmeticSlot.avatar.rawValue == "avatar")
        #expect(CosmeticSlot.avatar.kind == .avatar)
    }

    @Test("bundled pictures are named after their item")
    func bundledName() {
        #expect(AssetNaming.bundledImageName(item: "avatar_seal", slot: .avatar) == "skin-avatar_seal-avatar")
    }
}

@Suite("Built-in avatars")
struct BuiltInAvatarTests {
    private var avatars: [SkinItem] { SkinCatalog.builtIn.items(of: .avatar) }

    @Test("eight pictures are free and six are sold one by one")
    func freeAndPremium() {
        let free = avatars.filter { $0.productID == nil }
        let premium = avatars.filter { $0.productID != nil }
        #expect(free.count == 8)
        #expect(premium.count == 6)
        #expect(premium.allSatisfy { $0.productID == ProductIDs.single($0.id) })
        #expect(premium.map(\.productID).contains("fap.skin.avatar_yellow_cat"))
        #expect(premium.map(\.productID).contains("fap.skin.avatar_girl"))
    }

    @Test("every picture is bundled, fills the avatar slot and none is a default")
    func bundled() {
        #expect(avatars.allSatisfy { $0.isBundled && $0.slots == [.avatar] && !$0.isDefault })
    }

    @Test("a server catalog never marks its items as bundled")
    func remoteNotBundled() throws {
        let decoded = try JSONDecoder().decode(SkinItem.self, from: Data(#"{"id":"x","kind":"avatar","isBundled":true}"#.utf8))
        #expect(!decoded.isBundled)
    }
}

@Suite("SkinResolver for avatars")
struct AvatarResolverTests {
    private let resolver = SkinResolver(catalog: SkinCatalog.builtIn)
    private func picking(_ id: SkinID) -> Loadout { LoadoutBuilder().equip(id, on: [.avatar]).build() }

    @Test("nothing picked shows no picture")
    func none() {
        #expect(resolver.resolve(.avatar, loadout: Loadout(), ownership: .none, installed: []) == nil)
    }

    @Test("a free picture shows without a purchase or a download")
    func free() {
        #expect(resolver.resolve(.avatar, loadout: picking("avatar_seal"), ownership: .none, installed: [])?.item.id == "avatar_seal")
    }

    @Test("a premium picture shows only once bought")
    func premium() {
        let loadout = picking("avatar_yellow_cat")
        #expect(resolver.resolve(.avatar, loadout: loadout, ownership: .none, installed: []) == nil)
        let owned = Ownership(productIDs: [ProductIDs.single("avatar_yellow_cat")])
        #expect(resolver.resolve(.avatar, loadout: loadout, ownership: owned, installed: [])?.item.id == "avatar_yellow_cat")
    }

    @Test("an unknown picture shows nothing")
    func unknown() {
        #expect(resolver.resolve(.avatar, loadout: picking("avatar_unknown"), ownership: .everything, installed: []) == nil)
    }
}
