import Foundation
import Network
import Observation
import PokerCore

/// Drives a local (same room) match over Network.framework (tdr/0007, tdr/0013).
///
/// Host: picks the table size, then "Search opponents" advertises with a
/// passcode, runs the authority in a `HostedTable`, seats the host through an
/// in-process transport and relays each guest whose passcode matches through
/// its own `RemoteGuestBridge`. A heads-up table deals when the guest sits
/// down; a bigger one when the host presses Start. Guest: browses, picks a
/// host, enters the passcode, plays through `PeerLinkTransport`. Either way the
/// result is a `MatchSessionClient` for the lobby list and the shared `TableView`.
@Observable
final class LocalLobbyModel {
    enum Role: Equatable {
        case host
        case guest
    }

    enum Phase: Equatable {
        case idle
        /// The host is choosing the table size.
        case setup
        /// Advertising with this passcode; the table size is locked.
        case hosting(passcode: String)
        case browsing
        case passcodeEntry(NearbyPeer)
        case connecting(peerName: String)
        case connected
        case failed(String)
    }

    let identity: PlayerIdentity
    private(set) var role: Role?
    private(set) var phase: Phase = .idle
    private(set) var nearbyPeers: [NearbyPeer] = []
    /// Set once seated; the lobby list and the table UI bind to it.
    private(set) var client: MatchSessionClient?
    /// Seats at the hosted table, `TableSize.range`. Only editable during setup.
    /// Clamped in a setter, not `didSet`: writing back from an `@Observable`
    /// property's `didSet` re-enters the setter and recurses forever.
    var maxPlayers: Int {
        get { chosenMaxPlayers }
        set {
            guard canChooseTableSize, TableSize.range.contains(newValue) else { return }
            chosenMaxPlayers = newValue
        }
    }
    private var chosenMaxPlayers = TableSize.minPlayers

    private var discovery: NearbyDiscovery?
    /// Guest side: the one link to the host.
    private var link: NearbyLink?
    private var table: HostedTable?
    /// Host side: every guest link and its bridge into the table.
    private var guestLinks: [ConnectionID: NearbyLink] = [:]
    private var bridges: [ConnectionID: RemoteGuestBridge] = [:]
    private var guestTasks: [ConnectionID: Task<Void, Never>] = [:]
    private var eventTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private let graceInterval: Duration

    init(identity: PlayerIdentity, graceInterval: Duration = HostedTable.defaultGraceInterval) {
        self.identity = identity
        self.graceInterval = graceInterval
    }

    /// The picker is enabled only before searching starts.
    var canChooseTableSize: Bool { phase == .setup || phase == .idle }

    /// The match has been dealt; the table replaces the lobby.
    var isPlaying: Bool {
        guard let client, let view = client.view else { return false }
        return view.phase != .lobby
    }

    // MARK: - Intents

    func host() {
        guard phase == .idle else { return }
        role = .host
        phase = .setup
    }

    /// Opens the table: seats the host and starts advertising.
    func startSearching() async {
        guard role == .host, phase == .setup else { return }
        let passcode = PasscodeKey.random()
        phase = .hosting(passcode: passcode)
        let table = HostedTable(
            room: MatchRoom(code: "LOCAL", configuration: MatchConfiguration(maxPlayers: maxPlayers)),
            graceInterval: graceInterval
        )
        self.table = table
        let client = MatchSessionClient(identity: identity, transport: await table.connect())
        self.client = client
        await client.connect()

        let discovery = NearbyDiscovery()
        self.discovery = discovery
        observe(discovery)
        discovery.startListening(name: identity.displayName, passcode: passcode, maxGuests: maxPlayers - 1)
    }

    /// Closes the table before it starts, back to choosing its size.
    func stopSearching() async {
        guard role == .host, case .hosting = phase, !isPlaying else { return }
        await client?.leave()
        await tearDown()
        phase = .setup
    }

    /// Host: deal now. Guests still completing their handshake get a short
    /// grace period; nobody new is accepted afterwards.
    func startGame() async {
        guard role == .host, let client, client.isHost else { return }
        await client.startMatch()
        discovery?.stop()
    }

