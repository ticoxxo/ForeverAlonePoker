import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport

@Suite("Profile pictures on the wire")
struct AvatarWireTests {
    @Test("an identity round-trips with its profile picture")
    func roundTrip() throws {
        let decoded = try JSONDecoder().decode(PlayerIdentity.self, from: JSONEncoder().encode(TestPlayers.bobWithAvatar))
        #expect(decoded == TestPlayers.bobWithAvatar)
    }

    @Test("an identity without a picture still decodes")
    func noPicture() throws {
        let decoded = try JSONDecoder().decode(PlayerIdentity.self, from: Data(#"{"id":"bob-id","displayName":"Bob","countryCode":""}"#.utf8))
        #expect(decoded.avatarID == nil)
    }

    @Test("opponents see the picture a player sat down with")
    func seated() {
        var room = MatchRoomBuilder().build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        let out = room.handle(.join(TestPlayers.bobWithAvatar), from: TestPlayers.bobConnection)
        #expect(out.latestView(for: TestPlayers.aliceConnection)?.opponent?.avatarID == "avatar_seal")
    }

    @Test("an overlong picture id is dropped")
    func overlong() {
        var room = MatchRoomBuilder().build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        let bob = PlayerIdentity(id: "bob-id", displayName: "Bob", avatarID: String(repeating: "x", count: 100))
        let out = room.handle(.join(bob), from: TestPlayers.bobConnection)
        #expect(out.latestView(for: TestPlayers.aliceConnection)?.opponent?.avatarID == nil)
    }
}
