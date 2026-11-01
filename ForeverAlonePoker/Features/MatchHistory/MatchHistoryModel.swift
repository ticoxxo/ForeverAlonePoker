import Foundation
import Observation

/// How the full match history is sorted.
enum MatchHistoryOrder: CaseIterable, Hashable {
    case newestFirst
    case oldestFirst
    case opponentAZ

    var displayName: LocalizedStringResource {
        switch self {
        case .newestFirst: "Newest first"
        case .oldestFirst: "Oldest first"
        case .opponentAZ: "Opponent A–Z"
        }
    }

    var sortDescriptors: [SortDescriptor<MatchRecord>] {
        switch self {
        case .newestFirst: [SortDescriptor(\.date, order: .reverse)]
        case .oldestFirst: [SortDescriptor(\.date)]
        case .opponentAZ: [SortDescriptor(\.opponentName), SortDescriptor(\.date, order: .reverse)]
        }
    }
}

/// The whole match history, read from the store in batches as the player
/// scrolls. Batches stay cached in `IdentityStore`, so coming back is instant.
@Observable
final class MatchHistoryModel {
    var order: MatchHistoryOrder = .newestFirst
    private(set) var matches: [MatchRecord] = []
    private(set) var reachedEnd = false
    private let identity: IdentityStore

    init(identity: IdentityStore) {
        self.identity = identity
        reload()
    }

    /// Starts over in the current order with whatever is already cached.
    func reload() {
        (matches, reachedEnd) = identity.cachedHistory(order)
        if matches.isEmpty {
            loadNextBatch()
        }
    }

    func loadNextBatch() {
        guard !reachedEnd else { return }
        let page = identity.historyPage(order, offset: matches.count)
        matches += page.matches
        reachedEnd = page.reachedEnd
    }

    /// Fetches the next batch when `match` is close to the bottom of the list.
    func loadMoreIfNeeded(after match: MatchRecord) {
        guard let index = matches.firstIndex(where: { $0.id == match.id }) else { return }
        if index >= matches.count - 5 {
            loadNextBatch()
        }
    }
}
