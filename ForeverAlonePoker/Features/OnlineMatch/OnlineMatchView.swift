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
        self.init(
            model: OnlineLobbyModel(identity: identity, service: service, sessionToken: sessionToken),
            onMatchFinished: onMatchFinished,
            onRated: onRated
        )
    }

    init(
        model: OnlineLobbyModel,
        onMatchFinished: @escaping (MatchSummary) -> Void = { _ in },
        onRated: @escaping (RatingUpdate) -> Void = { _ in }
    ) {
        _model = State(wrappedValue: model)
        self.onMatchFinished = onMatchFinished
        self.onRated = onRated
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
                    .onAppear {
                        client.onMatchFinished = onMatchFinished
                        client.onRated = onRated
                    }
            } else if model.phase == .searching {
                MatchSearchView { model.cancelSearch() }
            } else {
                OnlineLobbyView(model: model)
            }
        }
        .alert("No match found :(", isPresented: $model.showsNoMatchFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nobody had an open table in the last 3 minutes. Try again, or create a table and share its code.")
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
                            .font(.callout.monospaced().bold())
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
                    .contentTransition(.opacity)
            }
        }
        .accessibilityLabel(copied ? Text("Copied") : Text("Room code \(code.map(String.init).joined(separator: " "))"))
        .accessibilityHint(Text("Copies the code so you can send it to a friend"))
        .sensoryFeedback(.success, trigger: copied) { _, copied in copied }
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
                    PrimaryActionButton(title: "Search opponents", systemImage: "magnifyingglass") {
                        Task { await model.searchOpponents() }
                    }
                } footer: {
                    Text("You get a 6-character code to share. The server referees the match.")
                }
                Section {
                    PrimaryActionButton(title: "Find a match", systemImage: "globe", kind: .regular) {
                        model.startMatchSearch()
                    }
                } footer: {
                    Text("Join any open table with a free seat, no code needed.")
                }
                Section("Join a table") {
                    TextField("Room code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.monospaced())
                        .accessibilityLabel(Text("Room code"))
                        .accessibilityHint(Text("Six letters and numbers from the friend who made the table"))
                        .onChange(of: code) {
                            code = String(code.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        }
                    PrimaryActionButton(title: "Join", systemImage: "arrow.right.circle.fill", kind: .regular) {
                        Task { await model.join(code: code) }
                    }
                    .disabled(code.count != 6)
                }
            case .working, .searching:
                Section {
                    WorkingRow(text: "Contacting the server…")
                }
            case .connected(let roomCode):
                if let client = model.client, let view = client.view, view.phase == .lobby {
                    Section {
                        VStack(spacing: Theme.Spacing.small) {
                            Text("Share this code with your opponents")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            RoomCodeBadge(code: roomCode)
                                .font(.title.monospaced().bold())
                                .glassButtonStyle()
                                .controlSize(.large)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.small)
                    }
                    TableSizeSection(maxPlayers: .constant(view.table.maxPlayers), isEnabled: false)
                    LobbyPlayersSection(view: view, avatars: avatars)
                    Section {
                        if view.table.isStarting {
                            WaitingRow(text: "Starting…")
                        } else if client.isHost {
                            PrimaryActionButton(title: "Start game", systemImage: "play.fill") {
                                Task { await model.startGame() }
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
                    PrimaryActionButton(title: "Try again", systemImage: "arrow.clockwise") { model.reset() }
                }
            }
        }
    }
}

private typealias WaitingRow = WorkingRow

#if DEBUG
#Preview("Create or join") {
    NavigationStack {
        OnlineMatchView(identity: PreviewPlayers.me, service: PreviewRoomService(.hostTable(opponents: [])))
    }
    .previewEnvironment()
}

#Preview("Hosting, players joining") {
    let model = OnlineLobbyModel(
        identity: PreviewPlayers.me,
        service: PreviewRoomService(.hostTable(opponents: ["Lucía", "Mateo"]))
    )
    NavigationStack {
        OnlineMatchView(model: model)
            .task {
                model.maxPlayers = 4
                await model.searchOpponents()
            }
    }
    .previewEnvironment()
}

#Preview("Waiting for the host") {
    let model = OnlineLobbyModel(
        identity: PreviewPlayers.me,
        service: PreviewRoomService(.joinTable(host: "Sofía", others: ["Bob"], maxPlayers: 4))
    )
    NavigationStack {
        OnlineMatchView(model: model)
            .task { await model.join(code: PreviewRoomService.roomCode) }
    }
    .previewEnvironment()
}

#Preview("Heads-up match") {
    let model = OnlineLobbyModel(
        identity: PreviewPlayers.me,
        service: PreviewRoomService(.hostTable(opponents: ["Mateo"]))
    )
    NavigationStack {
        OnlineMatchView(model: model)
            .task { await model.searchOpponents() }
    }
    .previewEnvironment()
}

#Preview("Searching for a match") {
    let model = OnlineLobbyModel(identity: PreviewPlayers.me, service: PreviewRoomService(.slowServer))
    NavigationStack {
        OnlineMatchView(model: model)
            .task { await model.findMatch() }
    }
    .previewEnvironment()
}

#Preview("No match found") {
    let model = OnlineLobbyModel(
        identity: PreviewPlayers.me,
        service: PreviewRoomService(.noSuchRoom),
        searchTimeout: .seconds(4)
    )
    NavigationStack {
        OnlineMatchView(model: model)
            .task { await model.findMatch() }
    }
    .previewEnvironment()
}

#Preview("Contacting the server") {
    let model = OnlineLobbyModel(identity: PreviewPlayers.me, service: PreviewRoomService(.slowServer))
    NavigationStack {
        OnlineMatchView(model: model)
            .task { await model.searchOpponents() }
    }
    .previewEnvironment()
}

#Preview("Room not found") {
    let model = OnlineLobbyModel(identity: PreviewPlayers.me, service: PreviewRoomService(.noSuchRoom))
    NavigationStack {
        OnlineMatchView(model: model)
            .task { await model.join(code: "ZZZ999") }
    }
    .previewEnvironment()
}
#endif
