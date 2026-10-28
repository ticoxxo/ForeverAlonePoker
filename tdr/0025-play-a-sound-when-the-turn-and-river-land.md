# 0025. Play a sound when the turn and the river land

- **Status:** Accepted
- **Date:** 2026-10-28
- **Feature / area:** `ForeverAlonePoker/Shared/Audio`, `ForeverAlonePoker/Features/Table`

## Context

The app had no audio. After the flop, a single new card on the board is easy to miss, especially when the player is looking at their own hand or the action bar. We have a short effect, `placingNewCard.mp3`.

## Decision

`Shared/Audio` holds the bundled sound files and `SoundEffects`, the one place that plays them. `SoundEffect` names each file (raw value = file name). `SoundEffects.shared.play(_:)` loads an `AVAudioPlayer` once per effect and reuses it. The audio session uses the `.ambient` category, so effects mix with the player's music and stay quiet when the silent switch is on.

`BoardView` plays `.placingNewCard` when the number of community cards goes up while three or more were already showing, which means the turn and the river. That rule is `BoardSound.playsOnDeal(previousCount:newCount:)` in `TableModels.swift`. The flop, clearing the board for a new hand, and a rejoin that lands on a board already past the flop all stay silent.

## Consequences

- New effects are one `SoundEffect` case plus a file in `Shared/Audio`. Views never create `AVAudioPlayer` themselves.
- The sound follows what the board renders (`PlayerView`), not the rules, so clients still never run game logic (tdr/0003).
- Follow-up: an in-app sound on/off setting if players ask for one. Today, the silent switch is the only control.

## Alternatives considered

- **`AudioServicesPlaySystemSound`.** Simpler, but it ignores the media volume, can't be preloaded from an mp3 easily, and gives no control over the session.
- **Play on every board card.** The flop already has a staggered animation (`DealTiming`), and three sounds in a row felt noisy.

## Test strategy

`ForeverAlonePokerTests/Features/Table/TableMotionTests.swift` (`BoardSound`) covers the rule: flop silent, turn and river play, new hand silent, rejoin silent. Playback itself is checked by hand on a device with the ring switch on and off.
