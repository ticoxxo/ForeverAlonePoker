import Foundation
import Testing
@testable import ForeverAlonePoker

@MainActor
struct AccountStatusTests {
    @Test func signedIntoICloudShowsTheCheckmark() {
        let status = AccountStatus(isCloudSyncEnabled: true, tier: .iCloud)

        #expect(status.isSignedIntoCloud)
        #expect(status.cloudLabel == String(localized: "Signed in"))
        #expect(status.cloudSymbol == "checkmark.icloud.fill")
        #expect(status.cloudFooter == String(localized: "Your profile and history sync through iCloud."))
    }

    @Test func notSignedIntoICloudPointsToSettings() {
        let status = AccountStatus(isCloudSyncEnabled: false, tier: .local)

        #expect(!status.isSignedIntoCloud)
        #expect(status.cloudLabel == String(localized: "Not signed in"))
        #expect(status.cloudSymbol == "icloud.slash")
        #expect(status.cloudFooter == String(localized: "Your profile and history are stored on this device. Sign into iCloud in Settings to sync them."))
    }

    @Test func rankedPlayerWithICloudStillReportsSignedIn() {
        let status = AccountStatus(isCloudSyncEnabled: true, tier: .ranked)

        #expect(status.isSignedIntoCloud)
        #expect(status.isRanked)
    }

    @Test func rankedPlayerWithoutICloudReportsNotSignedIn() {
        let status = AccountStatus(isCloudSyncEnabled: false, tier: .ranked)

        #expect(!status.isSignedIntoCloud)
        #expect(status.isRanked)
    }

    @Test func iCloudAloneIsNotRanked() {
        #expect(!AccountStatus(isCloudSyncEnabled: true, tier: .iCloud).isRanked)
    }

    @Test func rankedFooterOffersRankedPlayUntilSignedIn() {
        let status = AccountStatus(isCloudSyncEnabled: true, tier: .iCloud)

        #expect(status.rankedFooter == String(localized: "Optional. Play ranked matches and appear on the leaderboard."))
    }

    @Test func rankedFooterExplainsWhatCountsOnceSignedIn() {
        let status = AccountStatus(isCloudSyncEnabled: true, tier: .ranked)

        #expect(status.rankedFooter == String(localized: "Online matches against other signed-in players count toward the world and country leaderboards."))
    }
}
