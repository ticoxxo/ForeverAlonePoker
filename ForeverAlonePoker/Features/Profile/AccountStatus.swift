import Foundation

/// What Profile says about the player's two separate accounts (tdr/0033): the
/// device's iCloud account, which only Settings can change, and the optional
/// Sign in with Apple that opts into ranked play.
struct AccountStatus: Equatable {
    let isSignedIntoCloud: Bool
    let isRanked: Bool

    /// - Parameter tier: only says whether the player is ranked; it hides the
    ///   iCloud state of a ranked player, so that comes from `isCloudSyncEnabled`.
    init(isCloudSyncEnabled: Bool, tier: IdentityStore.Tier) {
        isSignedIntoCloud = isCloudSyncEnabled
        isRanked = tier == .ranked
    }

    var cloudLabel: String {
        isSignedIntoCloud ? String(localized: "Signed in") : String(localized: "Not signed in")
    }

    var cloudSymbol: String {
        isSignedIntoCloud ? "checkmark.icloud.fill" : "icloud.slash"
    }

    var cloudFooter: String {
        isSignedIntoCloud
            ? String(localized: "Your profile and history sync through iCloud.")
            : String(localized: "Your profile and history are stored on this device. Sign into iCloud in Settings to sync them.")
    }

    var rankedFooter: String {
        isRanked
            ? String(localized: "Online matches against other signed-in players count toward the world and country leaderboards.")
            : String(localized: "Optional. Play ranked matches and appear on the leaderboard.")
    }
}
