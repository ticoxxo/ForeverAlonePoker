import SwiftUI
import PokerCore

/// Entry point for local play: lobby first, then the shared table.
struct LocalMatchView: View {
    @State private var model: LocalLobbyModel
    @Environment(\.dismiss) private var dismiss
    private let onMatchFinished: (MatchSummary) -> Void

    init(identity: PlayerIdentity, onMatchFinished: @escaping (MatchSummary) -> Void = { _ in }) {
        _model = State(wrappedValue: LocalLobbyModel(identity: identity))
        self.onMatchFinished = onMatchFinished
    }

    var body: some View {
        ZStack {
            if let client = model.client {
                TableView(client: client)
                    .onAppear { client.onMatchFinished = onMatchFinished }
            } else {
                LocalLobbyView(model: model)
            }
        }
        .navigationTitle("Local match")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.client != nil)
        .toolbar {
            if model.client != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Leave") {
                        Task {
                            await model.leave()
                            dismiss()
                        }
                    }
                }
            }
        }
        .onDisappear {
            Task { await model.leave() }
        }
    }
}

/// Host or join a nearby table.
struct LocalLobbyView: View {
    let model: LocalLobbyModel

    var body: some View {
        List {
            switch model.phase {
            case .idle:
                Section {
                    Button {
                        model.host()
                    } label: {
                        Label("Host a table", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    Button {
                        model.browse()
                    } label: {
                        Label("Join a nearby table", systemImage: "person.2.wave.2")
                    }
                } footer: {
                    Text("Both devices need Wi-Fi or Bluetooth on and the app open. The host's device referees the match and shows a passcode the guest must enter.")
                }
            case .hosting(let passcode):
                Section {
                    PasscodeDisplay(passcode: passcode)
                    LobbyStatusRow(text: "Waiting for a player to join…")
                } footer: {
                    Text("Your table is visible nearby as “\(model.identity.displayName)”. Tell your opponent the passcode.")
                }
            case .browsing:
                NearbyPeersSection(peers: model.nearbyPeers, onSelect: model.select)
            case .passcodeEntry(let peer):
                PasscodeEntrySection(
                    peerName: peer.name,
                    onJoin: { model.join(peer, passcode: $0) },
                    onCancel: model.cancelPasscodeEntry
                )
            case .connecting(let peerName):
                Section {
                    LobbyStatusRow(text: "Connecting to \(peerName)…")
                }
            case .connected:
                Section {
                    LobbyStatusRow(text: "Connected. Taking your seat…")
                }
            case .failed(let reason):
                Section {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button("Try again") {
                        Task { await model.leave() }
                    }
                }
            }
        }
    }
}

private struct LobbyStatusRow: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack {
            ProgressView()
            Text(text)
        }
    }
}

private struct PasscodeDisplay: View {
    let passcode: String

    var body: some View {
        VStack(spacing: 4) {
            Text("Passcode")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(passcode)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .kerning(8)
                .accessibilityLabel(Text("Passcode \(passcode.map(String.init).joined(separator: " "))"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct NearbyPeersSection: View {
    let peers: [NearbyPeer]
    let onSelect: (NearbyPeer) -> Void

    var body: some View {
        Section {
            if peers.isEmpty {
                LobbyStatusRow(text: "Looking for nearby tables…")
            }
            ForEach(peers) { peer in
                Button {
                    onSelect(peer)
                } label: {
                    Label(peer.name, systemImage: "suit.spade.fill")
                }
            }
        } header: {
            Text("Nearby tables")
        }
    }
}

private struct PasscodeEntrySection: View {
    let peerName: String
    let onJoin: (String) -> Void
    let onCancel: () -> Void

    @State private var passcode = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Section {
            TextField("4-digit passcode", text: $passcode)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .onChange(of: passcode) {
                    passcode = String(passcode.filter(\.isNumber).prefix(4))
                }
            Button("Join") { onJoin(passcode) }
                .disabled(passcode.count != 4)
            Button("Back", role: .cancel, action: onCancel)
        } header: {
            Text("Join \(peerName)")
        } footer: {
            Text("Enter the passcode shown on the host's screen.")
        }
        .onAppear { isFocused = true }
    }
}
