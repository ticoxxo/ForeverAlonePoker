import Foundation
import Observation

/// The player's sound settings: music and sound effects, each with an on/off
/// switch and a volume, plus the music track. Kept per device in
/// `UserDefaults`, not in the synced profile, because the right volume
/// depends on the device (tdr/0026).
@Observable
final class AudioSettings {
    static let defaultMusicVolume: Float = 0.6
    static let defaultEffectsVolume: Float = 1
    static let defaultTrack = MusicTrack.subtlety

    enum Key {
        static let isMusicOn = "audio.isMusicOn"
        static let musicVolume = "audio.musicVolume"
        static let selectedTrack = "audio.selectedTrack"
        static let areEffectsOn = "audio.areEffectsOn"
        static let effectsVolume = "audio.effectsVolume"
    }

    var isMusicOn: Bool {
        didSet { defaults.set(isMusicOn, forKey: Key.isMusicOn) }
    }

    /// 0 to 1.
    var musicVolume: Float {
        didSet { defaults.set(musicVolume, forKey: Key.musicVolume) }
    }

    var selectedTrack: MusicTrack {
        didSet { defaults.set(selectedTrack.rawValue, forKey: Key.selectedTrack) }
    }

    var areEffectsOn: Bool {
        didSet { defaults.set(areEffectsOn, forKey: Key.areEffectsOn) }
    }

    /// 0 to 1.
    var effectsVolume: Float {
        didSet { defaults.set(effectsVolume, forKey: Key.effectsVolume) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isMusicOn = defaults.object(forKey: Key.isMusicOn) as? Bool ?? true
        musicVolume = defaults.object(forKey: Key.musicVolume) == nil
            ? Self.defaultMusicVolume
            : defaults.float(forKey: Key.musicVolume)
        selectedTrack = defaults.string(forKey: Key.selectedTrack).flatMap(MusicTrack.init(rawValue:))
            ?? Self.defaultTrack
        areEffectsOn = defaults.object(forKey: Key.areEffectsOn) as? Bool ?? true
        effectsVolume = defaults.object(forKey: Key.effectsVolume) == nil
            ? Self.defaultEffectsVolume
            : defaults.float(forKey: Key.effectsVolume)
    }

    /// The music volume to play at: 0 while music is off.
    var effectiveMusicVolume: Float { isMusicOn ? musicVolume : 0 }

    /// The sound effects volume to play at: 0 while effects are off.
    var effectiveEffectsVolume: Float { areEffectsOn ? effectsVolume : 0 }

    /// Whether the app makes any sound at all.
    var isAnythingAudible: Bool {
        effectiveMusicVolume > 0 || effectiveEffectsVolume > 0
    }

    /// The quick toolbar button: silences everything that is audible, or
    /// turns music and effects back on when all is silent. The switches are
    /// the only state, so Profile always shows what is actually playing.
    func toggleAll() {
        let isOn = !isAnythingAudible
        isMusicOn = isOn
        areEffectsOn = isOn
    }

    func resetToDefaults() {
        isMusicOn = true
        musicVolume = Self.defaultMusicVolume
        selectedTrack = Self.defaultTrack
        areEffectsOn = true
        effectsVolume = Self.defaultEffectsVolume
    }
}
