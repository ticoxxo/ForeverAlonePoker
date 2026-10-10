import Foundation
import Observation

/// Loads the top of the world or a country leaderboard plus the player's own
/// row when it falls outside the top (tdr/0006: no absolute rank in v1).
@Observable
final class LeaderboardModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    static let limit = 100

    var scope: LeaderboardScope = .world
    private(set) var phase: Phase = .loading
    private(set) var rows: [LeaderboardRow] = []
    /// The player's row when it is not among `rows`.
    private(set) var ownEntry: LeaderboardRow?
    private(set) var avatars: [String: Data] = [:]
    private let service: any LeaderboardService

    init(service: any LeaderboardService) {
        self.service = service
    }

    func load(myPlayerID: String?) async {
        phase = .loading
        do {
            let top = try await service.top(scope, limit: Self.limit)
            rows = top
            ownEntry = await ownEntryOutsideTop(top, myPlayerID: myPlayerID)
            phase = .loaded
            avatars = (try? await service.avatars(for: top.map(\.playerID) + (ownEntry.map { [$0.playerID] } ?? []))) ?? [:]
        } catch {
            rows = []
            ownEntry = nil
            phase = .failed(String(localized: "Could not load the leaderboard. Check your internet and iCloud connection."))
        }
    }

    /// 1-based position within the loaded top; `nil` for the pinned own entry.
    func rank(of row: LeaderboardRow) -> Int? {
        rows.firstIndex(of: row).map { $0 + 1 }
    }

    private func ownEntryOutsideTop(_ top: [LeaderboardRow], myPlayerID: String?) async -> LeaderboardRow? {
        guard let myPlayerID, !top.contains(where: { $0.playerID == myPlayerID }) else { return nil }
        guard let own = try? await service.entry(for: myPlayerID) else { return nil }
        if case .country(let code) = scope, own.countryCode != code { return nil }
        return own
    }
}
