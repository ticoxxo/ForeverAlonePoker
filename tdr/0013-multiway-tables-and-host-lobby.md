# 0013. Seat two to six players, gathered in a host-run lobby

- **Status:** Accepted (supersedes in part 0003, 0007, 0008, 0009, 0010); §2 short all-ins and §4 Ready between hands and dropped players superseded by 0014
- **Date:** 2026-10-16
- **Feature / area:** `Packages/PokerCore/Sources/PokerCore/{Hand,Match,Authority,Protocol,Rating}`, `Server/Sources/PokerServerCore`, `ForeverAlonePoker/Shared/{Transport,Session,Identity,DesignSystem}`, `Features/{LocalMatch,OnlineMatch,Table}`

## Context

Every layer assumed heads-up: `Seat` was a two-case enum with `.opponent`, the hand engine had no side pots, the room dealt when two players pressed Ready, the nearby host accepted one guest, the server published 1v1 Elo and the table drew one opponent. Players asked for tables of up to six, where the host picks the size, opens the table, sees who joined (name and picture) and starts when they like, with a little patience for players still connecting. Heads-up must keep starting by itself.

## Decision

1. **Seats are numbers.** `Seat` is a struct over its zero-based index (`.one` … `.six` kept as constants) and still encodes as a bare integer. `TableSize.range` is `2...6`; `MatchConfiguration.maxPlayers` (default 2) sizes the table.
2. **The engine plays N seats.** `HandEngine` takes one stack per seat; a seat with 0 chips sits the hand out (`SeatState.isSittingOut`, treated as folded). Heads-up keeps button = small blind; with three or more the two seats after the button post and the seat after the big blind opens; after the flop the first live seat after the button acts. A raise reopens the action for everyone. Showdown splits the pot into a main pot and side pots by each live player's commitment (`HandResult.pots`); uncalled chips go back; odd chips go to the first winner clockwise from the button. Dealing stays fixed: two cards to each seat dealt in, in seat order, then the board. A short all-in raise reopens the action like a full raise (simplification; it never allows a raise against nobody).
3. **Matches eliminate.** `MatchState.players` lists the seats in the match; the button moves to the next seat with chips; busted seats are recorded in `eliminations` (players busted by the same hand are ordered by the chips they started it with) and `place(of:)` gives finishing positions. A player who leaves mid-match is `retire`d: folded now, chips removed when the hand settles. The match is over when one player has chips.
4. **The room has a lobby.** `MatchRoom` starts in the `.lobby` phase; the first player to join is the host (handed to the lowest seat if they leave the lobby). Heads-up deals as soon as the second player sits down. A bigger table deals when the host sends `ClientMessage.startMatch` and the hosting layer then calls `beginMatch()`; from then on only seated players may (re)join. Between hands every connected player who still has chips must be Ready; disconnected players are dealt in and folded when the action reaches them. Knocked-out players stay and watch (`PlayerSummary.isBusted`, `place`). A finished match nobody can rematch reopens the lobby when someone new arrives.
5. **The grace period lives in the hosting layer.** `MatchAuthority.beginAfterGrace` waits until no open connection is still unseated, or the grace period (5 s) passes, then deals. The server `Room` counts open WebSockets; `HostedTable` counts local transports, attached guests and guests still in their TLS handshake (`expectRemote`).
6. **The protocol says who is where.** `PlayerView.players` lists every other seated player clockwise; `PlayerView.table` (`TableInfo`) carries the size, the host, whether the start is pending, and the Elo flags; `PlayerView.actor` says whose turn it is. `.waitingForOpponent` and `.opponentLeft` are replaced by the lobby state and `.playerLeft(seat:name:)`. `ProtocolVersion` is 3.
7. **Elo, multiway.** Ratings change only when every seated player is ranked (`MatchRoom.isEloEnabled`; rooms on a server with ranked play are `isRankedCapable`). Otherwise the lobby and the table say "Elo gain disabled for this game". `EloCalculator.updateMultiway` scores the winner as beating each loser: every loser takes their full head-to-head loss; the winner's K-factor is shared across the pairings so a six-max win moves them about as much as one heads-up win. With one loser it equals `update`. `RankingService.record(winner:losers:)` stores every row; every connected player gets `.rated`.
8. **Pictures come from public profiles.** The lobby and the table show `PublicProfile` avatars (tdr/0010) fetched by `AvatarLoader` through `CloudKitAvatarProvider`, each player once, giving up after 3 s; without a picture the player's initials are drawn.
9. **Apps.** Local and online both show a "Max players" picker (default 2) and a "Search opponents" button; the picker is disabled while searching. `NearbyDiscovery` accepts up to `maxPlayers - 1` guests and frees a slot when a guest's handshake fails. `POST /rooms` takes an optional `{"maxPlayers": n}`. The table fans the other players over the top arc (`SeatLayout`).

## Consequences

- Heads-up behaves as before except that the first hand needs no Ready press.
- Every place that used `Seat.opponent` or `PlayerView.opponent` must think in lists; `opponent` remains a convenience that is `nil` unless exactly one other player is seated.
- Chips of a player who leaves mid-match leave with them, so totals at the table can shrink.
- Old builds cannot talk to new ones (protocol 3).
- Follow-up: dead-button rules, action timers for absent players, and partial-raise reopening rules if competitive play needs them.

## Alternatives considered

- **Keep `Seat` an enum with six cases.** Encodes the same, but loses arithmetic around the table and invites `switch` statements that must change with the size.
- **Ready-gate the first hand of every table.** The host's Start already says "go"; asking every player again is friction.
- **Send pictures in the join message.** Works without iCloud but grows every join and lobby broadcast; ranked players already publish one.
- **Pairwise Elo across every finishing position.** Fairer for the middle places, but not what was asked: only the winner gains.

## Test strategy

- `Packages/PokerCore/Tests/PokerCoreTests/MultiwayTests.swift`: three-handed blinds and order, raise reopening, sit-outs, side pots, odd chips, forfeits, eliminations and places, retirement, lobby/host/start/grace/full/Elo rules, absent-player folding, spectators, multiway rematch, multiway Elo. Builders: `HandStateBuilder.stacks(...)` with default cards for seats three to six, `MatchStateBuilder.players(_:)`, `MatchRoomBuilder.maxPlayers(_:)`/`rankedCapable()`, `MatchRoom.seatThreeAndDeal()`, `TestPlayers.dave`.
- `Server/Tests/PokerServerTests`: `RoomStartTests` (immediate start, grace waits for an open socket, late joiner dealt in), `CreateRoomRequestTests`, `RankedRoomTests.publishesMultiway`.
- `ForeverAlonePokerTests`: `MatchSessionClientTests.multiwayStart`/`departureNamed`, `OnlineLobbyModelTests` (size sent and locked, host starts), `TableStatusTests`, `SeatLayoutTests`, `HandOutcomeTests.sidePots`, `AvatarLoaderTests`, `IdentityStoreTests.recordsPlace`.
- Manual: several devices on one network hosting a 3–6 player local table; `swift run PokerBot CODE` several times against an online table.
