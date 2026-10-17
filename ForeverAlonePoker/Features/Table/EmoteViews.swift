import SwiftUI
import PokerCore

/// A player's emote, popped up by their seat for a few seconds (tdr/0015).
struct EmoteBubble: View {
    let reaction: MatchSessionClient.Reaction?

    var body: some View {
        ZStack {
            if let reaction {
                Text(reaction.emote.symbol)
                    .font(.system(size: 34))
                    .padding(6)
                    .background(.white.opacity(0.9), in: Circle())
                    .shadow(radius: 3)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .id(reaction.id)
                    .accessibilityLabel(Text("Reaction \(reaction.emote.symbol)"))
            }
        }
        .animation(.spring(duration: 0.3), value: reaction)
        .allowsHitTesting(false)
    }
}

/// The emote tray: one button that opens the nine emojis. Disabled once this
/// turn's emote is spent.
struct EmotePicker: View {
    let isEnabled: Bool
    let onPick: (Emote) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "face.smiling")
                .font(.title2)
                .padding(10)
                .background(.black.opacity(0.35), in: Circle())
                .foregroundStyle(.white)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(Text("Send a reaction"))
        .popover(isPresented: $isPresented) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48)), count: 3), spacing: 8) {
                ForEach(Emote.allCases, id: \.self) { emote in
                    Button {
                        isPresented = false
                        onPick(emote)
                    } label: {
                        Text(emote.symbol)
                            .font(.system(size: 32))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(emote.symbol))
                }
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        EmoteBubble(reaction: MatchSessionClient.Reaction(emote: .cool))
        EmotePicker(isEnabled: true) { _ in }
    }
    .padding()
    .background(TableFelt())
}
