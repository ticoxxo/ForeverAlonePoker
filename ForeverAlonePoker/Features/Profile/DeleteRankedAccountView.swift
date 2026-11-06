import AuthenticationServices
import SwiftUI

/// Confirms deleting the ranked account (tdr/0034). Continuing with Apple is
/// the confirmation: it proves the owner is here and hands the server a fresh
/// authorization code to revoke the app's Apple tokens with.
struct DeleteRankedAccountView: View {
    let ranked: RankedSignInModel
    @Environment(IdentityStore.self) private var identity
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Your leaderboard entry, rating and record are removed for good.", systemImage: "trophy")
                    Label("ForeverAlonePoker stops using your Apple Account for sign-in.", systemImage: "apple.logo")
                    Label("Your name, picture, purchases and match history on this device stay.", systemImage: "iphone")
                } footer: {
                    Text("You can sign in again later; you will start over at the initial rating.")
                }

                Section {
                    switch ranked.phase {
                    case .working:
                        WorkingRow(text: "Deleting your ranked account…")
                    case .idle, .failed:
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = []
                        } onCompletion: { result in
                            handle(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: Theme.Target.minimum)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        if case .failed(let reason) = ranked.phase {
                            Label(reason, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                } footer: {
                    Text("Continue with Apple to confirm.")
                }
            }
            .navigationTitle("Delete ranked account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(ranked.phase == .working)
                }
            }
        }
        .interactiveDismissDisabled(ranked.phase == .working)
        .onAppear { ranked.dismissFailure() }
        .onChange(of: identity.tier) { _, tier in
            if tier != .ranked { dismiss() }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                ranked.reportSignInFailure()
                return
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            Task { await ranked.deleteAccount(identityToken: token, authorizationCode: code) }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            ranked.reportSignInFailure()
        }
    }
}
