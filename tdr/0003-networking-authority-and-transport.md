# 0003. One authoritative referee behind a swappable transport; Hummingbird over WebSockets for the internet, MultipeerConnectivity for local play, no database yet

- **Status:** Accepted
- **Date:** 2026-10-07
- **Feature / area:** `Packages/PokerCore/Sources/PokerCore/{Protocol,Authority}`, `ForeverAlonePoker/Shared/Transport`, `Features/LocalMatch`, `Features/OnlineMatch`, `Server/`

## Context

Players must be able to play over the local network (two devices in the same room) and over the internet. There is no backend or database yet. Poker has hidden information: a client that holds the deck or the opponent's cards can cheat by reading memory. The question raised was "Hummingbird or an API with Postgres?".

Hummingbird is a Swift server framework; Postgres is a database. They are not alternatives: a Hummingbird server may or may not use Postgres.

## Decision

1. **Server-authoritative model, implemented once in CORE.** `MatchRoom` (a pure value) and its `MatchAuthority` actor wrapper own the only unredacted `MatchState`, validate every `ClientMessage`, and emit `Outbound` messages per connection. Clients receive `PlayerView`s that contain their own hole cards and never the deck or the opponent's live cards. Events are public and identical for both players.

2. **The transport is the only thing that differs between modes.** The app defines `MatchTransport` (send `ClientMessage`, receive `ServerMessage` as an `AsyncStream`). Implementations:
   - `InMemoryTransport`: both ends in one process, used by tests and previews.
   - `MultipeerTransport` (local): MultipeerConnectivity over Wi-Fi/Bluetooth. The device that taps **Host** runs `MatchAuthority`; the guest's messages arrive over `MCSession`. Acceptable trust model for friends in the same room.
   - `WebSocketTransport` (internet): `URLSessionWebSocketTask` to the Hummingbird server, which runs `MatchAuthority` per room.

3. **Internet backend: Hummingbird 2 + WebSockets, rooms in memory, no Postgres.** A room is created with a 6-character code via a small REST call; gameplay flows over one WebSocket per player. The server depends on `Packages/PokerCore`. It runs as a single small container.

4. **Postgres is deferred until the server itself must persist something.** On-device data (profile, local history) uses SwiftData (see 0004, planned). Rankings and public profiles are planned in CloudKit's public database (see 0005, planned). Triggers that would bring Postgres in: accounts not expressible through Sign in with Apple + CloudKit, server-side match resume across restarts, or CloudKit Web Services proving too limited for leaderboards.

5. **Wire format.** JSON `Envelope<Message>` with `version` (currently 1). Cards encode as two-character notation. Any shape change bumps `ProtocolVersion.current`.

## Consequences

- The same `TableView` works for local and online play; no feature contains mode-specific rules.
- Local matches are refereed by one of the two phones, so they are never used for rankings.
- Hosting is required for internet play; a Dockerfile and a hosting provider are follow-up work.
- Reconnection is supported at the room level (a dropped connection keeps its seat for the same `PlayerIdentity.id`); token-based session resumption is deferred.
- MultipeerConnectivity disconnects when the app is backgrounded; the lobby must handle a reconnect state. Requires `NSLocalNetworkUsageDescription` and `NSBonjourServices` in Info.plist.

## Alternatives considered

- **Game Center real-time matches (peer-to-peer).** Free matchmaking and NAT traversal with no server, and it also covers nearby play. Rejected for internet play because one device would deal (cheatable) and both players need Game Center sign-in; the user asked for iCloud, not Game Center, for identity.
- **REST API polling.** Simpler hosting, but poker expects sub-second reactions and server push; a WebSocket avoids polling and lets the server drive state.
- **Hummingbird + Postgres from day one.** Nothing needs persisting yet; it would delay the first online hand for no benefit.
- **Mental poker / commit-reveal shuffles for P2P fairness.** Cryptographically sound but far more complex than a server referee for a 1v1 game.

## Test strategy

- `MatchRoomTests` (CORE) prove seating, readiness, redaction (JSON sent to one player never contains the other's cards), rejection routing, leave/forfeit and reconnect.
- `ProtocolTests` prove envelopes and server messages round-trip with the version.
- App: `MatchSessionClient` tests over `InMemoryTransport` play a scripted hand end to end (step 6).
- Server: HummingbirdTesting drives two WebSocket clients through a hand (step 10).
- Manual: local play needs two physical devices; online play needs the server running and two simulators.
