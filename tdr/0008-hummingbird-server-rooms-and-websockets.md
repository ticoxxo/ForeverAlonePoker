# 0008. Hummingbird server: in-memory rooms, one WebSocket per player, same wire protocol

- **Status:** Accepted
- **Date:** 2026-10-07
- **Feature / area:** `Server/`, `ForeverAlonePoker/Shared/Transport/WebSocketTransport.swift`, `ForeverAlonePoker/Features/OnlineMatch`

## Context

tdr/0003 chose a server-authoritative Hummingbird backend over WebSockets with no database. This record covers how that server is shaped and how the app reaches it.

## Decision

1. **Separate SwiftPM package `Server/`** with a library `PokerServerCore` (testable) and a thin `PokerServer` executable. It depends on `../Packages/PokerCore`, `hummingbird` 2.x and `hummingbird-websocket` 2.x. A `Dockerfile` builds a static Linux binary from the repo root.

2. **Rooms are actors in memory.** `RoomRegistry` creates rooms with 6-character codes from an unambiguous alphabet (`RoomCode`) and sweeps rooms idle with no connections. `Room` owns the `MatchAuthority` and one `AsyncStream<ServerMessage>` per connected socket, mirroring the app's `HostedTable`, so every message goes through the same CORE referee and replies are delivered in order per connection.

3. **REST is tiny; gameplay is WebSocket.**
   - `GET /health`
   - `POST /rooms` → `{ "code": "ABC234" }`
   - `GET /rooms/{code}` → `{ code, seatsTaken, connected }` or 404
   - `GET /rooms/{code}/ws` → WebSocket upgrade (refused for unknown codes). Text frames carry the JSON `Envelope` from tdr/0003 (`ServerWire` is byte-compatible with the app's `WireCodec`). A version mismatch gets a `.rejected` reply.
   Socket close = `authority.disconnect`, which forfeits a hand in progress and holds the seat for the same `PlayerIdentity.id` (reconnect by rejoining).

4. **App side.** `WebSocketTransport` implements `MatchTransport` over `URLSessionWebSocketTask`, behind a `WebSocketConnection` protocol so tests use a fake. `HTTPRoomService` creates and checks rooms. `OnlineLobbyModel` drives create/join and hands a `MatchSessionClient` to the shared `TableView`; the room code is shown in the toolbar for sharing. The server base URL lives on `PlayerProfile.serverURLOverride` (SwiftData) and is edited in Profile; default `http://localhost:8080` for development.

5. **Dev bot.** `PokerBot` (executable in `Server/`) joins a room over WebSocket and readies/checks/calls, so one device can exercise online play end to end. Not a product feature.

## Consequences

- No persistence on the server: a restart drops rooms. Acceptable for now (tdr/0003 triggers unchanged).
- The server must be reachable from devices (hosting + TLS termination are deployment concerns, not code).
- Identity is still the local `PlayerIdentity`; ranked identity (Sign in with Apple) arrives with tdr/0006 tier 2.

## Alternatives considered

- **Reusing `HostedTable` on the server.** It lives in the app target and would drag app code into the server; a 60-line actor is cheaper than a third shared package for now.
- **Binary frames.** Text JSON is debuggable with any client; payloads are tiny.
- **REST polling.** Rejected in tdr/0003.

## Test strategy

- `Server/Tests/PokerServerTests`: room code format and normalisation, registry uniqueness and sweeping, room routing; HTTP create/lookup/404; a full hand across two live WebSockets including opponent-left on close; unknown room refuses upgrade; version mismatch rejection. Run with `swift test --package-path Server`.
- App: `WebSocketTransportTests` with a fake connection; `OnlineLobbyModelTests` with a fake room service and an in-process authority.
- Manual: run `swift run --package-path Server PokerServer`, play from the simulator against `swift run --package-path Server PokerBot <code>`.
