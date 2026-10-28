import AVFoundation
import Observation
import os

/// A music track bundled with the app. The raw value is the file name in
/// `Shared/Audio/Music`, without the extension.
nonisolated enum MusicTrack: String, CaseIterable, Identifiable {
    case subtlety
    case thisFeeling
    case openingTheWindowForSomeFreshAir

    static let fileExtension = "mp3"

    var id: String { rawValue }

    /// The song's name. Song names are not translated.
    var title: String {
        switch self {
        case .subtlety: "Subtlety"
        case .thisFeeling: "This Feeling"
        case .openingTheWindowForSomeFreshAir: "Opening the Window for Some Fresh Air"
        }
    }
}

/// Where `MusicPlayer` sends its music; faked in tests.
protocol MusicOutput: AnyObject {
    /// Starts `track` from the beginning, looping, replacing any other track.
    func play(_ track: MusicTrack, volume: Float)
    func pause()
    /// Carries on the paused track where it stopped.
    func resume()
    func setVolume(_ volume: Float)
}

/// Plays the selected track, looping, across the whole app (tdr/0026). Music
/// plays only while the app is active and the player has music on; leaving
/// either pauses it, and it resumes where it was.
final class MusicPlayer {
    /// Set from the scene phase.
    var isAppActive = false {
        didSet { update() }
    }

    private let settings: AudioSettings
    private let output: MusicOutput
    /// The track the output holds, playing or paused.
    private var loadedTrack: MusicTrack?
    private var isPaused = false
    private var appliedVolume: Float = 0

    init(settings: AudioSettings, output: MusicOutput) {
        self.settings = settings
        self.output = output
        followSettings()
    }

    /// Brings the output in line with the settings and the app state.
    func update() {
        let volume = settings.effectiveMusicVolume
        guard isAppActive, volume > 0 else {
            if loadedTrack != nil, !isPaused {
                output.pause()
                isPaused = true
            }
            return
        }
        let track = settings.selectedTrack
        if loadedTrack != track {
            output.play(track, volume: volume)
            loadedTrack = track
            isPaused = false
        } else {
            if isPaused {
                output.resume()
                isPaused = false
            }
            if appliedVolume != volume {
                output.setVolume(volume)
            }
        }
        appliedVolume = volume
    }

    /// Applies each settings change (a toggle, the slider, a new track) as
    /// it happens. Observation fires before the change lands, so the update
    /// runs on the next turn of the main actor, then tracking is re-armed.
    private func followSettings() {
        withObservationTracking {
            _ = settings.effectiveMusicVolume
            _ = settings.selectedTrack
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.followSettings()
            }
        }
    }
}

/// Plays music through `AVAudioPlayer` in the shared `AudioSession`.
final class AVMusicOutput: MusicOutput {
    private var player: AVAudioPlayer?
    private var isPaused = false
    private var logger: Logger { AudioSession.shared.logger }

    func play(_ track: MusicTrack, volume: Float) {
        player?.stop()
        player = nil
        isPaused = false
        guard let url = Bundle.main.url(forResource: track.rawValue, withExtension: MusicTrack.fileExtension) else {
            logger.error("Missing music file \(track.rawValue, privacy: .public)")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            self.player = player
            AudioSession.shared.whenReady { [weak self] in
                // Paused or replaced while the session was activating.
                guard let self, self.player === player, !self.isPaused else { return }
                self.start(player)
            }
        } catch {
            logger.error("Could not load music \(track.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func pause() {
        isPaused = true
        player?.pause()
    }

    func resume() {
        isPaused = false
        guard let player else { return }
        AudioSession.shared.whenReady { [weak self] in
            guard let self, self.player === player, !self.isPaused else { return }
            self.start(player)
        }
    }

    func setVolume(_ volume: Float) {
        player?.volume = volume
    }

    /// Starts `player` off the main thread (see `AudioSession.start`).
    private func start(_ player: AVAudioPlayer) {
        Task { [weak self] in
            await AudioSession.shared.start(player)
            // Replaced or paused while it was starting.
            guard let self, self.player === player else {
                player.stop()
                return
            }
            if self.isPaused { player.pause() }
        }
    }
}
