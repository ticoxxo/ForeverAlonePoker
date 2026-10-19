import SwiftUI

/// The one obvious next step of a screen (tdr/0018): full width, 56 pt tall,
/// prominent glass (or a bordered prominent button before iOS 26). Inside a
/// `List` it drops the row background so it reads as a button, not a row.
struct PrimaryActionButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var isWorking: Bool = false
    /// `.regular` for an equal alternative next to the main action.
    var kind: GlassButtonKind = .prominent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.small) {
                if isWorking {
                    ProgressView()
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.Target.primary - 14)
        }
        .glassButtonStyle(kind)
        .controlSize(.regular)
        .disabled(isWorking)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: Theme.Spacing.small, leading: 0, bottom: Theme.Spacing.small, trailing: 0))
    }
}

/// A progress spinner with a short message, read by VoiceOver as one phrase.
struct WorkingRow: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            ProgressView()
            Text(text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
