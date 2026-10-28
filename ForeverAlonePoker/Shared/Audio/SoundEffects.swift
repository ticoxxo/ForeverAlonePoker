import AVFoundation
import os

/// A short sound bundled with the app. The raw value is the file name in
/// `Shared/Audio/SoundEffects`, without the extension.
nonisolated enum SoundEffect: String, CaseIterable {
    case placingNewCard
    case allInChips
    case placingPokerChips
    case cardsBeingDealt
    case shufflingCards
    case winningPot
    case lostSound
    case winSound
    case foldHand

    var fileExtension: String {
        switch self {
        case .placingNewCard: "mp3"
        default: "m4a"
        }
    }
}

/// Plays the app's sound effects through the shared `AudioSession`, at the
/// player's sound effects volume (tdr/0026). Players are loaded once per
/// effect and reused.
final class SoundEffects {
    static let shared = SoundEffects()

    /// The player's sound settings. Without them effects play at full volume.
    weak var settings: AudioSettings?

    private var players: [SoundEffect: AVAudioPlayer] = [:]
    private var logger: Logger { AudioSession.shared.logger }

    private init() {}

    /// Plays `effect` from the start, cutting off a previous play of the
    /// same effect. Nothing plays while sound effects are off. Missing or
    /// unreadable files are logged and ignored.
    func play(_ effect: SoundEffect) {
        guard volume > 0 else { return }
        AudioSession.shared.whenReady { [self] in start(effect) }
    }

    private var volume: Float {
        settings?.effectiveEffectsVolume ?? 1
    }

    private func start(_ effect: SoundEffect) {
        // The player may have muted while the session was activating.
        guard volume > 0, let player = player(for: effect) else { return }
        player.volume = volume
        player.currentTime = 0
        Task {
            await AudioSession.shared.start(player)
            // Muted while it was starting.
            if volume == 0 { player.stop() }
        }
    }

    private func player(for effect: SoundEffect) -> AVAudioPlayer? {
        if let player = players[effect] { return player }
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: effect.fileExtension) else {
            logger.error("Missing sound file \(effect.rawValue, privacy: .public)")
            return nil
        }
        do {
            // Prepared off the main thread when it first plays.
            let player = try AVAudioPlayer(contentsOf: url)
            players[effect] = player
            return player
        } catch {
            logger.error("Could not load sound \(effect.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
