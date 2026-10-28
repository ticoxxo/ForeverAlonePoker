# 0026. Play background music and let players control sound

- **Status:** Accepted
- **Date:** 2026-10-28
- **Feature / area:** `ForeverAlonePoker/Shared/Audio`, `ForeverAlonePoker/App`, `ForeverAlonePoker/Features/Profile`, the Home and Table toolbars

## Context

The app has table sound effects (tdr/0025) but no music, and the silent switch was the only way to quiet it. We have three tracks for the whole app (`Shared/Audio/Music`). Players need a quick way to silence everything, finer control over music and effects separately, and the music must not keep playing when the app is not in front.

## Decision

`Shared/Audio` is split by what it plays:

| Type | Role |
| --- | --- |
| `AudioSession` | The one `.ambient` session, activated off the main thread once; `whenReady(_:)` runs playback after it. Shared by music and effects. |
| `AudioSettings` | `@Observable`: music on/volume/track, effects on/volume. Persisted per device in `UserDefaults` (`audio.*` keys). `toggleAll()`, `resetToDefaults()`, `effectiveMusicVolume`, `effectiveEffectsVolume`. |
| `MusicTrack` | One case per file in `Shared/Audio/Music` (raw value = file name, `.mp3`). Default: `subtlety`. |
| `MusicPlayer` | Plays the selected track, looping, through a `MusicOutput` (`AVMusicOutput` in the app, a fake in tests). Follows settings changes with Observation. |
| `SoundEffects` | Unchanged API; reads `settings` for volume and plays nothing while effects are off. |
| `AudioToggleButton` | The quick switch in the Home and Table navigation bars. |

Rules:

- Music plays only while the scene phase is `.active` and music is on with a volume above zero. `ForeverAlonePokerApp` sets `MusicPlayer.isAppActive` from `scenePhase`; inactive or background pauses, active resumes where it stopped (not from the start).
- Choosing another track starts it at once; chosen while music is off, it starts when music is switched on.
- The quick button has no state of its own: if anything is audible it turns music and effects off, otherwise both on. Profile's switches therefore always show what is playing.
- Profile groups the settings like the folders: Music (switch, volume, track) and Sound effects (switch, volume), then Reset settings, which also restores Subtlety.
- The session stays `.ambient`: the app's music mixes with whatever the player is listening to and the silent switch still silences it.

## Consequences

- Closes the follow-up in tdr/0025 (an in-app sound setting).
- Settings are per device and do not sync through CloudKit; a player can keep the iPad loud and the iPhone quiet.
- A new track is a `MusicTrack` case plus an `.mp3` in `Shared/Audio/Music`. Views never create `AVAudioPlayer` themselves.
- The three tracks add about 24 MB to the app.
- The music also plays in the unit-test host; it is silent on simulators run headless and harmless otherwise.

## Alternatives considered

- **Store the settings on the SwiftData profile.** It would sync volume between devices, which is the wrong default, and every change would be a CloudKit write.
- **A master mute flag separate from the two switches.** Profile could then show music "on" while nothing plays.
- **Play the three tracks as a playlist.** The player asked to choose one; looping the choice is simpler and predictable.
- **`.playback` session category.** It would interrupt the player's own music and ignore the silent switch.

## Test strategy

`ForeverAlonePokerTests/Shared/Audio/AudioSettingsTests.swift` covers defaults, persistence through an isolated `UserDefaults` suite, an unknown stored track, `toggleAll` from each state, zero volume, Reset and the effective volumes. `MusicPlayerTests.swift` drives `MusicPlayer` with `FakeMusicOutput` (`ForeverAlonePokerTests/Support`): playing only when active, pause and resume, music off, switching track (also while off), volume, live observation of settings, and that every track is bundled. Real playback, the scene-phase pause (Home screen, Control Center, a call) and the silent switch are checked by hand on a device.
