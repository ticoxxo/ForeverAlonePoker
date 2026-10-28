# 0025. Play sound effects at the table

- **Status:** Accepted
- **Date:** 2026-10-28
- **Feature / area:** `ForeverAlonePoker/Shared/Audio`, `ForeverAlonePoker/Features/Table`

## Context

The app had no audio. Key moments (a new card on the board, a bet, a pot won, the end of a match) are easy to miss when the player is looking at their own hand or the action bar. We have short effects for each of them in `Shared/Audio/SoundEffects`.

## Decision

`Shared/Audio` holds the bundled sound files and `SoundEffects`, the one place that plays them. `SoundEffect` names each file (raw value = file name). `SoundEffects.shared.play(_:)` loads an `AVAudioPlayer` once per effect and reuses it. The audio session uses the `.ambient` category, so effects mix with the player's music and stay quiet when the silent switch is on.

`TableSounds` in `Features/Table/TableModels.swift` decides what plays. `TableView` asks it in two places:

| Moment | Effect | Decided by |
| --- | --- | --- |
| All in pressed | `allInChips` | `effect(for:)`, from `act(_:)` |
| Check, Bet or Raise pressed | `placingPokerChips` | `effect(for:)`, from `act(_:)` |
| The flop (first board cards) | `cardsBeingDealt` | `effects(from:to:)` |
| The turn or the river | `placingNewCard` | `effects(from:to:)` |
| First deal of a match or a rematch | `shufflingCards` | `effects(from:to:)` |
| Winning a hand outright | `winningPot` | `effects(from:to:)` |
| The match ends: won / lost | `winSound` / `lostSound` | `effects(from:to:)` |

`effects(from:to:)` compares the previous `PlayerView` with the new one. The rules:

- A new match is hand number 1 in play, which also covers rematches, because hand numbers restart.
- If there is no previous view (the table just opened, or a rejoin), only a fresh deal with an empty board shuffles, so nothing that already happened is replayed.
- On the match's last hand, the match result replaces the pot sound.
- Fold, Call and a chopped pot are silent.

## Consequences

- New effects are one `SoundEffect` case plus a file in `Shared/Audio/SoundEffects`. Views never create `AVAudioPlayer` themselves.
- Sounds follow what the table renders (`PlayerView`), not the rules, so clients still never run game logic (tdr/0003).
- An all-in run-out can deal the whole board and end the match in one update, so its sounds overlap.
- Follow-up: an in-app sound on/off setting if players ask for one. Today, the silent switch is the only control.

## Alternatives considered

- **`AudioServicesPlaySystemSound`.** Simpler, but it ignores the media volume and gives no control over the session.
- **Play from each view (`BoardView`, the buttons).** Scattered, and a view alone cannot tell a rejoin from a deal.

## Test strategy

`ForeverAlonePokerTests/Features/Table/TableMotionTests.swift` (`TableSoundsActionTests`, `TableSoundsUpdateTests`) drives a `MatchRoomBuilder` room and checks each row of the table above, plus the silent rejoin and the losing side of a hand. Playback itself is checked by hand on a device with the ring switch on and off.
