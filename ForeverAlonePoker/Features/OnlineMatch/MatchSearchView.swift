import SwiftUI

/// Shown while the lobby searches for an open table without a code
/// (tdr/0021): the spinning globe and a way out.
struct MatchSearchView: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            Spacer()
            GlobeAnimationView(showsControls: false)
                .accessibilityHidden(true)
            VStack(spacing: Theme.Spacing.small) {
                Text("Searching for a match…")
                    .font(.title2.bold())
                Text("Looking for an open table with a free seat. We stop after 3 minutes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
            Spacer()
            PrimaryActionButton(title: "Cancel", systemImage: "xmark", kind: .regular, action: onCancel)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    MatchSearchView(onCancel: {})
}
#endif
