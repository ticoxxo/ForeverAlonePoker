import Foundation
import Testing
import PokerCore
@testable import ForeverAlonePoker

private func row(_ id: String, _ name: String, _ country: String, _ rating: Int) -> LeaderboardRow {
    LeaderboardRow(playerID: id, displayName: name, countryCode: country, rating: Rating(value: rating, matchesPlayed: 5), wins: 3, losses: 2)
}

private let ana = row("ana", "Ana", "MX", 1300)
private let bruno = row("bruno", "Bruno", "AR", 1250)
private let carla = row("carla", "Carla", "MX", 1100)
private let diego = row("diego", "Diego", "AR", 1050)

/// Serves a fixed table, filtering by country like CloudKit would.
private struct FakeLeaderboardService: LeaderboardService {
    var rows = [ana, bruno, carla, diego]
    var avatars: [String: Data] = ["ana": Data([1])]
    var fails = false

    func top(_ scope: LeaderboardScope, limit: Int) async throws -> [LeaderboardRow] {
        if fails { throw URLError(.notConnectedToInternet) }
        let scoped: [LeaderboardRow]
        switch scope {
        case .world: scoped = rows
        case .country(let code): scoped = rows.filter { $0.countryCode == code }
        }
        return Array(scoped.sorted { $0.rating > $1.rating }.prefix(limit))
    }

    func entry(for playerID: String) async throws -> LeaderboardRow? {
        rows.first { $0.playerID == playerID }
    }

    func avatars(for playerIDs: [String]) async throws -> [String: Data] {
        avatars.filter { playerIDs.contains($0.key) }
    }
}

@Suite("LeaderboardModel")
@MainActor
struct LeaderboardModelTests {
    @Test("loads the world top with ranks and avatars; a player inside the top is not pinned")
    func world() async {
        let model = LeaderboardModel(service: FakeLeaderboardService())
        await model.load(myPlayerID: "bruno")
        #expect(model.phase == .loaded)
        #expect(model.rows == [ana, bruno, carla, diego])
        #expect(model.rank(of: bruno) == 2)
        #expect(model.ownEntry == nil)
        #expect(model.avatars == ["ana": Data([1])])
    }

    @Test("a player outside the top is pinned with no rank")
    func pinnedOwnEntry() async {
        var service = FakeLeaderboardService()
        service.rows = (1...LeaderboardModel.limit).map { row("p\($0)", "P\($0)", "MX", 2000 - $0) } + [diego]
        let model = LeaderboardModel(service: service)
        await model.load(myPlayerID: "diego")
        #expect(model.rows.count == LeaderboardModel.limit)
        #expect(model.ownEntry == diego)
        #expect(model.rank(of: diego) == nil)
    }

    @Test("the country scope filters rows and hides an own entry from another country")
    func country() async {
        let model = LeaderboardModel(service: FakeLeaderboardService())
        model.scope = .country("MX")
        await model.load(myPlayerID: "bruno")
        #expect(model.rows == [ana, carla])
        #expect(model.ownEntry == nil, "Bruno plays for AR")
    }

    @Test("a signed-out player sees the table without a pinned row")
    func signedOut() async {
        let model = LeaderboardModel(service: FakeLeaderboardService())
        await model.load(myPlayerID: nil)
        #expect(model.rows.count == 4)
        #expect(model.ownEntry == nil)
    }

    @Test("a failed load reports a readable reason")
    func failure() async {
        var service = FakeLeaderboardService()
        service.fails = true
        let model = LeaderboardModel(service: service)
        await model.load(myPlayerID: nil)
        #expect(model.phase == .failed("Could not load the leaderboard. Check your internet and iCloud connection."))
        #expect(model.rows.isEmpty)
    }
}
