import Foundation
import SwiftData
import Testing
import PokerCore
@testable import ForeverAlonePoker

/// 60 matches, one an hour apart, against opponents named in reverse order of
/// play so the A–Z order differs from the date order.
@MainActor
private struct Fixture {
    let container: ModelContainer
    let store: IdentityStore

    init(matchCount: Int = 60) throws {
        container = try Persistence.inMemoryContainer()
        store = try IdentityStore(context: container.mainContext, defaultCountryCode: "MX")
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<matchCount {
            let match = MatchRecord(
                mode: .local,
                opponentName: String(format: "Opponent %02d", matchCount - 1 - index),
                didWin: false, finalStack: 0, opponentFinalStack: 0, handsPlayed: 1,
                date: start.addingTimeInterval(Double(index) * 3600)
            )
            match.profile = store.profile
            context.insert(match)
        }
        try context.save()
        store.refresh()
    }
}

@Suite("MatchHistoryModel")
@MainActor
struct MatchHistoryModelTests {
    @Test("loads newest first in batches until the end")
    func batches() throws {
        let fixture = try Fixture()
        let model = MatchHistoryModel(identity: fixture.store)
        #expect(model.matches.count == IdentityStore.historyBatchSize)
        #expect(!model.reachedEnd)
        #expect(model.matches.map(\.date) == model.matches.map(\.date).sorted(by: >))

        model.loadNextBatch()
        model.loadNextBatch()
        #expect(model.matches.count == 60)
        #expect(model.reachedEnd)
        #expect(Set(model.matches.map(\.id)).count == 60, "no duplicates across batches")
    }

    @Test("scrolling near the bottom loads the next batch")
    func loadMore() throws {
        let fixture = try Fixture()
        let model = MatchHistoryModel(identity: fixture.store)
        model.loadMoreIfNeeded(after: model.matches[0])
        #expect(model.matches.count == 25, "the top row does not trigger a fetch")
        model.loadMoreIfNeeded(after: model.matches[23])
        #expect(model.matches.count == 50)
    }

    @Test("oldest first and opponent A–Z orders")
    func orders() throws {
        let fixture = try Fixture()
        let model = MatchHistoryModel(identity: fixture.store)
        model.order = .oldestFirst
        model.reload()
        #expect(model.matches.first?.opponentName == "Opponent 59")
        #expect(model.matches.map(\.date) == model.matches.map(\.date).sorted())

        model.order = .opponentAZ
        model.reload()
        #expect(model.matches.prefix(3).map(\.opponentName) == ["Opponent 00", "Opponent 01", "Opponent 02"])
    }

    @Test("a new model starts with everything already cached")
    func cache() throws {
        let fixture = try Fixture()
        let first = MatchHistoryModel(identity: fixture.store)
        first.loadNextBatch()
        first.loadNextBatch()

        let second = MatchHistoryModel(identity: fixture.store)
        #expect(second.matches.count == 60)
        #expect(second.reachedEnd)
    }

    @Test("recording a match drops the cache so it shows up first")
    func invalidates() throws {
        let fixture = try Fixture()
        _ = MatchHistoryModel(identity: fixture.store)
        fixture.store.record(MatchSummary(didWin: true, opponentName: "Bob", myFinalStack: 3000, opponentFinalStack: 0, handsPlayed: 3), mode: .local)

        let model = MatchHistoryModel(identity: fixture.store)
        #expect(model.matches.first?.opponentName == "Bob")
        #expect(model.matches.count == 25)
    }

    @Test("an empty history ends right away")
    func empty() throws {
        let fixture = try Fixture(matchCount: 0)
        let model = MatchHistoryModel(identity: fixture.store)
        #expect(model.matches.isEmpty)
        #expect(model.reachedEnd)
    }
}
