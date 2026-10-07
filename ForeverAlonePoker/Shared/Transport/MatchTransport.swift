import PokerCore

/// One player's connection to the match authority, whatever carries it
/// (in-process pipe, MultipeerConnectivity, WebSocket). See tdr/0003.
///
/// The only mode-specific code in the app lives behind this protocol; the
/// session client and every view are transport-agnostic.
nonisolated protocol MatchTransport: Sendable {
    /// Messages from the authority, in order. The stream finishes when the
    /// connection closes for any reason.
    var incoming: AsyncStream<ServerMessage> { get }

    func send(_ message: ClientMessage) async throws

    /// Closes the connection. Safe to call more than once.
    func close() async
}

nonisolated enum TransportError: Error, Equatable {
    case notConnected
    case encodingFailed
}
