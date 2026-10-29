import SwiftUI
import PokerCore
import SkinKit

extension View {
    /// Shows a short celebration over the store when a purchase completes
    /// (`SkinStore.lastUnlock`, tdr/0018), then acknowledges it.
    func unlockCelebration() -> some View {
        modifier(UnlockCelebrationModifier())
    }
}

private struct UnlockCelebrationModifier: ViewModifier {
    @Environment(SkinStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let unlock = store.lastUnlock {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { store.acknowledgeUnlock() }
                            .accessibilityHidden(true)
                        UnlockCard(unlock: unlock) { store.acknowledgeUnlock() }
                            .padding(Theme.Spacing.xLarge)
                    }
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                    .task(id: unlock.id) {
                        // Long enough to read, short enough not to block shopping.
                        try? await Task.sleep(for: .seconds(4))
                        if store.lastUnlock?.id == unlock.id { store.acknowledgeUnlock() }
                    }
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.Motion.reveal, value: store.lastUnlock)
    }
}

/// "Unlocked!": the new cards fan out of a stack under a glass panel.
private struct UnlockCard: View {
    @Environment(SkinStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let unlock: SkinStore.Unlock
    let onDone: () -> Void

    @State private var isFannedOut = false
    @ScaledMetric(relativeTo: .largeTitle) private var cardHeight: CGFloat = 110

    private var item: SkinItem? { unlock.items.first }
    private var name: String {
        item?.name(for: Locale.current.language.languageCode?.identifier) ?? ""
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            preview
                .frame(height: min(cardHeight, 160) * 1.15)
                .environment(\.cardSkin, item.map(store.previewSkin(for:)) ?? .standard)
                .accessibilityHidden(true)
            VStack(spacing: Theme.Spacing.xSmall) {
                Label("Unlocked", systemImage: "checkmark.seal.fill")
                    .font(.title2.bold())
                    .symbolEffect(.bounce, options: .nonRepeating, value: isFannedOut)
                    .foregroundStyle(Theme.Palette.celebration)
                Text(name)
                    .font(.headline)
                (item?.kind == .chips ? Text("Now on your chips everywhere you play.") : Text("Now on your cards everywhere you play."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Done", action: onDone)
                .glassButtonStyle(.prominent)
                .controlSize(.large)
        }
        .padding(Theme.Spacing.xLarge)
        .frame(maxWidth: Theme.Width.card)
        .surfaceGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .sensoryFeedback(.success, trigger: unlock.id)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(reduceMotion ? nil : Theme.Motion.reveal.delay(0.1)) { isFannedOut = true }
            var announcement = AttributedString(String(localized: "Unlocked \(name)"))
            announcement.accessibilitySpeechAnnouncementPriority = .high
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    /// Three cards of a face set, the back, or three chips, fanning out
    /// from one stack.
    @ViewBuilder
    private var preview: some View {
        let height = min(cardHeight, 160)
        if item?.kind == .chips {
            ChipFanView(isFannedOut: isFannedOut)
                .frame(height: height * 0.6)
                .scaleEffect(isFannedOut ? 1 : 0.6)
        } else if item?.slots.contains(.cardBack) == true {
            CardBackView()
                .frame(height: height)
                .rotationEffect(.degrees(isFannedOut ? -4 : 0))
                .scaleEffect(isFannedOut ? 1 : 0.6)
        } else {
            ZStack {
                ForEach(Array(["Qd", "Kh", "As"].enumerated()), id: \.offset) { index, notation in
                    if let card = Card(notation) {
                        let angle = Double(index - 1) * 14
                        CardView(card: card)
                            .frame(height: height)
                            .rotationEffect(.degrees(isFannedOut ? angle : 0), anchor: .bottom)
                            .offset(x: isFannedOut ? CGFloat(index - 1) * height * 0.28 : 0)
                            .scaleEffect(isFannedOut ? 1 : 0.6)
                    }
                }
            }
        }
    }
}
