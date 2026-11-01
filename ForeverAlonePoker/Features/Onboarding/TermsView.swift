import SwiftUI

/// Accepting the community guidelines before meeting other players: App
/// Review Guideline 1.2 asks user-generated-content apps for terms with zero
/// tolerance for objectionable content (tdr/0029). Shown once per version.
struct TermsView: View {
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                CommunityGuidelinesText()
                    .padding()
            }
            .navigationTitle("Community guidelines")
            .safeAreaInset(edge: .bottom) {
                Button(action: onAccept) {
                    Text("I agree")
                        .frame(maxWidth: .infinity, minHeight: Theme.Target.primary)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.bar)
            }
        }
        .interactiveDismissDisabled()
    }
}
