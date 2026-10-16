import SwiftUI
import PokerCore

/// Entry point for internet play: create or join a room, then the shared table.
struct OnlineMatchView: View {
    @State private var model: OnlineLobbyModel
    @Environment(\.dismiss) private var dismiss
    private let onMatchFinished: (MatchSummary) -> Void
    private let onRated: (RatingUpdate) -> Void

    init(
        identity: PlayerIdentity,
        service: any RoomService,
        sessionToken: String? = nil,
        onMatchFinished: @escaping (MatchSummary) -> Void = { _ in },
        onRated: @escaping (RatingUpdate) -> Void = { _ in }
    ) {
        _model = State(wrappedValue: OnlineLobbyModel(identity: identity, service: service, sessionToken: sessionToken))
        self.onMatchFinished = onMatchFinished
        self.onRated = onRated
    }

    var body: some View {
        ZStack {
            if model.isPlaying, let client = model.client {
                TableView(client: client)
                    .onAppear {
                        client.onMatchFinished = onMatchFinished
                        client.onRated = onRated
                    }
            } else {
                OnlineLobbyView(model: model)
            }
        }
        .navigationTitle("Online match")
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
                if let code = model.roomCode {
                    ToolbarItem(placement: .primaryAction) {
                        RoomCodeBadge(code: code)
                    }
                }
            }
        }
        .onDisappear {
            Task { await model.leave() }
        }
    }
}

/// Shows the room code and copies it on tap so it can be sent to a friend.
struct RoomCodeBadge: View {
    let code: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = code
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            // Toolbars collapse `Label` to its icon; build the row explicitly
            // so the code itself is always visible.
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                Text(copied ? "Copied" : code)
                    .font(.callout.monospaced().bold())
            }
        }
        .accessibilityLabel(Text("Room code \(code). Double tap to copy."))
    }
}

struct OnlineLobbyView: View {
    @Bindable var model: OnlineLobbyModel
    @State private var code = ""
    @State private var avatars = AvatarLoader()

    var body: some View {
        List {
            switch model.phase {
            case .idle:
                TableSizeSection(maxPlayers: $model.maxPlayers, isEnabled: true)
                Section {
                    Button {
                        Task { await model.searchOpponents() }
                    } label: {
                        Label("Search opponents", systemImage: "magnifyingglass")
                    }
                } footer: {
                    Text("You get a 6-character code to share. The server referees the match.")
                }
                Section("Join a table") {
                    TextField("Room code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.monospaced())
                        .onChange(of: code) {
                            code = String(code.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        }
                    Button("Join") {
                        Task { await model.join(code: code) }
                    }
                    .disabled(code.count != 6)
                }
            case .working:
                Section {
                    HStack {
                        ProgressView()
                        Text("Contacting the server…")
                    }
                }
            case .connected(let roomCode):
                if let client = model.client, let view = client.view, view.phase == .lobby {
                    Section {
                        Text("Share the code \(roomCode) with your opponents.")
                    }
                    TableSizeSection(maxPlayers: .constant(view.table.maxPlayers), isEnabled: false)
                    LobbyPlayersSection(view: view, avatars: avatars)
                    Section {
                        if view.table.isStarting {
                            WaitingRow(text: "Starting…")
                        } else if client.isHost {
                            Button {
                                Task { await model.startGame() }
                            } label: {
                                Label("Start game", systemImage: "play.fill")
                            }
                            .disabled(view.players.filter(\.isConnected).isEmpty)
                        } else {
                            WaitingRow(text: "Waiting for the host to start…")
                        }
                    } footer: {
                        if client.isHost {
                            Text("Start whenever you like. Players still connecting get a few seconds to sit down.")
                        }
                    }
                    if let rejection = client.lastRejection {
                        Section {
                            Label(rejection, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Section {
                        WaitingRow(text: "Taking your seat…")
                    }
                    if let rejection = model.client?.lastRejection {
                        Section {
                            Label(rejection, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            case .failed(let reason):
                Section {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button("Try again") { model.reset() }
                }
            }
        }
    }
}

private struct WaitingRow: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack {
            ProgressView()
            Text(text)
        }
    }
}
