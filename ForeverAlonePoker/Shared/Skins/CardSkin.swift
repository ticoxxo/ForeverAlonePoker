import Foundation
import SwiftUI
import SkinKit

/// Where one slot's image comes from.
nonisolated enum SkinImageSource: Hashable, Sendable {
    /// An image set in the app's asset catalog (the free defaults).
    case bundled(String)
    /// A verified download on this device; `fallback` is the bundled image
    /// shown while it loads or if it cannot be read.
    case file(URL, fallback: String)
    /// Not on this device: store previews only.
    case remote(URL, fallback: String)
}

/// How cards look for one viewer, fully resolved (tdr/0011). A plain value
/// put in the environment: card views read it and never see catalogs,
/// ownership or StoreKit, and the game never sees it at all.
nonisolated struct CardSkin: Equatable, Sendable {
    private var overrides: [CosmeticSlot: SkinImageSource]

    init(overrides: [CosmeticSlot: SkinImageSource] = [:]) {
        self.overrides = overrides
    }

    /// Every slot shows the bundled default.
    static let standard = CardSkin()

    func source(for slot: CosmeticSlot) -> SkinImageSource {
        overrides[slot] ?? .bundled(BundledSkin.imageName(for: slot))
    }
}

/// Names of the default skin's image sets in `Assets.xcassets/Skins`, e.g.
/// "skin-default-front-As" and "skin-navy_check-back".
nonisolated enum BundledSkin {
    static func imageName(for slot: CosmeticSlot) -> String {
        let item = slot.kind == .cardBack ? SkinCatalog.defaultBackID : SkinCatalog.defaultFrontID
        return "skin-\(item.rawValue)-\(slot.rawValue.replacingOccurrences(of: ".", with: "-"))"
    }
}

extension EnvironmentValues {
    /// The skin card views draw with. The app root sets the player's own; the
    /// table overrides it for the opponent's seat.
    @Entry var cardSkin: CardSkin = .standard
}
