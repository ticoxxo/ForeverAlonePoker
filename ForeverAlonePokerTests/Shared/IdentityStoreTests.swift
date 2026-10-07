import Foundation
import SwiftData
import Testing
import PokerCore
@testable import ForeverAlonePoker

/// Keeps the container alive for the duration of a test: a model whose
/// container has been released asserts on property access.
@MainActor
private struct Fixture {
    let container: ModelContainer
    let store: IdentityStore

    init(country: String = "MX") throws {
        container = try Persistence.inMemoryContainer()
        store = try IdentityStore(context: container.mainContext, defaultCountryCode: country)
    }
}

@Suite("IdentityStore")
@MainActor
struct IdentityStoreTests {
    @Test("first launch creates a default user with the device country")
    func createsDefaultUser() throws {
        let fixture = try Fixture(country: "MX")
        let store = fixture.store
        #expect(store.profile.displayName == "Player")
        #expect(store.profile.countryCode == "MX")
        #expect(store.profile.appleUserID == nil)
        #expect(store.tier == .local)
        #expect(store.identity.displayName == "Player")
        #expect(store.identity.id == store.profile.localID.uuidString)
    }

    @Test("the same store reopens the same user instead of creating another")
    func reopensExistingUser() throws {
        let fixture = try Fixture()
        fixture.store.updateDisplayName("Ana")
        let second = try IdentityStore(context: fixture.container.mainContext, defaultCountryCode: "US")
        #expect(second.profile.localID == fixture.store.profile.localID)
        #expect(second.profile.displayName == "Ana")
        #expect(second.profile.countryCode == "MX", "existing profile is not overwritten")
        #expect(try fixture.container.mainContext.fetchCount(FetchDescriptor<PlayerProfile>()) == 1)
    }

    @Test("edits are trimmed and persisted")
    func edits() throws {
        let fixture = try Fixture()
        let store = fixture.store
        store.updateDisplayName("  Ana  ")
        #expect(store.profile.displayName == "Ana")
        store.updateDisplayName("   ")
        #expect(store.profile.displayName == "Ana", "blank names are ignored")
        store.updateCountryCode("AR")
        #expect(store.profile.countryCode == "AR")
        store.updateAvatar(Data([1, 2, 3]))
        #expect(store.profile.avatar == Data([1, 2, 3]))
    }

    @Test("finished matches are recorded newest first and counted")
    func recordsMatches() throws {
        let fixture = try Fixture()
        let store = fixture.store
        store.record(MatchSummary(didWin: true, opponentName: "Bob", myFinalStack: 3000, opponentFinalStack: 0, handsPlayed: 12), mode: .local)
        store.record(MatchSummary(didWin: false, opponentName: "Carol", myFinalStack: 0, opponentFinalStack: 3000, handsPlayed: 7), mode: .practice)

        #expect(store.recentMatches.count == 2)
        #expect(store.recentMatches.first?.opponentName == "Carol")
        #expect(store.recentMatches.first?.mode == .practice)
        #expect(store.recentMatches.last?.didWin == true)
        #expect(store.recentMatches.first?.profile?.localID == store.profile.localID)
        #expect(store.wins == 1)
        #expect(store.losses == 1)
    }

    @Test("ranked tier follows the Apple user id")
    func tier() throws {
        let fixture = try Fixture()
        let store = fixture.store
        store.isCloudSyncEnabled = true
        #expect(store.tier == .iCloud)
        store.profile.appleUserID = "sub-123"
        #expect(store.tier == .ranked)
    }
}

@Suite("CountryFlag")
struct CountryFlagTests {
    @Test("two-letter codes become regional indicator flags", arguments: [("MX", "🇲🇽"), ("us", "🇺🇸"), ("JP", "🇯🇵")])
    func flags(code: String, expected: String) {
        #expect(CountryFlag.emoji(for: code) == expected)
    }

    @Test("anything else yields no flag", arguments: ["", "M", "MEX", "1X", "🇲🇽"])
    func invalid(code: String) {
        #expect(CountryFlag.emoji(for: code) == "")
    }

    @Test("region list contains only two-letter codes")
    func regions() {
        let codes = CountryFlag.allRegionCodes(locale: Locale(identifier: "en_US"))
        #expect(codes.contains("MX"))
        #expect(codes.allSatisfy { $0.count == 2 })
        #expect(CountryFlag.name(for: "MX", locale: Locale(identifier: "en_US")) == "Mexico")
    }
}
