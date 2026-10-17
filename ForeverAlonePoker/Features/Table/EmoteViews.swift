import SwiftUI
import PokerCore

/// A player's emote in a speech bubble that hugs the emoji, popped up by
/// their seat for a few seconds (tdr/0015). Attach it with `emoteBubble(_:)`
/// so it sits above and to the right of the picture, its tail pointing at it.
struct EmoteBubble: View {
    enum Size {
        case regular
        /// For the waiting zone (tdr/0016).
        case small

        var fontSize: CGFloat { self == .regular ? 26 : 18 }
        var padding: CGFloat { self == .regular ? 8 : 5 }
        var tail: CGFloat { self == .regular ? 7 : 5 }
    }

    let reaction: MatchSessionClient.Reaction?
    var size: Size = .regular

    var body: some View {
        ZStack {
            if let reaction {
                Text(reaction.emote.symbol)
                    .font(.system(size: size.fontSize))
                    .fixedSize()
                    .padding(.horizontal, size.padding)
                    .padding(.vertical, size.padding * 0.6)
                    // Room for the tail under the rounded body, so the emoji
                    // stays centered in the body itself.
                    .padding(.bottom, size.tail)
                    .background(SpeechBubble(tail: size.tail).fill(.white))
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .transition(.scale(scale: 0.4, anchor: .bottomLeading).combined(with: .opacity))
                    .id(reaction.id)
                    .accessibilityLabel(Text("Reaction \(reaction.emote.symbol)"))
            }
        }
        .animation(.spring(duration: 0.3), value: reaction)
        .allowsHitTesting(false)
    }
}

/// A rounded bubble whose tail, at the bottom-left, points down at the
/// picture it belongs to.
private struct SpeechBubble: Shape {
    let tail: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tail)
        var path = Path(roundedRect: body, cornerRadius: min(body.height, body.width) / 2, style: .continuous)
        let start = body.minX + body.height * 0.35
        path.move(to: CGPoint(x: start, y: body.maxY - 1))
        path.addLine(to: CGPoint(x: body.minX + 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: start + tail * 1.6, y: body.maxY - 1))
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Puts an emote bubble just above the top-right corner of this view, the
    /// tail touching its edge, without covering it or changing its layout.
    func emoteBubble(_ reaction: MatchSessionClient.Reaction?, size: EmoteBubble.Size = .regular) -> some View {
        overlay(alignment: .topTrailing) {
            EmoteBubble(reaction: reaction, size: size)
                .alignmentGuide(.top) { $0[.bottom] - size.tail }
                .alignmentGuide(.trailing) { $0[.leading] + size.padding }
        }
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
    HStack(spacing: 60) {
        AvatarView(data: nil, size: 36, name: "Ticoxxo")
            .emoteBubble(MatchSessionClient.Reaction(emote: .poop))
        AvatarView(data: nil, size: 30, name: "Bot")
            .emoteBubble(MatchSessionClient.Reaction(emote: .cool), size: .small)
        EmotePicker(isEnabled: true) { _ in }
    }
    .padding(40)
    .background(TableFelt())
}
