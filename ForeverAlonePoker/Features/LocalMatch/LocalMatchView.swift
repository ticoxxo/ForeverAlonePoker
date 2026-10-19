import Network
import SwiftUI
import PokerCore

/// Entry point for local play: lobby first, then the shared table.
struct LocalMatchView: View {
    @State private var model: LocalLobbyModel
    @Environment(\.dismiss) private var dismiss
    private let onMatchFinished: (MatchSummary) -> Void

    init(identity: PlayerIdentity, onMatchFinished: @escaping (MatchSummary) -> Void = { _ in }) {
        self.init(model: LocalLobbyModel(identity: identity), onMatchFinished: onMatchFinished)
    }

    init(model: LocalLobbyModel, onMatchFinished: @escaping (MatchSummary) -> Void = { _ in }) {
        _model = State(wrappedValue: model)
        self.onMatchFinished = onMatchFinished
    }

    var body: some View {
        ZStack {
            if model.isPlaying, let client = model.client {
                TableView(client: client) {
                    Task {
                        await model.leave()
                        dismiss()
                    }
                }
                    .onAppear { client.onMatchFinished = onMatchFinished }
            } else {
                LocalLobbyView(model: model)
            }
        }
        .navigationTitle("Local match")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.client != nil)
        .onChange(of: model.isPlaying) {
            if model.isPlaying { model.stopAdvertising() }
        }
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
    @Bindable var model: LocalLobbyModel
    @State private var avatars = AvatarLoader()

    var body: some View {
        List {
            switch model.phase {
            case .idle:
                Section {
                    PrimaryActionButton(title: "Host a table", systemImage: "antenna.radiowaves.left.and.right") {
                        model.host()
                    }
                    .accessibilityHint(Text("Your device referees the match and shows a passcode"))
                    PrimaryActionButton(title: "Join a nearby table", systemImage: "person.2.wave.2", kind: .regular) {
                        model.browse()
                    }
                    .accessibilityHint(Text("Looks for tables hosted on devices near you"))
                } footer: {
                    Text("Every device needs Wi-Fi or Bluetooth on and the app open. The host's device referees the match and shows a passcode the other players must enter.")
                }
            case .setup:
                TableSizeSection(maxPlayers: $model.maxPlayers, isEnabled: true)
                Section {
                    PrimaryActionButton(title: "Search opponents", systemImage: "magnifyingglass") {
                        Task { await model.startSearching() }
                    }
                    Button("Back", role: .cancel) {
                        Task { await model.leave() }
                    }
                }
            case .hosting(let passcode):
                Section {
                    PasscodeDisplay(passcode: passcode)
                    LobbyStatusRow(text: model.maxPlayers == TableSize.minPlayers
                        ? "Waiting for a player to join…"
                        : "Waiting for players to join…")
                } footer: {
                    Text("Your table is visible nearby as “\(model.identity.displayName)”. Tell your opponents the passcode.")
                }
                TableSizeSection(maxPlayers: $model.maxPlayers, isEnabled: false)
                if model.maxPlayers > TableSize.minPlayers, let view = model.client?.view {
                    LobbyPlayersSection(view: view, avatars: avatars)
                    Section {
                        if view.table.isStarting {
                            LobbyStatusRow(text: "Starting…")
                        } else {
                            PrimaryActionButton(title: "Start game", systemImage: "play.fill") {
                                Task { await model.startGame() }
                            }
                            .disabled(view.players.filter(\.isConnected).isEmpty)
                        }
                    } footer: {
                        Text("Start whenever you like. Players still connecting get a few seconds to sit down.")
                    }
                }
                if !(model.client?.view?.table.isStarting ?? false) {
                    Section {
                        Button("Stop searching", role: .cancel) {
                            Task { await model.stopSearching() }
                        }
                    }
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
                if let view = model.client?.view, view.phase == .lobby {
                    LobbyPlayersSection(view: view, avatars: avatars)
                    Section {
                        LobbyStatusRow(text: view.table.isStarting ? "Starting…" : "Waiting for the host to start…")
                    }
                } else {
                    Section {
                        LobbyStatusRow(text: "Connected. Taking your seat…")
                    }
                }
            case .failed(let reason):
                Section {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    PrimaryActionButton(title: "Try again", systemImage: "arrow.clockwise") {
                        Task { await model.leave() }
                    }
                }
            }
        }
    }
}

/// The lobby's spinner rows share the design system's `WorkingRow`.
private typealias LobbyStatusRow = WorkingRow

private struct PasscodeDisplay: View {
    let passcode: String
    /// Big enough to read across a table, and bigger still with larger text.
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 52

