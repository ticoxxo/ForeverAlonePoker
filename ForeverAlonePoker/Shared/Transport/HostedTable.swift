import Foundation
import PokerCore

/// A table whose authority runs in this process. Players connect either
/// locally (`connect()` returns an in-process transport) or remotely
/// (`attachRemote` registers a delivery closure for a peer on another device).
/// Every message, local or remote, goes through the same `MatchAuthority`, and
/// its replies are routed back to whichever connection should receive them.
///
/// Used by tests and previews (local players), and by the nearby host (host
/// local, guests remote). The Hummingbird server does the equivalent with
/// WebSockets and does not use this type.
///
/// When the host starts a table of three or more (tdr/0013) the first hand is
/// dealt once every connection, including guests still completing their
/// handshake (`expectRemote`), has taken a seat, or after `graceInterval`.
///
/// Between hands (tdr/0014) the next hand is dealt `nextHandPause` after the
/// last one ends, and a player who dropped is knocked out if they have not
/// rejoined within `absenceTimeout`.
actor HostedTable {
    nonisolated static let defaultGraceInterval: Duration = .seconds(5)
    nonisolated static let defaultNextHandPause: Duration = .seconds(4)
    nonisolated static let defaultAbsenceTimeout: Duration = .seconds(60)

    let authority: MatchAuthority
    private var locals: [ConnectionID: AsyncStream<ServerMessage>.Continuation] = [:]
    private var remotes: [ConnectionID: @Sendable (ServerMessage) -> Void] = [:]
    private var expected: Set<ConnectionID> = []
    private let graceInterval: Duration
    private var graceTask: Task<Void, Never>?
    private let nextHandPause: Duration
    private var nextHandTask: Task<Void, Never>?
    private let absenceTimeout: Duration
    private var absenceTasks: [MatchRoom.Absence: Task<Void, Never>] = [:]

    init(
        authority: MatchAuthority,
        graceInterval: Duration = HostedTable.defaultGraceInterval,
        nextHandPause: Duration = HostedTable.defaultNextHandPause,
        absenceTimeout: Duration = HostedTable.defaultAbsenceTimeout
    ) {
        self.authority = authority
        self.graceInterval = graceInterval
        self.nextHandPause = nextHandPause
        self.absenceTimeout = absenceTimeout
    }

    init(
        room: MatchRoom,
        graceInterval: Duration = HostedTable.defaultGraceInterval,
        nextHandPause: Duration = HostedTable.defaultNextHandPause,
        absenceTimeout: Duration = HostedTable.defaultAbsenceTimeout
    ) {
        self.init(
            authority: MatchAuthority(room: room),
            graceInterval: graceInterval,
            nextHandPause: nextHandPause,
            absenceTimeout: absenceTimeout
        )
    }

    // MARK: - Local connections

    func connect(id: ConnectionID = ConnectionID(UUID().uuidString)) -> InMemoryTransport {
        let (stream, continuation) = AsyncStream<ServerMessage>.makeStream()
        locals[id] = continuation
        return InMemoryTransport(id: id, table: self, incoming: stream)
    }

    fileprivate func send(_ message: ClientMessage, from id: ConnectionID) async throws {
        guard locals[id] != nil else { throw TransportError.notConnected }
        await receive(message, from: id)
        if case .startMatch = message { await scheduleBegin() }
        await scheduleNextHand()
    }

    fileprivate func close(_ id: ConnectionID) async {
        guard let continuation = locals.removeValue(forKey: id) else { return }
        continuation.finish()
        await disconnect(id)
    }

    // MARK: - Remote connections

    /// A guest is connecting (handshake in progress). Counted as still joining
    /// during the start grace period until it attaches or is forgotten.
    func expectRemote(_ id: ConnectionID) {
        expected.insert(id)
    }

    func forgetRemote(_ id: ConnectionID) {
        expected.remove(id)
    }

    /// Registers a remote player. `deliver` is called, in order, with every
    /// message the authority addresses to this connection.
    func attachRemote(id: ConnectionID, deliver: @escaping @Sendable (ServerMessage) -> Void) {
        expected.remove(id)
        remotes[id] = deliver
    }

    func receiveRemote(_ message: ClientMessage, from id: ConnectionID) async {
        guard remotes[id] != nil else { return }
        await receive(message, from: id)
        if case .startMatch = message { await scheduleBegin() }
        await scheduleNextHand()
    }

    func detachRemote(_ id: ConnectionID) async {
        expected.remove(id)
        guard remotes.removeValue(forKey: id) != nil else { return }
        await disconnect(id)
    }

    /// Leaving a match in play holds the seat like a drop (tdr/0016).
    private func receive(_ message: ClientMessage, from id: ConnectionID) async {
        let (outbound, absence) = await authority.receive(message, from: id)
        deliver(outbound)
        if let absence { scheduleExpiry(of: absence) }
    }

    private func disconnect(_ id: ConnectionID) async {
        let (outbound, absence) = await authority.disconnect(id)
        deliver(outbound)
        if let absence { scheduleExpiry(of: absence) }
        await scheduleNextHand()
    }

    // MARK: - Starting

    private func scheduleBegin() async {
        guard graceTask == nil, await authority.isStarting else { return }
        let grace = graceInterval
        graceTask = Task { [weak self] in
            guard let self else { return }
            let outbound = await self.authority.beginAfterGrace(grace: grace) { [weak self] in
                await self?.joiningConnections() ?? []
            }
            await self.finishBegin(outbound)
        }
    }

    private func joiningConnections() -> Set<ConnectionID> {
        Set(locals.keys).union(remotes.keys).union(expected)
    }

    private func finishBegin(_ outbound: [Outbound]) async {
        graceTask = nil
        deliver(outbound)
        await scheduleNextHand()
    }

    /// Waits for a pending start to deal. For tests.
    func waitForStart() async {
        await graceTask?.value
    }

    // MARK: - Between hands

    /// Deals the next hand after the pause whenever one is due.
    private func scheduleNextHand() async {
        guard nextHandTask == nil, let ticket = await authority.nextHandTicket else { return }
        let pause = nextHandPause
        nextHandTask = Task { [weak self] in
            guard let self else { return }
            let outbound = await self.authority.dealNextHand(ticket: ticket, after: pause)
            await self.finishNextHand(outbound)
        }
    }

    private func finishNextHand(_ outbound: [Outbound]) async {
        nextHandTask = nil
        deliver(outbound)
        await scheduleNextHand()
    }

    /// Waits for a scheduled next hand. For tests.
    func waitForNextHand() async {
        await nextHandTask?.value
    }

    /// Knocks the player out if they are still away after the timeout.
    private func scheduleExpiry(of absence: MatchRoom.Absence) {
        let timeout = absenceTimeout
        absenceTasks[absence] = Task { [weak self] in
            guard let self else { return }
            let outbound = await self.authority.expire(absence, after: timeout)
            await self.finishExpiry(absence, outbound)
        }
    }

    private func finishExpiry(_ absence: MatchRoom.Absence, _ outbound: [Outbound]) async {
        absenceTasks[absence] = nil
        deliver(outbound)
        await scheduleNextHand()
    }

    /// Waits for every pending absence to expire or lapse. For tests.
    func waitForAbsences() async {
        for task in absenceTasks.values { await task.value }
    }

    // MARK: - Delivery

    func deliver(_ outbound: [Outbound]) {
        for item in outbound {
            if let continuation = locals[item.to] {
                continuation.yield(item.message)
            } else if let remote = remotes[item.to] {
                remote(item.message)
            }
        }
    }
}

/// Transport for a player in the same process as the `HostedTable`.
nonisolated struct InMemoryTransport: MatchTransport {
    let id: ConnectionID
    private let table: HostedTable
    let incoming: AsyncStream<ServerMessage>

    fileprivate init(id: ConnectionID, table: HostedTable, incoming: AsyncStream<ServerMessage>) {
        self.id = id
        self.table = table
        self.incoming = incoming
    }

    func send(_ message: ClientMessage) async throws {
        try await table.send(message, from: id)
    }

    func close() async {
        await table.close(id)
    }
}
