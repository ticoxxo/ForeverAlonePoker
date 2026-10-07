import Foundation
import Network
import Observation
import PokerCore

/// Drives a local (same room) match over Network.framework (tdr/0007).
///
/// Host: advertises, shows a passcode, accepts the first guest whose passcode
/// matches, runs the authority in a `HostedTable`, plays through an in-process
/// transport and relays the guest through `RemoteGuestBridge`. Guest: browses,
/// picks a host, enters the passcode, plays through `PeerLinkTransport`.
/// Either way the result is a `MatchSessionClient` for the shared `TableView`.
@Observable
final class LocalLobbyModel {
    enum Role: Equatable {
        case host
        case guest
    }

    enum Phase: Equatable {
        case idle
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
    /// Set once the link is up; the table UI binds to it.
    private(set) var client: MatchSessionClient?

    private var discovery: NearbyDiscovery?
    private var link: NearbyLink?
    private var table: HostedTable?
    private var bridge: RemoteGuestBridge?
    private var eventTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    init(identity: PlayerIdentity) {
        self.identity = identity
    }

    // MARK: - Intents

    func host() {
        guard phase == .idle else { return }
        role = .host
        let passcode = PasscodeKey.random()
        phase = .hosting(passcode: passcode)
        let discovery = NearbyDiscovery()
        self.discovery = discovery
        observe(discovery)
        discovery.startListening(name: identity.displayName, passcode: passcode)
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
        attach(link)
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
            attach(link)
        case .failed(let reason):
            phase = .failed(reason)
        }
    }

    /// Follows the link's connection state; `.ready` means TLS succeeded, so
    /// the passcode matched and the match can start.
    private func attach(_ link: NearbyLink) {
        self.link = link
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await state in link.stateChanges {
                guard let self else { return }
                switch state {
                case .ready:
                    await self.startMatch()
                case .waiting(let error), .failed(let error):
                    await self.linkFailed(error)
                case .cancelled:
                    if self.phase == .connected { self.phase = .failed("Connection lost.") }
                default:
                    break
                }
            }
        }
    }

    private func linkFailed(_ error: NWError) async {
        await link?.disconnect()
        link = nil
        switch role {
        case .guest:
            phase = .failed("Could not connect. Check the passcode and try again.")
        case .host:
            // A guest with the wrong passcode; keep hosting for the next attempt.
            if case .hosting = phase { return }
            phase = .failed(error.localizedDescription)
        case nil:
            break
        }
    }

    private func startMatch() async {
        guard client == nil, let link, let role else { return }
        discovery?.stop()
        let client: MatchSessionClient
        switch role {
        case .host:
            let table = HostedTable(room: MatchRoom(code: "LOCAL"))
            self.table = table
            bridge = RemoteGuestBridge(link: link, table: table)
            client = MatchSessionClient(identity: identity, transport: await table.connect())
        case .guest:
            client = MatchSessionClient(identity: identity, transport: PeerLinkTransport(link: link))
        }
        self.client = client
        phase = .connected
        await client.connect()
    }

    private func tearDown() async {
        eventTask?.cancel()
        stateTask?.cancel()
        bridge?.stop()
        discovery?.stop()
        await link?.disconnect()
        eventTask = nil
        stateTask = nil
        bridge = nil
        discovery = nil
        link = nil
        table = nil
        client = nil
        nearbyPeers = []
    }
}
