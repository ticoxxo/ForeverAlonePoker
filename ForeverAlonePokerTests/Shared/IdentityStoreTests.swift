import Foundation
import SwiftData
import Testing
import PokerCore
import SkinKit
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

    @Test("a multiway finish keeps the place and the table size")
    func recordsPlace() throws {
        let fixture = try Fixture()
        let store = fixture.store
        store.record(MatchSummary(
            didWin: false, opponentName: "Bob, Carol and Dave", myFinalStack: 0,
            opponentFinalStack: 6000, handsPlayed: 40, place: 3, playerCount: 4
        ), mode: .local)
        #expect(store.recentMatches.first?.place == 3)
        #expect(store.recentMatches.first?.playerCount == 4)
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

    @Test("the identity carries the country so opponents and leaderboards can show it")
    func identityCountry() throws {
        let fixture = try Fixture(country: "MX")
        #expect(fixture.store.identity.countryCode == "MX")
        fixture.store.updateCountryCode("AR")
        #expect(fixture.store.identity.countryCode == "AR")
    }

    @Test("linking an Apple account makes the Apple user id the player's identity and keeps the token")
    func linkApple() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let localID = store.profile.localID.uuidString
        #expect(store.rankedSessionToken == nil)
        #expect(store.publicProfileSnapshot == nil)

        store.linkAppleAccount(userID: "001234.abc", sessionToken: "session-1")
        #expect(store.tier == .ranked)
        #expect(store.identity.id == "001234.abc")
        #expect(store.rankedSessionToken == "session-1")
        #expect(store.publicProfileSnapshot == PublicProfileSnapshot(playerID: "001234.abc", displayName: "Player", countryCode: "MX", avatar: nil))

        store.unlinkAppleAccount()
        #expect(store.tier == .local)
        #expect(store.identity.id == localID)
        #expect(store.rankedSessionToken == nil)
        #expect(store.recentMatches.isEmpty, "history untouched")
    }

    @Test("the newest online match is marked ranked when the server rates it")
    func markRanked() throws {
        let fixture = try Fixture()
        let store = fixture.store
        store.record(MatchSummary(didWin: true, opponentName: "Bob", myFinalStack: 3000, opponentFinalStack: 0, handsPlayed: 3), mode: .online)
        store.record(MatchSummary(didWin: true, opponentName: "Ann", myFinalStack: 3000, opponentFinalStack: 0, handsPlayed: 3), mode: .local)
        store.markLatestOnlineMatchRanked()
        #expect(store.recentMatches.first(where: { $0.mode == .online })?.wasRanked == true)
        #expect(store.recentMatches.first(where: { $0.mode == .local })?.wasRanked == false)
    }

    @Test("profiles created on two devices before their first sync merge into the oldest")
    func mergesDuplicateProfiles() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let context = fixture.container.mainContext
        store.record(MatchSummary(didWin: true, opponentName: "Bob", myFinalStack: 3000, opponentFinalStack: 0, handsPlayed: 3), mode: .local)

        // What a CloudKit import of the other device's rows looks like.
        let other = PlayerProfile(displayName: "Other device", countryCode: "US")
        other.createdAt = store.profile.createdAt.addingTimeInterval(60)
        other.appleUserID = "001234.abc"
        other.rankedSessionToken = "session-1"
        context.insert(other)
        let theirMatch = MatchRecord(mode: .online, opponentName: "Carol", didWin: false, finalStack: 0, opponentFinalStack: 3000, handsPlayed: 9)
        theirMatch.profile = other
        context.insert(theirMatch)
        try context.save()

        let keeperID = store.profile.localID
        store.refresh()
        #expect(try context.fetchCount(FetchDescriptor<PlayerProfile>()) == 1)
        #expect(store.profile.localID == keeperID)
        #expect(store.profile.displayName == "Player", "the older profile keeps its details")
        #expect(store.profile.appleUserID == "001234.abc", "but adopts the ranked identity")
        #expect(store.rankedSessionToken == "session-1")
        #expect(store.recentMatches.count == 2)
        #expect(store.recentMatches.allSatisfy { $0.profile?.localID == keeperID })
    }

    @Test("the skin loadout is stored on the profile and stamped")
    func loadout() throws {
        let fixture = try Fixture()
        let store = fixture.store
        #expect(store.loadout == Loadout())
        var loadout = Loadout()
        loadout[.cardBack] = "red_check"
        store.updateLoadout(loadout)
        #expect(store.loadout == loadout)
        #expect(store.profile.cosmeticLoadoutUpdatedAt > .distantPast)
        let reopened = try IdentityStore(context: fixture.container.mainContext)
        #expect(reopened.loadout[.cardBack] == "red_check")
    }

    @Test("merging duplicate profiles keeps the most recently changed loadout")
    func mergesNewestLoadout() throws {
        let fixture = try Fixture()
        let context = fixture.container.mainContext
        let duplicate = PlayerProfile(displayName: "Other device")
        duplicate.createdAt = fixture.store.profile.createdAt.addingTimeInterval(60)
        var loadout = Loadout()
        loadout[.cardBack] = "red_rosette"
        duplicate.cosmeticLoadout = try JSONEncoder().encode(loadout)
        duplicate.cosmeticLoadoutUpdatedAt = Date()
        context.insert(duplicate)
        try context.save()

        fixture.store.refresh()

        #expect(fixture.store.loadout[.cardBack] == "red_rosette")
        #expect(try context.fetchCount(FetchDescriptor<PlayerProfile>()) == 1)
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
