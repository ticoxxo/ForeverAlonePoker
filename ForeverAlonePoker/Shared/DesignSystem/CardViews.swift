import SwiftUI
import PokerCore

/// A face-up playing card.
struct CardView: View {
    let card: Card

    /// The card face is always white, so the ink must be a fixed colour.
    /// `.primary` resolves to white in dark mode and made black suits invisible.
    private var color: Color {
        switch card.suit {
        case .hearts, .diamonds: .red
        case .clubs, .spades: .black
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white)
                .shadow(radius: 1, y: 1)
            VStack(spacing: 0) {
                Text(card.rank.symbol)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(card.suit.symbol)
                    .font(.title3)
            }
            .foregroundStyle(color)
        }
        .aspectRatio(0.7, contentMode: .fit)
        .environment(\.colorScheme, .light)
        .accessibilityLabel(Text(card.notation))
    }
}

/// A face-down card.
struct CardBackView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 2)
                    .padding(3)
            )
            .shadow(radius: 1, y: 1)
            .aspectRatio(0.7, contentMode: .fit)
            .accessibilityLabel(Text("Face-down card"))
    }
}

/// A row of cards, with optional face-down placeholders filling to `slots`.
struct CardRowView: View {
    let cards: [Card]
    var slots: Int = 0
    var height: CGFloat = 64

    var body: some View {
        HStack(spacing: 6) {
            ForEach(cards, id: \.self) { card in
                CardView(card: card)
                    .frame(height: height)
                    .transition(.scale.combined(with: .opacity))
            }
            ForEach(0..<max(0, slots - cards.count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .aspectRatio(0.7, contentMode: .fit)
                    .frame(height: height)
            }
        }
    }
}

/// A chip amount with a consistent style.
struct ChipAmountView: View {
    let amount: Chips

    var body: some View {
        Label {
            Text(amount, format: .number)
                .monospacedDigit()
        } icon: {
            Image(systemName: "circle.circle.fill")
        }
        .font(.subheadline.weight(.semibold))
    }
}

#Preview("Cards") {
    VStack(spacing: 16) {
        CardRowView(cards: [Card("As")!, Card("Kd")!, Card("Th")!, Card("2c")!], slots: 5)
        HStack {
            CardBackView().frame(height: 64)
            CardBackView().frame(height: 64)
        }
        ChipAmountView(amount: 1500)
    }
    .padding()
    .background(.green)
}
