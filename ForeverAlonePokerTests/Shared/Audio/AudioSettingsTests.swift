import Foundation
import Testing
@testable import ForeverAlonePoker

/// A throwaway defaults domain per test, so settings never leak between tests
/// or into the app's own defaults.
func isolatedDefaults() -> UserDefaults {
    let name = "AudioSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
@Suite("AudioSettings")
struct AudioSettingsTests {
    @Test("music and effects start on, playing Subtlety")
    func defaults() {
        let settings = AudioSettings(defaults: isolatedDefaults())
        #expect(settings.isMusicOn)
        #expect(settings.areEffectsOn)
        #expect(settings.musicVolume == AudioSettings.defaultMusicVolume)
        #expect(settings.effectsVolume == AudioSettings.defaultEffectsVolume)
        #expect(settings.selectedTrack == .subtlety)
    }

    @Test("changes survive a relaunch")
    func persists() {
        let defaults = isolatedDefaults()
        let settings = AudioSettings(defaults: defaults)
        settings.isMusicOn = false
        settings.musicVolume = 0.3
        settings.areEffectsOn = false
        settings.effectsVolume = 0.2
        settings.selectedTrack = .thisFeeling

        let relaunched = AudioSettings(defaults: defaults)
        #expect(!relaunched.isMusicOn)
        #expect(relaunched.musicVolume == 0.3)
        #expect(!relaunched.areEffectsOn)
        #expect(relaunched.effectsVolume == 0.2)
        #expect(relaunched.selectedTrack == .thisFeeling)
    }

    @Test("an unknown stored track falls back to Subtlety")
    func unknownTrack() {
        let defaults = isolatedDefaults()
        defaults.set("removedSong", forKey: AudioSettings.Key.selectedTrack)
        #expect(AudioSettings(defaults: defaults).selectedTrack == .subtlety)
    }

    @Test("the quick button silences everything that is on")
    func toggleAllMutes() {
        let settings = AudioSettings(defaults: isolatedDefaults())
        settings.toggleAll()
        #expect(!settings.isMusicOn)
        #expect(!settings.areEffectsOn)
        #expect(!settings.isAnythingAudible)
    }

    @Test("the quick button silences effects when only effects are on")
    func toggleAllMutesPartlyOn() {
        let settings = AudioSettings(defaults: isolatedDefaults())
        settings.isMusicOn = false
        settings.toggleAll()
        #expect(!settings.isMusicOn)
        #expect(!settings.areEffectsOn)
    }

    @Test("the quick button turns both back on when all is silent")
    func toggleAllUnmutes() {
        let settings = AudioSettings(defaults: isolatedDefaults())
        settings.isMusicOn = false
        settings.areEffectsOn = false
        settings.toggleAll()
        #expect(settings.isMusicOn)
        #expect(settings.areEffectsOn)
    }

    @Test("a channel at zero volume is not audible")
    func zeroVolumeIsSilent() {
        let settings = AudioSettings(defaults: isolatedDefaults())
        settings.musicVolume = 0
        settings.effectsVolume = 0
        #expect(!settings.isAnythingAudible)
    }

    @Test("Reset restores every default, the track included")
    func reset() {
        let settings = AudioSettings(defaults: isolatedDefaults())
        settings.isMusicOn = false
        settings.musicVolume = 0.1
        settings.areEffectsOn = false
        settings.effectsVolume = 0.1
        settings.selectedTrack = .openingTheWindowForSomeFreshAir
        settings.resetToDefaults()
        #expect(settings.isMusicOn)
        #expect(settings.areEffectsOn)
        #expect(settings.musicVolume == AudioSettings.defaultMusicVolume)
        #expect(settings.effectsVolume == AudioSettings.defaultEffectsVolume)
        #expect(settings.selectedTrack == .subtlety)
    }

    @Test("a switched-off channel plays at zero volume")
    func effectiveVolumes() {
        let settings = AudioSettings(defaults: isolatedDefaults())
        settings.effectsVolume = 0.5
        settings.musicVolume = 0.4
        #expect(settings.effectiveEffectsVolume == 0.5)
        #expect(settings.effectiveMusicVolume == 0.4)
        settings.areEffectsOn = false
        settings.isMusicOn = false
        #expect(settings.effectiveEffectsVolume == 0)
        #expect(settings.effectiveMusicVolume == 0)
    }
}
