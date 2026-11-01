import SwiftUI

/// The rules every player accepts before playing with others, and the way
/// to reach us (App Review Guideline 1.2, tdr/0029). Bump `version` when
/// the text changes in substance so everyone accepts it again.
enum CommunityGuidelines {
    static let version = 1
    /// `@AppStorage` key holding the accepted version.
    static let acceptedVersionKey = "acceptedGuidelinesVersion"
}

struct CommunityGuidelinesText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("ForeverAlonePoker is for everyone. Your name is seen by the players you meet, so names and behavior at the table must follow these rules:")
            rule("No hate, harassment, threats or slurs.")
            rule("No sexual or violent names.")
            rule("No spam, links or impersonation.")
            Text("There is zero tolerance for objectionable content or abusive players. Names are filtered automatically. You can block or report any player from their seat; we review reports within 24 hours and act on them.")
            Text("Questions or problems: \(SupportContact.email)")
                .textSelection(.enabled)
        }
        .font(.body)
    }

    private func rule(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "checkmark.shield")
            .labelStyle(.titleAndIcon)
    }
}

struct CommunityGuidelinesView: View {
    var body: some View {
        ScrollView {
            CommunityGuidelinesText()
                .padding()
        }
        .navigationTitle("Community guidelines")
    }
}
