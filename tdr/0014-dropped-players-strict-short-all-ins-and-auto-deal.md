# 0014. Hold dropped seats on a timer, play short all-ins strictly, and deal the next hand automatically

- **Status:** Accepted (supersedes in part 0013 §2 and §4); leaving mid-match superseded by 0016
- **Date:** 2026-10-17
- **Feature / area:** `Packages/PokerCore/Sources/PokerCore/{Hand,Authority,Protocol}`, `Server/Sources/PokerServerCore/Room.swift`, `Server/Sources/PokerBot`, `ForeverAlonePoker/Shared/{Transport/HostedTable.swift,Session}`, `ForeverAlonePoker/Features/Table`

## Context

tdr/0013 shipped multiway tables with simplifications that hurt play at bigger tables:

- A dropped connection folded the player at once, even when the action was elsewhere and they could have come back in time. A dropped seat was held forever, so a player who never returned was dealt in and folded on every hand.
- A short all-in raise reopened raising for everyone, which strict No-Limit rules do not allow.
- Every connected player with chips had to press Ready between hands, which is slow at six players.

Leaving the table mid-match (folded, knocked out, chips leave with them) stays as 0013 decided.

## Decision

1. **Dropped players keep their hand until it is their turn.** `MatchRoom.disconnect` only clears the connection; `foldAbsentActors` folds the seat when the action reaches it. `PlayerSummary.isConnected` drives a "Reconnecting…" label under the player's picture (`ReconnectingLabel` in `SeatViews.swift`).
2. **Absences expire.** Each drop starts a `MatchRoom.Absence` (seat plus a per-seat drop count). The hosting layer (`HostedTable`, server `Room`) waits `absenceTimeout` (60 s), then calls `MatchAuthority.expire(_:after:)`, which runs `MatchRoom.expire(_:)`: if that same absence is still going, the player leaves exactly as with `.leave`. A reconnect, or a later drop, makes the old absence stale, so a timer never needs cancelling.
3. **Short all-ins don't reopen raising.** `SeatState.actedAtBet` records the street's bet right after a player's last voluntary action. A player may bet or raise only if they haven't acted on the street, or the bet has grown by at least `minRaiseIncrement` since they did (`HandEngine.mayRaise`). Short all-ins therefore add up: together they reopen raising once they make a full raise (the usual cumulative rule). Everyone still has to respond to the extra chips; those who may not raise can call or fold (`LegalActions` without `betRange`/`raiseRange`/`allInAmount`, and `.raise`/`.allIn` throw `raiseNotAllowed`).
4. **The next hand deals itself.** `MatchRoom.nextHandTicket` is `match.handsPlayed` while a hand is due: between hands, with at least two connected players who have chips. The hosting layer waits `nextHandPause` (4 s, long enough to read the result) and calls `MatchAuthority.dealNextHand(ticket:after:)`. A stale ticket deals nothing. A table with one connected player waits for a reconnect or for the absence to expire. `.ready` between hands is ignored; it still accepts a rematch once the match is `.finished`. The table shows "Next hand…" (`TableStatus.nextHandSoon`).
5. `ProtocolVersion` is 4, because new clients never send Ready between hands and an old host would never deal.

## Consequences

- Bigger tables flow without anyone pressing anything, and a flaky connection costs at most the hands the player was away for.
- Hosting layers own two more timers; `MatchRoom` still reads no clock, and tests drive `dealNextHand`/`expire` directly.
- A player who drops for over a minute is out of the match for good, and their chips leave the table.
- Old builds can't play with new ones (protocol 4).
- Follow-up: action timers for slow players who are still connected; a setting for the pause and timeout.

## Alternatives considered

- **Keep Ready, with a timeout.** Still makes everyone tap, and the timeout needs the same timer machinery.
- **Cancel the expiry task on reconnect.** Needs the hosting layer to map rejoins back to seats; the ticketed `Absence` makes stale timers harmless instead.
- **Track "raise closed" as a flag reset on a full raise.** Doesn't handle several short all-ins adding up to a full raise.

## Test strategy

- `Packages/PokerCore/Tests/PokerCoreTests/MultiwayTests.swift`:
  - Short all-in doesn't reopen; a player who hasn't acted may still raise; short all-ins add up.
  - A disconnected player keeps their hand until their turn, or plays on after reconnecting first.
  - Absence expiry, stale absence, next hand needs two connected players, stale next-hand ticket.
- `MatchRoomTests`: the hand flows without Ready; reconnect keeps the live hand; protocol version 4.
- `PokerCoreTestSupport`: `MatchRoom.dealNextHand()`.
- `Server/Tests/PokerServerTests/RoomTests.swift` `RoomTimingTests`: auto-deal after the pause, expiry knocks the player out, rejoin in time keeps the seat.
- `ForeverAlonePokerTests`:
  - `MatchSessionClientTests.autoDeal`/`absenceExpires`.
  - `PeerLinkTransportTests.linkDrops`.
  - `TableModelsTests.nextHandSoon`.
- Manual: a 3-player online table with `PokerBot`. Kill one bot mid-hand: "Reconnecting…" shows, the bot is folded on its turn, and is out after a minute.
