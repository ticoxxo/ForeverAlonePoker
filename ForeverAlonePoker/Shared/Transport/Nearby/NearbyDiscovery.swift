import Foundation
import Network

/// A nearby table found over Bonjour.
nonisolated struct NearbyPeer: Identifiable, Hashable, Sendable {
    let name: String
    let endpoint: NWEndpoint

    var id: NWEndpoint { endpoint }
}

/// Finds and opens links to nearby devices with Network.framework.
/// Host: `startListening` advertises a Bonjour service and accepts the first
/// guest whose passcode matches. Guest: `startBrowsing` lists hosts and
/// `connect` opens a link with the passcode the host showed.
nonisolated final class NearbyDiscovery: @unchecked Sendable {
    enum Event: Sendable {
        case listening
        case found(NearbyPeer)
        case lost(NearbyPeer)
        /// A guest completed the TLS handshake with the right passcode.
        case guestConnected(NearbyLink)
        case failed(String)
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let queue = DispatchQueue(label: "ForeverAlonePoker.nearby.discovery")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var acceptedLink: NearbyLink?

    init() {
        (events, continuation) = AsyncStream<Event>.makeStream()
    }

    // MARK: - Host

    func startListening(name: String, passcode: String) {
        do {
            let listener = try NWListener(using: NearbyParameters.make(passcode: passcode))
            listener.service = NWListener.Service(name: name, type: NearbyParameters.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.continuation.yield(.listening)
                case .failed(let error): self?.continuation.yield(.failed(error.localizedDescription))
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                // Heads-up table: one guest. Anyone else is turned away.
                guard acceptedLink == nil else {
                    connection.cancel()
                    return
                }
                let link = NearbyLink(connection: connection)
                acceptedLink = link
                link.start()
                continuation.yield(.guestConnected(link))
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            continuation.yield(.failed(error.localizedDescription))
        }
    }

    // MARK: - Guest

    func startBrowsing() {
        let browser = NWBrowser(
            for: .bonjour(type: NearbyParameters.serviceType, domain: nil),
            using: NearbyParameters.browsing()
        )
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.continuation.yield(.failed(error.localizedDescription))
            }
        }
        browser.browseResultsChangedHandler = { [weak self] _, changes in
            for change in changes {
                switch change {
                case .added(let result):
                    if let peer = Self.peer(from: result) { self?.continuation.yield(.found(peer)) }
                case .removed(let result):
                    if let peer = Self.peer(from: result) { self?.continuation.yield(.lost(peer)) }
                default:
                    break
                }
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func connect(to peer: NearbyPeer, passcode: String) -> NearbyLink {
        let connection = NWConnection(to: peer.endpoint, using: NearbyParameters.make(passcode: passcode))
        let link = NearbyLink(connection: connection)
        link.start()
        return link
    }

    func stop() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
    }

    private static func peer(from result: NWBrowser.Result) -> NearbyPeer? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        return NearbyPeer(name: name, endpoint: result.endpoint)
    }
}