    /// The match was dealt: stop advertising the table.
    func stopAdvertising() {
        guard role == .host else { return }
        discovery?.stop()
    }

    func browse() {
        guard phase == .idle else { return }
        role = .guest
        phase = .browsing
        let discovery = NearbyDiscovery()
        self.discovery = discovery
        observe(discovery)
        discovery.startBrowsing()
    }

    func select(_ peer: NearbyPeer) {
        guard role == .guest, phase == .browsing else { return }
        phase = .passcodeEntry(peer)
    }

    func cancelPasscodeEntry() {
        guard case .passcodeEntry = phase else { return }
        phase = .browsing
    }

    func join(_ peer: NearbyPeer, passcode: String) {
        guard role == .guest, let discovery else { return }
        phase = .connecting(peerName: peer.name)
        discovery.stop()
        let link = discovery.connect(to: peer, passcode: passcode)
        attachToHost(link)
    }

    func leave() async {
        await client?.leave()
        await tearDown()
        phase = .idle
        role = nil
    }

    // MARK: - Wiring

    private func observe(_ discovery: NearbyDiscovery) {
        eventTask = Task { [weak self] in
            for await event in discovery.events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: NearbyDiscovery.Event) async {
        switch event {
        case .listening:
            break
        case .found(let peer):
            if !nearbyPeers.contains(peer) { nearbyPeers.append(peer) }
        case .lost(let peer):
            nearbyPeers.removeAll { $0 == peer }
        case .guestConnected(let link):
            await admit(link)
        case .failed(let reason):
            phase = .failed(reason)
        }
    }

    /// Host: follows one guest's link. `.ready` means TLS succeeded, so the
    /// passcode matched and the guest is bridged into the table; until then
    /// the table counts them as still joining.
    private func admit(_ link: NearbyLink) async {
        guard role == .host, let table else {
            await link.disconnect()
            return
        }
        let id = ConnectionID(UUID().uuidString)
        guestLinks[id] = link
        await table.expectRemote(id)
        guestTasks[id] = Task { [weak self] in
            for await state in link.stateChanges {
                guard let self else { return }
                switch state {
                case .ready:
                    if self.bridges[id] == nil {
                        self.bridges[id] = RemoteGuestBridge(link: link, table: table, connectionID: id)
                    }
                case .waiting, .failed, .cancelled:
                    // Wrong passcode, or the guest went away.
                    await self.dropGuest(id)
                    return
                default:
                    break
                }
            }
        }
    }

    private func dropGuest(_ id: ConnectionID) async {
        guard let link = guestLinks.removeValue(forKey: id) else { return }
        bridges.removeValue(forKey: id)?.stop()
        guestTasks.removeValue(forKey: id)
        await table?.detachRemote(id)
        await table?.forgetRemote(id)
        await link.disconnect()
        discovery?.releaseGuestSlot()
    }

    /// Guest: follows the link to the host; `.ready` means the passcode matched.
    private func attachToHost(_ link: NearbyLink) {
        self.link = link
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await state in link.stateChanges {
                guard let self else { return }
                switch state {
                case .ready:
                    await self.seatGuest()
                case .waiting, .failed:
                    await self.hostLinkFailed()
                case .cancelled:
                    if self.phase == .connected { self.phase = .failed("Connection lost.") }
                default:
                    break
                }
            }
        }
    }

    private func hostLinkFailed() async {
        await link?.disconnect()
        link = nil
        phase = .failed("Could not connect. Check the passcode and try again.")
    }

    private func seatGuest() async {
        guard client == nil, role == .guest, let link else { return }
        let client = MatchSessionClient(identity: identity, transport: PeerLinkTransport(link: link))
        self.client = client
        phase = .connected
        await client.connect()
    }

    private func tearDown() async {
        eventTask?.cancel()
        stateTask?.cancel()
        for task in guestTasks.values { task.cancel() }
        for bridge in bridges.values { bridge.stop() }
        discovery?.stop()
        await link?.disconnect()
        for guest in guestLinks.values { await guest.disconnect() }
        eventTask = nil
        stateTask = nil
        guestTasks = [:]
        bridges = [:]
        guestLinks = [:]
        discovery = nil
        link = nil
        table = nil
        client = nil
        nearbyPeers = []
    }
}
