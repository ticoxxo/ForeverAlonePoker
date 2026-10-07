import Foundation
import PokerCore
import PokerServerCore

// Development opponent for online play: joins a room and readies, checks or
// calls whenever it is its turn. Usage:
//   swift run PokerBot <ROOMCODE> [http://host:port]
// Omit the code to create a new room and print it.

setbuf(stdout, nil)  // Unbuffered so the room code shows up immediately when piped.

let arguments = CommandLine.arguments.dropFirst()
let baseURL = URL(string: arguments.dropFirst().first ?? "http://localhost:8080")!
let session = URLSession(configuration: .default)

func createRoom() async throws -> String {
    var request = URLRequest(url: baseURL.appending(path: "rooms"))
    request.httpMethod = "POST"
    let (data, _) = try await session.data(for: request)
    return try JSONDecoder().decode(RoomCreated.self, from: data).code
}

let code: String
if let given = arguments.first {
    code = RoomCode.normalize(given)
} else {
    code = try await createRoom()
    print("Created room \(code)")
}

var components = URLComponents(url: baseURL.appending(path: "rooms/\(code)/ws"), resolvingAgainstBaseURL: false)!
components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
let socket = session.webSocketTask(with: components.url!)
socket.resume()

func send(_ message: ClientMessage) async throws {
    try await socket.send(.string(try ServerWire.encode(message)))
}

print("Joining \(code) as PokerBot…")
try await send(.join(PlayerIdentity(id: "pokerbot", displayName: "PokerBot")))

while true {
    guard case .string(let text) = try await socket.receive() else { continue }
    let message = try ServerWire.decode(ServerMessage.self, from: text)
    switch message {
    case .welcome(let seat, _):
        print("Seated at \(seat)")
    case .waitingForOpponent:
        print("Waiting for an opponent…")
    case .event(let event):
        print("  \(event)")
    case .rejected(let reason):
        print("Rejected: \(reason)")
    case .opponentLeft:
        print("Opponent left")
    case .state(let view):
        switch view.phase {
        case .waitingForHand, .finished:
            if !view.me.isReady, view.opponent != nil {
                try await Task.sleep(for: .seconds(1))
                try await send(.ready)
            }
        case .inHand:
            guard view.isMyTurn else { continue }
            try await Task.sleep(for: .milliseconds(600))
            if view.legalActions.canCheck {
                try await send(.act(.check))
            } else if view.legalActions.callAmount != nil {
                try await send(.act(.call))
            }
        }
    }
}
