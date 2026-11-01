import Foundation
import Observation
import SwiftData
import SwiftUI
import PokerCore

/// The players this player blocked (tdr/0029). Blocking is always available
/// on an opponent's seat, and offered straight away when their picture is
/// flagged as sensitive. It only changes what this player sees and hears.
@Observable
final class BlockList {
    private let context: ModelContext
    private(set) var players: [BlockedPlayer] = []

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    var blockedIDs: Set<String> { Set(players.map(\.playerID)) }

    func isBlocked(_ playerID: String) -> Bool {
        players.contains { $0.playerID == playerID }
    }

    func block(playerID: String, name: String) {
        guard !playerID.isEmpty, !isBlocked(playerID) else { return }
        context.insert(BlockedPlayer(playerID: playerID, displayName: name))
        save()
    }

    func unblock(playerID: String) {
        for player in players where player.playerID == playerID {
            context.delete(player)
        }
        save()
    }

    /// Re-reads the store after an iCloud import; duplicates from two
    /// devices are harmless (the set of ids is what counts).
    func refresh() {
        players = (try? context.fetch(FetchDescriptor<BlockedPlayer>(sortBy: [SortDescriptor(\.blockedAt, order: .reverse)]))) ?? []
    }

    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save the block list: \(error)")
        }
        refresh()
    }
}

extension EnvironmentValues {
    /// Players whose names the seats hide (tdr/0029).
    @Entry var blockedPlayerIDs: Set<String> = []
}

extension PlayerSummary {
    /// The name to draw: hidden for a blocked player.
    func shownName(hiding blocked: Set<String>) -> String {
        blocked.contains(playerID) ? String(localized: "Blocked player") : name
    }

    /// The profile picture to draw; a blocked player always shows initials.
    func shownAvatarID(hiding blocked: Set<String>) -> String? {
        blocked.contains(playerID) ? nil : avatarID
    }
}
