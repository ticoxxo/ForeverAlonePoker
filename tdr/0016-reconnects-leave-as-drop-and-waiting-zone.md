# 0016. Let players come back: Leave is a drop, clients reconnect, folded players wait at the side

- **Status:** Accepted (supersedes in part 0014: leaving mid-match)
- **Date:** 2026-10-17
- **Feature / area:** `Packages/PokerCore/Sources/PokerCore/Authority/MatchRoom.swift`, `Server/Sources/PokerServerCore/{Room,PokerServerApp}.swift`, `ForeverAlonePoker/Shared/{Session/MatchSessionClient.swift,Transport/HostedTable.swift,Transport/WebSocketTransport.swift}`, `ForeverAlonePoker/Features/{Table,OnlineMatch,LocalMatch}`

## Context

Testing tdr/0014 on devices showed:

- Leaving the table screen (the Leave button, or navigating back) sent `.leave`, which knocked the player out for good. Coming back with the room code was refused with "The game has already started."
- A phone that drops off the network can stay "connected" on the server until its socket times out, so even a real reconnect could be refused.
- A player whose own connection dropped saw nothing.
- At bigger tables, players out of the hand took space in the ring.

## Decision

1. **Leave mid-match is a drop.** Once the match has begun and until it is over, `.leave` folds the player's live hand at once and holds the seat, chips included, like a dropped connection: the same `Absence` and 60 s expiry (tdr/0014). The hosting layers learn about it through `MatchAuthority.receive`, which returns the absence a message started. Only when the absence expires is the player knocked out with their chips (`.playerLeft`). In the lobby or after the match is over, `.leave` still frees the seat at once.
2. **Rejoining takes the seat back.** A join from the identity holding a seat gets it, whether the old connection is gone or still attached (a stale socket the server hasn't noticed). The old connection is told "You joined this table from another device." and its late `disconnect` matches no seat. A player who rejoins mid-hand stays folded until the next hand.
3. **Online clients reconnect by themselves.** `MatchSessionClient` takes a `reconnect` transport factory (online only; `OnlineLobbyModel` passes one). When the connection drops after the player was seated, it moves to `.reconnecting`. Every 2 s for up to 60 s it opens a new transport and joins again. `.welcome` restores `.seated`; a rejection means the seat expired ("You were away too long and lost your seat."). `leave()` never reconnects. `WebSocketTransport` pings every 10 s and closes a socket that stops answering. The server pings every 10 s (`WebSocketServerConfiguration.autoPing`).
4. **The table shows connection state.**
   - Your own connection: the table is blurred behind a card. While retrying it shows "Unstable connection" with a spinner and "Check your connection."; once it gives up, the reason and Leave. A local guest, with no reconnect, goes straight to the second card.
   - Other players: `PlayerAvatar` dims a reconnecting player's picture behind `wifi.slash` and spins a ring around it. Heads-up, the opponent now shows their picture too.
5. **Waiting zone.** At tables of three or more, `TableSeating` splits the other players: anyone knocked out, or folded in the current or just-finished hand, waits in a slim column at the trailing edge. That's 30 pt pictures with no name, still able to emote. The ring re-lays out the rest. Folded players come back when the next hand is dealt.
6. **Emote bubble.** A speech bubble that fits the emoji, placed above the top-right of the picture with its tail touching it (`View.emoteBubble`), smaller in the waiting zone.

## Consequences

- Closing the app or the table screen by accident no longer costs a player the match, if they come back within a minute.
- A deliberate leave takes 60 s to free the seat, so the others play a few hands with an absent player auto-folded.
- The identity id is all a reclaim needs, as before; a ranked seat taken over by an unranked join becomes unranked (Elo off), as with any unranked join.
- Follow-up: automatic reconnects for local guests (rediscovery and passcode handshake).

## Alternatives considered

- **Keep Leave permanent and only fix real drops.** Leaving the screen is easy to do by accident; the user chose to treat it as a drop.
- **Rejoin as a spectator after leaving.** Simpler, but costs the player their chips for a mistake.
- **Show folded players dimmed in place.** Keeps the ring crowded at six-max.

## Test strategy

- `PokerCoreTests`:
  - `MatchRoomTests`: `leave`, `leaveExpires`, `leaveAndReturn`, `takeover`, `leaveOutsidePlay`, `authorityLeave`.
  - `MultiwayTests.leaveMidMatch`: back folded until the next hand.
- `PokerServerTests/RoomTests.swift` `RoomTimingTests.leaveExpires`.
- `ForeverAlonePokerTests`:
  - `MatchSessionClientTests`: `leaving`, `reconnects`, `seatLost`, `leaveDoesNotReconnect`, `departureNamed`.
  - `WebSocketTransportTests.heartbeat`.
  - `TableSeatingTests`.
- Manual on devices:
  - Bubble placement.
  - The reconnecting ring.
  - The blurred card: turn on airplane mode for a few seconds.
  - Leave and rejoin with the code within 60 s.
  - The waiting zone at a 3–6 player table with PokerBots.
