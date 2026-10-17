# 0015. Let players react with a fixed set of emojis, one per turn

- **Status:** Accepted
- **Date:** 2026-10-17
- **Feature / area:** `Packages/PokerCore/Sources/PokerCore/{Protocol,Authority}`, `ForeverAlonePoker/Shared/Session/MatchSessionClient.swift`, `ForeverAlonePoker/Features/Table`

## Context

Players at a table have no way to talk. Banter is part of the fun, but free text needs moderation and invites spam.

## Decision

- `Emote` (PokerCore) is a closed set of nine: 😃 🫠 😂 🙃 🤬 🥶 💩 😎 👀. It is encoded as the emoji itself; anything else fails to decode, so nothing outside the set reaches the room.
- `ClientMessage.emote(_:)` asks; the authority relays `ServerMessage.emote(seat:emote:)` to every connected seat, sender included.
- **One per turn.** `MatchRoom` keeps a `turn` counter that moves on with every action, deal, auto-fold, join and leave. Each seated player, spectators included, may send one emote per turn (`SeatedPlayer.lastEmoteTurn`); a second is rejected with "One emoji per turn.". `PlayerView.canEmote` tells the client, and the sender gets a fresh view with the emote spent.
- Emotes never touch game state.
- The client keeps `reactions[seat]` for `reactionDuration` (3 s). `EmoteBubble` shows it by the seat's avatar or header. `EmotePicker` (a button with the nine in a popover) sits next to the action bar, disabled while `canEmote` is false. The practice table hides it.

## Consequences

- No moderation needed, and the rate is bounded by the game's own pace.
- Every new emoji is a protocol change.
- Follow-up: mute a player's emotes locally; emote sets as cosmetic items (tdr/0011).

## Alternatives considered

- **Free text chat.** Needs moderation and reporting.
- **A time-based cooldown.** Needs a clock in the room; the turn counter ties the limit to the game's own pace instead.
- **Accept any emoji string.** Arbitrary strings are free text in disguise.

## Test strategy

- `Packages/PokerCore/Tests/PokerCoreTests/MatchRoomTests.swift`:
  - `MatchRoomEmoteTests`: relayed to everyone, one per turn, spectators may emote, unseated rejected.
  - `ProtocolTests.emoteWireFormat`: round-trip; forged values fail to decode.
- `ForeverAlonePokerTests/Shared/MatchSessionClientTests.emotes`: the reaction shows for both players, the limit applies, the bubble fades, and the limit resets when the action moves.
- Manual: the bubble placement on iPhone and iPad at heads-up and six-max.
