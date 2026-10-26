import SwiftUI

/// Common questions about the card store (tdr/0022). It says nothing about
/// whether Apple grants refunds: that is Apple's call (HIG).
struct PurchaseFAQView: View {
    private struct Entry {
        let question: LocalizedStringKey
        let answer: LocalizedStringKey
    }

    private let entries: [Entry] = [
        Entry(
            question: "What do I get when I buy a set?",
            answer: "All 52 card faces of the set, or the card back you bought. You choose which cards show it, and can switch back to the classic deck at any time."
        ),
        Entry(
            question: "Do skins change the game?",
            answer: "No. Skins are only how cards look. Every player gets the same cards and the same rules."
        ),
        Entry(
            question: "Can my opponent see my cards' skin?",
            answer: "Only if their device already has that skin. Otherwise they see the classic cards."
        ),
        Entry(
            question: "Why is the price in my currency?",
            answer: "Prices come from the App Store in the currency of your App Store country or region."
        ),
        Entry(
            question: "I have a new device. Do I buy again?",
            answer: "No. Purchases belong to your Apple Account. Sign in with the same account and tap Restore in the card store."
        ),
        Entry(
            question: "Can my family use what I buy?",
            answer: "Not at the moment: card skins are not shared through Family Sharing."
        ),
        Entry(
            question: "How do I request a refund?",
            answer: "Open Help, then Request a Refund, and choose the purchase. Apple handles the request and emails you about it."
        ),
    ]

    var body: some View {
        List(entries.indices, id: \.self) { index in
            let entry = entries[index]
            DisclosureGroup {
                Text(entry.answer)
                    .foregroundStyle(.secondary)
            } label: {
                Text(entry.question)
                    .font(.headline)
            }
        }
        .navigationTitle("Questions")
    }
}

#if DEBUG
#Preview("FAQ") {
    NavigationStack {
        PurchaseFAQView()
    }
}
#endif
