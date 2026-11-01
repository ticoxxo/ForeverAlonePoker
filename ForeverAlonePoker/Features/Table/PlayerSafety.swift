import SwiftUI
import PokerCore

/// Another player someone may report or block (tdr/0029).
struct SafetyTarget: Identifiable, Hashable {
    let playerID: String
    let name: String
    var id: String { playerID }

    init(playerID: String, name: String) {
        self.playerID = playerID
        self.name = name
    }

    init(_ summary: PlayerSummary) {
        self.init(playerID: summary.playerID, name: summary.name)
    }
}

/// What a seat's menu can do; `nil` where there is nobody real to act on
/// (practice against the computer).
struct PlayerSafetyActions {
    let isBlocked: (String) -> Bool
    let report: (SafetyTarget) -> Void
    let toggleBlock: (SafetyTarget) -> Void
}

extension EnvironmentValues {
    @Entry var playerSafetyActions: PlayerSafetyActions? = nil
}

extension View {
    /// Report and Block on another player's seat: a context menu, and the
    /// same two as VoiceOver actions. Report writes to support by email.
    func playerSafetyMenu(_ summary: PlayerSummary) -> some View {
        modifier(PlayerSafetyMenu(target: SafetyTarget(summary)))
    }
}

private struct PlayerSafetyMenu: ViewModifier {
    let target: SafetyTarget
    @Environment(\.playerSafetyActions) private var actions

    func body(content: Content) -> some View {
        if let actions {
            let blocked = actions.isBlocked(target.playerID)
            content
                .contentShape(.contextMenuPreview, Circle())
                .contextMenu {
                    Button {
                        actions.report(target)
                    } label: {
                        Label("Report…", systemImage: "exclamationmark.bubble")
                    }
                    Button(role: blocked ? nil : .destructive) {
                        actions.toggleBlock(target)
                    } label: {
                        blocked
                            ? Label("Unblock", systemImage: "person.crop.circle.badge.checkmark")
                            : Label("Block", systemImage: "person.crop.circle.badge.xmark")
                    }
                }
                .accessibilityAction(named: Text("Report")) { actions.report(target) }
                .accessibilityAction(named: blocked ? Text("Unblock") : Text("Block")) { actions.toggleBlock(target) }
        } else {
            content
        }
    }
}

/// The table's safety plumbing (tdr/0029): blocked names and Report/Block
/// for every seat below.
struct TableSafetyModifier: ViewModifier {
    let blocked: Set<String>
    let actions: PlayerSafetyActions?

    func body(content: Content) -> some View {
        content
            .environment(\.blockedPlayerIDs, blocked)
            .environment(\.playerSafetyActions, actions)
    }
}
