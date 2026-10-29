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

/// How cards and chips look for one viewer, fully resolved (tdr/0011,
/// tdr/0027). A plain value put in the environment: card and chip views read
/// it and never see catalogs,
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
/// "skin-default-front-As", "skin-navy_check-back" and
/// "skin-classic_chips-chips-100-top-small".
nonisolated enum BundledSkin {
    static func imageName(for slot: CosmeticSlot) -> String {
        let item = switch slot.kind {
        case .cardBack: SkinCatalog.defaultBackID
        case .chips: SkinCatalog.defaultChipsID
        default: SkinCatalog.defaultFrontID
        }
        return AssetNaming.bundledImageName(item: item, slot: slot)
    }
}

extension EnvironmentValues {
    /// The skin card and chip views draw with. The app root sets the player's own; the
    /// table overrides it for the opponent's seat.
    @Entry var cardSkin: CardSkin = .standard
}
