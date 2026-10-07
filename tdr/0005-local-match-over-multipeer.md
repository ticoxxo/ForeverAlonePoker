# 0005. Local play over MultipeerConnectivity with the host as referee

- **Status:** Superseded by 0007 (MultipeerConnectivity is deprecated in iOS 27; the `PeerLink` boundary, `HostedTable`, `WireCodec` and `RemoteGuestBridge` decisions below still stand and are inherited by 0007)
- **Date:** 2026-10-07
- **Feature / area:** `ForeverAlonePoker/Features/LocalMatch`, `ForeverAlonePoker/Shared/Transport/{HostedTable,WireCodec,PeerLink}.swift`, `ForeverAlonePoker/Shared/Transport/Multipeer`

## Context

Two players in the same room should play without any server (tdr/0003). MultipeerConnectivity gives discovery and a reliable encrypted channel over Wi-Fi and Bluetooth, but its delegate callbacks arrive on arbitrary queues and `MCSession` is hard to drive in unit tests.

## Decision

1. **Host referees.** The device that taps *Host a table* runs the authority in a `HostedTable` (the in-process table from tdr/0004, extended with remote connections). The host plays through `InMemoryTransport`; the guest's bytes are relayed by `RemoteGuestBridge` into the same `MatchAuthority`. The guest plays through `PeerLinkTransport`. Both end up with an ordinary `MatchSessionClient`, so `TableView` is unchanged.

2. **`PeerLink` isolates the radio.** It is a tiny `nonisolated` protocol (ordered reliable `Data` in and out, `disconnect`). `MultipeerLink` implements it over `MCSession`; `FakePeerLink.pair()` implements it in tests. Everything protocol-aware (`WireCodec`, transports, bridge) is tested against the fake and never touches MultipeerConnectivity.

3. **Wire format is the versioned JSON envelope** from tdr/0003 (`WireCodec`). A version mismatch in either direction produces a `.rejected` message with a human-readable reason instead of silent failure.

4. **Discovery is minimal.** `MultipeerDiscovery` advertises/browses with service type `fapoker` and auto-accepts the first invitation on the host. Discovery and session state are exposed as `AsyncStream`s; `LocalLobbyModel` (main actor, `@Observable`) consumes them and owns the lifecycle (`host`, `browse`, `invite`, `leave`).

5. **Info.plist** carries `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_fapoker._tcp`, `_fapoker._udp`), added through Xcode's tooling.

## Consequences

- A dropped link forfeits the guest's current hand and holds the seat (room-level reconnect from tdr/0003); the lobby surfaces "Connection lost".
- MultipeerConnectivity suspends when the app is backgrounded; a backgrounded guest will lose the hand. Acceptable for v1, documented in the lobby footer.
- Local matches are refereed by a player's phone and are therefore never ranked (tdr/0003).
- Identity shown to peers is the display name from the profile (tdr/0006 once persistence lands); until then the device name.

## Alternatives considered

- **Both devices run the engine and exchange actions.** Two sources of truth with hidden information would need a commit-reveal shuffle; a single referee is simpler and matches the online model.
- **Game Center nearby matchmaking.** Requires Game Center sign-in on both devices; the user chose iCloud, not Game Center, for identity.
- **Network.framework / Bonjour by hand.** More control, much more code; MultipeerConnectivity already handles both Wi-Fi and Bluetooth.

## Test strategy

- `WireCodecTests`: round trip, version mismatch, malformed input.
- `PeerLinkTransportTests`: guest seating and redaction on the wire, a hand across the link both ways, rejection routing, version mismatch answer, link drop forfeits and holds the seat.
- `MultipeerLink`, `MultipeerDiscovery` and `LocalLobbyModel` are thin adapters verified manually on two physical devices (simulators are unreliable for MultipeerConnectivity).
