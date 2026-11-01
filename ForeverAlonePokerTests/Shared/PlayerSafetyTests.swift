import Foundation
import SwiftData
import Testing
import PokerCore
@testable import ForeverAlonePoker

@MainActor
private struct Fixture {
    let container: ModelContainer
    let identity: IdentityStore

    init() throws {
        container = try Persistence.inMemoryContainer()
        identity = try IdentityStore(context: container.mainContext, defaultCountryCode: "MX")
    }
}

private func summary(_ playerID: String, _ name: String, countryCode: String = "", avatarID: String? = nil) -> PlayerSummary {
    PlayerSummary(
        seat: .two, playerID: playerID, name: name, countryCode: countryCode, avatarID: avatarID, stack: 0, streetCommitted: 0,
        hasFolded: false, isAllIn: false, isReady: false, isConnected: true, isRanked: false, isBusted: false, place: nil
    )
}

// MARK: - Block list

@Suite("BlockList")
@MainActor
struct BlockListTests {
    @Test("a blocked player is remembered and can be unblocked")
    func blockAndUnblock() throws {
        let container = try Persistence.inMemoryContainer()
        let list = BlockList(context: container.mainContext)
        list.block(playerID: "bruno", name: "Bruno")
        #expect(list.isBlocked("bruno"))
        #expect(BlockList(context: container.mainContext).blockedIDs == ["bruno"], "persisted")

        list.unblock(playerID: "bruno")
        #expect(!list.isBlocked("bruno"))
    }

    @Test("blocking twice keeps one entry")
    func idempotent() throws {
        let container = try Persistence.inMemoryContainer()
        let list = BlockList(context: container.mainContext)
        list.block(playerID: "bruno", name: "Bruno")
        list.block(playerID: "bruno", name: "Bruno")
        #expect(list.players.count == 1)
    }

    @Test("a blocked player's name is hidden at the table")
    func shownName() {
        let bruno = summary("bruno", "Bruno")
        #expect(bruno.shownName(hiding: []) == "Bruno")
        #expect(bruno.shownName(hiding: ["bruno"]) == "Blocked player")
    }

    @Test("a blocked player's picture is replaced by initials")
    func shownAvatar() {
        let bruno = summary("bruno", "Bruno", avatarID: "avatar_seal")
        #expect(bruno.shownAvatarID(hiding: []) == "avatar_seal")
        #expect(bruno.shownAvatarID(hiding: ["bruno"]) == nil)
    }

    @Test("a blocked player's country flag is hidden")
    func shownCountry() {
        let bruno = summary("bruno", "Bruno", countryCode: "MX")
        #expect(bruno.shownCountryCode(hiding: []) == "MX")
        #expect(bruno.shownCountryCode(hiding: ["bruno"]) == "")
    }
}

// MARK: - Profile

@Suite("ProfileSafetyModel")
@MainActor
struct ProfileSafetyModelTests {
    @Test("a name the policy rejects is explained and not saved")
    func policyRejects() throws {
        let fixture = try Fixture()
        let model = ProfileSafetyModel(identity: fixture.identity)
        #expect(model.commitName("sh1t") == nil)
        #expect(model.nameError == "That name isn't allowed. Choose another one.")
        #expect(fixture.identity.profile.displayName == "Player")
    }

    @Test("a name the policy accepts is saved normalized")
    func accepts() throws {
        let fixture = try Fixture()
        let model = ProfileSafetyModel(identity: fixture.identity)
        #expect(model.commitName("  Ana   Lucía ") == "Ana Lucía")
        #expect(fixture.identity.profile.displayName == "Ana Lucía")
        #expect(model.nameError == nil)
    }
}

// MARK: - Reports

@Suite("Report by email")
struct ReportMailTests {
    @Test("a report names the player, their id and the room")
    func reportMail() throws {
        let url = SupportContact.mailURL(.report(playerID: "bruno-1", name: "Bruno", roomCode: "ABC234"), appVersion: "1.2", system: "iOS 27.0")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let body = try #require(components.queryItems?.first { $0.name == "body" }?.value)

        #expect(components.queryItems?.first { $0.name == "subject" }?.value == "ForeverAlonePoker report: Bruno")
        #expect(body.contains("Reported player: Bruno (bruno-1)"))
        #expect(body.contains("Room: ABC234"))
        #expect(body.contains("App 1.2, iOS 27.0"))
    }
}
