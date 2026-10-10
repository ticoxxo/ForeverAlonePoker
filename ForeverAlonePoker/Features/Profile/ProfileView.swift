import AuthenticationServices
import PhotosUI
import SwiftUI

/// Edit the player: name, country and picture; opt into ranked play; browse
/// match history.
struct ProfileView: View {
    @Environment(IdentityStore.self) private var identity
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var serverURL = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var ranked: RankedSignInModel?

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        AvatarView(data: identity.profile.avatar, size: 96)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.multicolor)
                            }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Display name") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .onSubmit(commitName)
            }

            Section("Country") {
                CountryPicker(selection: countryBinding)
            }

            accountSection

            Section {
                TextField(HTTPRoomService.defaultBaseURL.absoluteString, text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(commitServerURL)
            } header: {
                Text("Game server")
            } footer: {
                Text("Address of the server used for online matches. Leave empty for the default.")
            }

            if !identity.recentMatches.isEmpty {
                Section("Match history") {
                    ForEach(identity.recentMatches) { match in
                        MatchRecordRow(
                            opponentName: match.opponentName,
                            didWin: match.didWin,
                            mode: match.mode,
                            date: match.date,
                            isRanked: match.wasRanked
                        )
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .onAppear {
            name = identity.profile.displayName
            serverURL = identity.profile.serverURLOverride
            if ranked == nil {
                ranked = RankedSignInModel(
                    identity: identity,
                    auth: HTTPRankedAuthService(baseURL: identity.serverURL),
                    publisher: CloudKitPublicProfilePublisher()
                )
            }
        }
        .onDisappear {
            commitName()
            commitServerURL()
            // Keep the public profile in step with edits made while ranked.
            if let ranked { Task { await ranked.publishProfile() } }
        }
        .onChange(of: selectedPhoto) {
            guard let selectedPhoto else { return }
            Task {
                if let data = try? await selectedPhoto.loadTransferable(type: Data.self) {
                    identity.updateAvatar(AvatarImporter.thumbnailData(from: data))
                }
            }
        }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            LabeledContent("Account", value: tierLabel)
            if identity.tier == .ranked {
                Button("Sign out of ranked play", role: .destructive) {
                    ranked?.signOut()
                }
            } else if let ranked {
                switch ranked.phase {
                case .working:
                    HStack {
                        ProgressView()
                        Text("Checking with the server…")
                    }
                case .idle, .failed:
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = []
                    } onCompletion: { result in
                        handleSignIn(result, with: ranked)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 44)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    if case .failed(let reason) = ranked.phase {
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        } footer: {
            Text(tierFooter)
        }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>, with ranked: RankedSignInModel) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                ranked.reportSignInFailure()
                return
            }
            Task { await ranked.signIn(identityToken: token) }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            ranked.reportSignInFailure()
        }
    }

    private var tierLabel: String {
        switch identity.tier {
        case .local: String(localized: "Default user")
        case .iCloud: String(localized: "iCloud")
        case .ranked: String(localized: "Ranked")
        }
    }

    private var tierFooter: String {
        switch identity.tier {
        case .local:
            String(localized: "Your profile and history are stored on this device. Sign into iCloud in Settings to sync them, and sign in with Apple to play ranked matches.")
        case .iCloud:
            String(localized: "Your profile and history sync through iCloud. Sign in with Apple to play ranked matches and appear on the leaderboard.")
        case .ranked:
            String(localized: "Online matches against other signed-in players count toward the world and country leaderboards.")
        }
    }

    // MARK: - Bindings and commits

    private var countryBinding: Binding<String> {
        Binding(
            get: { identity.profile.countryCode },
            set: { identity.updateCountryCode($0) }
        )
    }

    private func commitName() {
        identity.updateDisplayName(name)
    }

    private func commitServerURL() {
        identity.updateServerURL(serverURL)
    }
}

private struct CountryPicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Country", selection: $selection) {
            Text("Not set").tag("")
            ForEach(CountryFlag.allRegionCodes(), id: \.self) { code in
                Text("\(CountryFlag.emoji(for: code)) \(CountryFlag.name(for: code))").tag(code)
            }
        }
        .pickerStyle(.navigationLink)
    }
}

/// Shrinks a picked photo to a small square so it stays cheap to store and
/// sync (CloudKit assets later).
enum AvatarImporter {
    static let maxDimension: CGFloat = 256

    static func thumbnailData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = min(image.size.width, image.size.height)
        let scale = min(1, maxDimension / side)
        let target = CGSize(width: side * scale, height: side * scale)
        let renderer = UIGraphicsImageRenderer(size: target, format: .init())
        let thumbnail = renderer.image { _ in
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (target.width - drawSize.width) / 2, y: (target.height - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return thumbnail.jpegData(compressionQuality: 0.85)
    }
}
