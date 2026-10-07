import PhotosUI
import SwiftUI

/// Edit the default user: name, country and picture; browse match history.
struct ProfileView: View {
    @Environment(IdentityStore.self) private var identity
    @State private var name = ""
    @State private var serverURL = ""
    @State private var selectedPhoto: PhotosPickerItem?

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

            Section {
                LabeledContent("Account", value: tierLabel)
            } footer: {
                Text("Your profile and history are stored on this device. iCloud sync and ranked play are coming later.")
            }

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
                            date: match.date
                        )
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .onAppear {
            name = identity.profile.displayName
            serverURL = identity.profile.serverURLOverride
        }
        .onDisappear {
            commitName()
            commitServerURL()
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

    private var countryBinding: Binding<String> {
        Binding(
            get: { identity.profile.countryCode },
            set: { identity.updateCountryCode($0) }
        )
    }

    private var tierLabel: String {
        switch identity.tier {
        case .local: String(localized: "Default user")
        case .iCloud: String(localized: "iCloud")
        case .ranked: String(localized: "Ranked")
        }
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
