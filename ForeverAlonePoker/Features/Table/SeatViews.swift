import SwiftUI
import PokerCore

/// The opponent's seat: name, stack, bet in front, and their cards (face
/// down until a showdown reveals them).
struct OpponentSeatView: View {
    let summary: PlayerSummary?
    let isOnButton: Bool
    let revealedCards: [Card]
    let showsCards: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let summary {
                SeatHeaderView(
                    name: summary.name,
                    stack: summary.stack,
                    isOnButton: isOnButton,
                    isAllIn: summary.isAllIn,
                    hasFolded: summary.hasFolded,
                    isConnected: summary.isConnected
                )
                if showsCards {
                    if revealedCards.isEmpty {
                        HStack(spacing: 6) {
                            CardBackView().frame(height: 56)
                            CardBackView().frame(height: 56)
                        }
                    } else {
                        CardRowView(cards: revealedCards, height: 56)
                    }
                }
                if summary.streetCommitted > 0 {
                    ChipAmountView(amount: summary.streetCommitted)
                        .foregroundStyle(.white)
                }
            } else {
                Text("Waiting for an opponent…")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

/// The player's own seat: cards face up, stack and current bet.
struct MySeatView: View {
    let summary: PlayerSummary?
    let isOnButton: Bool
    let holeCards: [Card]

    var body: some View {
        VStack(spacing: 8) {
            if let summary, summary.streetCommitted > 0 {
                ChipAmountView(amount: summary.streetCommitted)
                    .foregroundStyle(.white)
            }
            if !holeCards.isEmpty {
                CardRowView(cards: holeCards, height: 88)
                    .opacity(summary?.hasFolded == true ? 0.4 : 1)
            }
            if let summary {
                SeatHeaderView(
                    name: summary.name,
                    stack: summary.stack,
                    isOnButton: isOnButton,
                    isAllIn: summary.isAllIn,
                    hasFolded: summary.hasFolded,
                    isConnected: summary.isConnected
                )
            }
        }
    }
}

struct SeatHeaderView: View {
    let name: String
    let stack: Chips
    let isOnButton: Bool
    let isAllIn: Bool
    let hasFolded: Bool
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isOnButton {
                Text("D")
                    .font(.caption.bold())
                    .padding(6)
                    .background(.white, in: Circle())
                    .foregroundStyle(.black)
                    .accessibilityLabel(Text("Dealer button"))
            }
            Text(name)
                .font(.headline)
            ChipAmountView(amount: stack)
            if isAllIn {
                StatusTag(text: "All-in")
            } else if hasFolded {
                StatusTag(text: "Folded")
            }
            if !isConnected {
                Image(systemName: "wifi.slash")
                    .accessibilityLabel(Text("Disconnected"))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.35), in: Capsule())
    }
}

struct StatusTag: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.yellow, in: Capsule())
            .foregroundStyle(.black)
    }
}

/// Community cards and the pot.
struct BoardView: View {
    let community: [Card]
    let pot: Chips
    let street: Street?

    var body: some View {
        VStack(spacing: 10) {
            if pot > 0 {
                HStack(spacing: 4) {
                    Text("Pot")
                    ChipAmountView(amount: pot)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.black.opacity(0.35), in: Capsule())
            }
            CardRowView(cards: community, slots: street == nil ? 0 : 5, height: 64)
                .animation(.spring(duration: 0.35), value: community)
        }
    }
}
