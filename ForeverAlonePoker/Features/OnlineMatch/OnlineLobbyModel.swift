import Foundation
import Observation
import PokerCore

/// Creates or joins a room on the server and hands the table a session client.
@Observable
final class OnlineLobbyModel {
    enum Phase: Equatable {
        case idle
        case working
        case connected(roomCode: String)
        case failed(String)
    }

    let identity: PlayerIdentity
    private(set) var phase: Phase = .idle
    private(set) var client: MatchSessionClient?
    private let service: any RoomService
    /// Ranked session token (tdr/0010); `nil` plays unranked.
    private let sessionToken: String?

    init(identity: PlayerIdentity, service: any RoomService, sessionToken: String? = nil) {
        self.identity = identity
        self.service = service
        self.sessionToken = sessionToken
    }

    var roomCode: String? {
        if case .connected(let code) = phase { return code }
        return nil
    }

    func createRoom() async {
        guard phase == .idle else { return }
        phase = .working
        do {
            let code = try await service.createRoom()
            await connect(to: code)
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    func join(code rawCode: String) async {
        guard phase == .idle else { return }
        phase = .working
        let code = HTTPRoomService.normalize(rawCode)
        do {
            try await service.checkRoom(code)
            await connect(to: code)
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    func leave() async {
        await client?.leave()
        client = nil
        phase = .idle
    }

    /// Back to the lobby after a failure.
    func reset() {
        phase = .idle
    }

    private func connect(to code: String) async {
        let client = MatchSessionClient(identity: identity, transport: service.makeTransport(roomCode: code), sessionToken: sessionToken)
        self.client = client
        phase = .connected(roomCode: code)
        await client.connect()
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case RoomServiceError.roomNotFound: String(localized: "No table with that code.")
        case RoomServiceError.invalidCode: String(localized: "Enter the 6-character code.")
        case RoomServiceError.server(let status): String(localized: "The server answered with an error (\(status)).")
        case RoomServiceError.badResponse: String(localized: "Unexpected reply from the server.")
        default: String(localized: "Could not reach the server. Check the server address in your profile.")
        }
    }
}