    var body: some View {
        VStack(spacing: Theme.Spacing.xSmall) {
            Text("Passcode")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(passcode)
                .font(.system(size: digitSize, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
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
                        .frame(minHeight: Theme.Target.minimum)
                }
                .accessibilityHint(Text("Asks for the passcode shown on the host's screen"))
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
                .accessibilityLabel(Text("Passcode"))
                .accessibilityHint(Text("Four digits shown on the host's screen"))
                .onChange(of: passcode) {
                    passcode = String(passcode.filter(\.isNumber).prefix(4))
                }
            PrimaryActionButton(title: "Join", systemImage: "arrow.right.circle.fill") { onJoin(passcode) }
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

#if DEBUG
private enum LocalPreviews {
    static let peers = ["Lucía's iPhone", "Mateo"].map {
        NearbyPeer(name: $0, endpoint: .service(name: $0, type: "_preview._tcp", domain: "local.", interface: nil))
    }
}

#Preview("Host or join") {
    NavigationStack {
        LocalMatchView(identity: PreviewPlayers.me)
    }
    .previewEnvironment()
}

#Preview("Choosing the table size") {
    let model = LocalLobbyModel(identity: PreviewPlayers.me)
    NavigationStack {
        LocalMatchView(model: model)
            .onAppear { model.host() }
    }
    .previewEnvironment()
}

#Preview("Hosting heads-up") {
    NavigationStack {
        LocalMatchView(model: .preview(.hosting(passcode: "4821"), identity: PreviewPlayers.me, role: .host))
    }
    .previewEnvironment()
}

#Preview("Hosting, players joined") {
    let table = PreviewTable(maxPlayers: 4)
    let client = MatchSessionClient(identity: PreviewPlayers.me, transport: table.transport())
    NavigationStack {
        LocalMatchView(model: .preview(
            .hosting(passcode: "4821"),
            identity: PreviewPlayers.me,
            role: .host,
            maxPlayers: 4,
            client: client
        ))
        .task {
            // You sit first, so you host; then the others arrive.
            await client.connect()
            await table.seat(["Lucía", "Sofía"])
        }
    }
    .previewEnvironment()
}

#Preview("Nearby tables") {
    NavigationStack {
        LocalMatchView(model: .preview(.browsing, identity: PreviewPlayers.me, role: .guest, nearbyPeers: LocalPreviews.peers))
    }
    .previewEnvironment()
}

#Preview("Passcode entry") {
    NavigationStack {
        LocalMatchView(model: .preview(.passcodeEntry(LocalPreviews.peers[0]), identity: PreviewPlayers.me, role: .guest))
    }
    .previewEnvironment()
}

#Preview("Waiting for the host") {
    let table = PreviewTable(maxPlayers: 4)
    let client = MatchSessionClient(identity: PreviewPlayers.me, transport: table.transport())
    NavigationStack {
        LocalMatchView(model: .preview(.connected, identity: PreviewPlayers.me, role: .guest, client: client))
            .task {
                await table.seat(["Lucía", "Bob"])
                await client.connect()
            }
    }
    .previewEnvironment()
}

#Preview("Connection failed") {
    NavigationStack {
        LocalMatchView(model: .preview(.failed("The passcode did not match."), identity: PreviewPlayers.me, role: .guest))
    }
    .previewEnvironment()
}
#endif
