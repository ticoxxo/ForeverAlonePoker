# 0021. Search for an open table without a code

- **Status:** Accepted
- **Date:** 2026-10-24
- **Feature / area:** `Server/Sources/PokerServerCore`, `ForeverAlonePoker/Features/OnlineMatch`, `ForeverAlonePoker/Shared/DesignSystem/GlobeAnimationView.swift`

## Context

Online play needed a room code from a friend (tdr/0008, tdr/0013). Players without someone to invite had no way in. The server kept rooms in memory but had no way to list them.

## Decision

1. **The server lists open tables.** `GET /rooms` answers `OpenRooms { rooms: [RoomInfo] }` from `RoomRegistry.openRooms()`. A room is open (`Room.isOpen()`) when it is still in the lobby, not starting, has a free seat and at least one connected socket. The longest-waiting room comes first. `GET /rooms/{code}` now reuses `Room.info()`.
2. **The app polls until it finds a seat.** The online lobby has a "Find a match" button. `OnlineLobbyModel.startMatchSearch()` moves to the `.searching` phase and runs `findMatch()`, which asks `RoomService.openRooms()` every `searchInterval` (3 s). It joins the first room with `OpenRoom.hasFreeSeat`. Full rooms are never entered, even if the server lists one. A failed request counts as an empty answer.
3. **Searching gives up after 3 minutes.** After `searchTimeout` (180 s) the model goes back to `.idle` and sets `showsNoMatchFound`. `OnlineMatchView` then shows the "No match found :(" alert over the lobby. Cancelling or leaving (`cancelSearch()`, `leave()`) stops the search without the alert.
4. **The search screen is the globe.** `MatchSearchView` shows `GlobeAnimationView(showsControls: false)` and a Cancel button. It replaces the lobby while the phase is `.searching`.

## Consequences

- Strangers can play without exchanging codes; any lobby with a free seat can be joined by anyone who searches.
- There is still a race: a room can fill between the listing and the join. Then the server rejects the join as before and the lobby shows that rejection.
- Polling costs one small request every 3 s per searching player. This is fine at the current scale. A push-based queue would replace it if it grows.
- Follow-up: make rooms private (code only) and match players by table size or rating.

## Alternatives considered

- **A server-side matchmaking queue over WebSocket.** Fairer pairing and no polling, but it needs a new protocol message and server state for a first version that only has to find any free seat.
- **Create a room when none is found.** It mixes "search" and "host". The player can already host with "Search opponents".

## Test strategy

- `Server/Tests/PokerServerTests/RoomTests.swift` (`openRooms`): empty, full and waiting rooms; only joinable ones are listed, oldest first.
- `Server/Tests/PokerServerTests/WebSocketFlowTests.swift` (`listOpenRooms`): `GET /rooms` over the router.
- `ForeverAlonePokerTests/Features/OnlineMatch/OnlineMatchTests.swift` (`findMatch`, `noMatchFound`, `cancelSearch`): skips full rooms, times out with the flag set (short injected timeout), cancelling raises no alert. Uses `MatchRoomBuilder` and `TestPlayers`.
- Manual: the globe screen, Cancel, and the alert after a real 3-minute search (previews "Searching for a match" and "No match found").
