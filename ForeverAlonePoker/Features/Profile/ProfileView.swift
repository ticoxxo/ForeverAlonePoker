import AuthenticationServices
import SwiftUI

/// Edit the player: name, picture and country; sound; opt into ranked play.
struct ProfileView: View {
    @Environment(IdentityStore.self) private var identity
    @Environment(AudioSettings.self) private var audio
    @Environment(SkinStore.self) private var skins
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(CountryFlag.showsAtOnlineTablesKey) private var showsCountryFlags = true
    @State private var name = ""
    #if DEBUG
    @State private var serverURL = ""
    #endif
    @State private var ranked: RankedSignInModel?
    @State private var safety: ProfileSafetyModel?
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 96

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    AvatarView(avatarID: skins.myAvatarID, size: min(avatarSize, 160), name: identity.profile.displayName)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                AvatarPicker()
            } header: {
                Text("Profile picture")
            } footer: {
                Text("More pictures in the Store.")
            }

            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .onSubmit(commitName)
            } header: {
                Text("Display name")
            } footer: {
                if let error = safety?.nameError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                CountryPicker(selection: countryBinding)
                Toggle(isOn: $showsCountryFlags) {
                    Label("Show flags online", systemImage: "flag")
                }
            } header: {
                Text("Country")
            } footer: {
                Text("Online tables show each player's country flag on their picture.")
            }

            soundSections

            accountSection

            rankedSection

            safetySection

            #if DEBUG
            // Developer only: release builds always use the production server (tdr/0032).
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
            #endif
        }
        .navigationTitle("Profile")
        .onAppear {
            name = identity.profile.displayName
            #if DEBUG
            serverURL = identity.profile.serverURLOverride
            #endif
            if ranked == nil {
                ranked = RankedSignInModel(
                    identity: identity,
                    auth: HTTPRankedAuthService(baseURL: identity.serverURL)
                )
            }
            if safety == nil {
                safety = ProfileSafetyModel(identity: identity)
            }
        }
        .onDisappear {
            commitName()
            #if DEBUG
            commitServerURL()
            #endif
        }
    }

    // MARK: - Sound

    /// Music and sound effects, one group each like the folders they play
    /// from, then Reset (tdr/0026).
    @ViewBuilder
    private var soundSections: some View {
        @Bindable var audio = audio
        Section {
            Toggle(isOn: $audio.isMusicOn) {
                Label("Music", systemImage: "music.note")
            }
            VolumeSlider(title: "Music volume", value: $audio.musicVolume)
                .disabled(!audio.isMusicOn)
            Picker("Track", selection: $audio.selectedTrack) {
                ForEach(MusicTrack.allCases) { track in
                    Text(verbatim: track.title).tag(track)
                }
            }
            .pickerStyle(.menu)
            .disabled(!audio.isMusicOn)
        } header: {
            Text("Sound")
        }

        Section {
            Toggle(isOn: $audio.areEffectsOn) {
                Label("Sound effects", systemImage: "speaker.wave.2")
            }
            VolumeSlider(title: "Sound effects volume", value: $audio.effectsVolume)
                .disabled(!audio.areEffectsOn)
        }

        Section {
            Button("Reset settings") {
                audio.resetToDefaults()
            }
        }
    }

    // MARK: - Account

    private var accountStatus: AccountStatus {
        AccountStatus(isCloudSyncEnabled: identity.isCloudSyncEnabled, tier: identity.tier)
    }

    /// iOS owns the iCloud account, so this only reports it (tdr/0033).
    private var accountSection: some View {
        Section {
            LabeledContent("iCloud") {
                // Not a Label: inside LabeledContent it makes the row far too tall on iOS 27.
                HStack(spacing: Theme.Spacing.small) {
                    Image(systemName: accountStatus.cloudSymbol)
                    Text(accountStatus.cloudLabel)
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text(accountStatus.cloudFooter)
        }
    }

    @ViewBuilder
    private var rankedSection: some View {
        Section {
            if accountStatus.isRanked {
                LabeledContent("Ranked", value: String(localized: "Signed in"))
                Button("Sign out of ranked play", role: .destructive) {
                    ranked?.signOut()
                }
            } else if let ranked {
                switch ranked.phase {
                case .working:
                    WorkingRow(text: "Checking with the server…")
                case .idle, .failed:
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = []
                    } onCompletion: { result in
                        handleSignIn(result, with: ranked)
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
            }
        } header: {
            Text("Ranked play")
        } footer: {
            Text(accountStatus.rankedFooter)
        }
    }

    // MARK: - Safety and support (tdr/0029)

    private var safetySection: some View {
        Section {
            NavigationLink {
                BlockedPlayersView()
            } label: {
                Label("Blocked players", systemImage: "person.crop.circle.badge.xmark")
            }
            NavigationLink {
                CommunityGuidelinesView()
            } label: {
                Label("Community guidelines", systemImage: "checkmark.shield")
            }
            Link(destination: SupportContact.mailURL(.support)) {
                Label("Contact support", systemImage: "envelope")
            }
        } header: {
            Text("Safety and support")
        } footer: {
            Text("To block or report a player, touch and hold their seat at the table.")
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

    // MARK: - Bindings and commits

    private var countryBinding: Binding<String> {
        Binding(
            get: { identity.profile.countryCode },
            set: { identity.updateCountryCode($0) }
        )
    }

    private func commitName() {
        if let accepted = safety?.commitName(name) { name = accepted }
    }

    #if DEBUG
    private func commitServerURL() {
        identity.updateServerURL(serverURL)
    }
    #endif
}

/// A 0 to 100 % volume in tenths, quiet speaker to loud speaker.
private struct VolumeSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Float

    var body: some View {
        Slider(value: $value, in: 0...1, step: 0.1) {
            Text(title)
        } minimumValueLabel: {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } maximumValueLabel: {
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
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
