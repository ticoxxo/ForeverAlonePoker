import SwiftUI
import PokerCore

/// The opponent's seat: name, stack, bet in front, and their cards (face
/// down until a showdown reveals them).
struct OpponentSeatView: View {
    let summary: PlayerSummary?
    let isOnButton: Bool
    let revealedCards: [Card]
    let showsCards: Bool
    var isActing: Bool = false
    var avatar: Data? = nil
    var reaction: MatchSessionClient.Reaction? = nil

    var body: some View {
        VStack(spacing: 8) {
            if let summary {
                PlayerAvatar(data: avatar, size: 44, name: summary.name, isReconnecting: summary.isReconnecting)
                    .emoteBubble(reaction)
                SeatHeaderView(
                    name: summary.name,
                    stack: summary.stack,
                    isOnButton: isOnButton,
                    isAllIn: summary.isAllIn,
                    hasFolded: summary.hasFolded,
                    isBusted: summary.isBusted,
                    isActing: isActing
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
    var reaction: MatchSessionClient.Reaction? = nil

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
                    isBusted: summary.isBusted
                )
                .emoteBubble(reaction)
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
    var isBusted: Bool = false
    var isActing: Bool = false

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
            if isBusted {
                StatusTag(text: "Out")
            } else if isAllIn {
                StatusTag(text: "All-in")
            } else if hasFolded {
                StatusTag(text: "Folded")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.35), in: Capsule())
        .overlay {
            if isActing {
                Capsule().strokeBorder(.yellow, lineWidth: 2)
            }
        }
        .opacity(isBusted ? 0.5 : 1)
    }
}

/// One of several other players at a bigger table (tdr/0013): a compact
/// badge with picture, name and stack, small cards, and their bet.
struct CompactSeatView: View {
    let summary: PlayerSummary
    let avatar: Data?
    let isOnButton: Bool
    let isActing: Bool
    let revealedCards: [Card]
    let showsCards: Bool
    var reaction: MatchSessionClient.Reaction? = nil

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                PlayerAvatar(data: avatar, size: 36, name: summary.name, isReconnecting: summary.isReconnecting)
                    .overlay {
                        if isActing {
                            Circle().strokeBorder(.yellow, lineWidth: 2)
                        }
                    }
                if isOnButton {
                    Text("D")
                        .font(.caption2.bold())
                        .padding(3)
                        .background(.white, in: Circle())
                        .foregroundStyle(.black)
                        .accessibilityLabel(Text("Dealer button"))
                }
            }
            .emoteBubble(reaction)
            Text(summary.name)
                .font(.caption.bold())
                .lineLimit(1)
            ChipAmountView(amount: summary.stack)
                .font(.caption2)
            if summary.isBusted {
                StatusTag(text: "Out")
            } else if summary.isAllIn {
                StatusTag(text: "All-in")
            } else if summary.hasFolded {
                StatusTag(text: "Folded")
            }
            if showsCards {
                if revealedCards.isEmpty {
                    HStack(spacing: 2) {
                        CardBackView().frame(height: 30)
                        CardBackView().frame(height: 30)
                    }
                } else {
                    CardRowView(cards: revealedCards, height: 30)
                }
            }
            if summary.streetCommitted > 0 {
                ChipAmountView(amount: summary.streetCommitted)
                    .font(.caption2)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 96)
        .opacity(summary.isBusted ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// A player's picture. While they are reconnecting (tdr/0016) it is dimmed
/// behind a `wifi.slash` symbol, with a spinning ring around it.
struct PlayerAvatar: View {
    let data: Data?
    let size: CGFloat
    let name: String
    var isReconnecting: Bool = false

    var body: some View {
        AvatarView(data: data, size: size, name: name)
            .overlay {
                if isReconnecting {
                    ZStack {
                        Circle().fill(.black.opacity(0.55))
                        Image(systemName: "wifi.slash")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.pulse)
                    }
                    .transition(.opacity)
                }
            }
            .overlay {
                if isReconnecting {
                    ReconnectRing(diameter: size + max(6, size * 0.16))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isReconnecting)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isReconnecting ? Text("\(name), reconnecting") : Text("Profile picture of \(name)"))
    }
}

/// An arc that keeps spinning around a reconnecting player's picture.
private struct ReconnectRing: View {
    let diameter: CGFloat
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(.white, style: StrokeStyle(lineWidth: max(2, diameter * 0.05), lineCap: .round))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
            .allowsHitTesting(false)
    }
}

extension PlayerSummary {
    /// Dropped but still holding the seat (tdr/0014, tdr/0016).
    nonisolated var isReconnecting: Bool { !isConnected && !isBusted }
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
