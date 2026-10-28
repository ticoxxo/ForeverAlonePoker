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

    var fileExtension: String {
        switch self {
        case .placingNewCard: "mp3"
        default: "m4a"
        }
    }
}

/// Plays the app's sound effects. Uses the ambient audio session category so
/// effects mix with the player's music and respect the silent switch.
/// Players are loaded once per effect and reused.
final class SoundEffects {
    static let shared = SoundEffects()

    private var players: [SoundEffect: AVAudioPlayer] = [:]
    private var isSessionConfigured = false
    private let logger = Logger(subsystem: "Ticoxxo.ForeverAlonePoker", category: "Audio")

    private init() {}

    /// Plays `effect` from the start, cutting off a previous play of the
    /// same effect. Missing or unreadable files are logged and ignored.
    func play(_ effect: SoundEffect) {
        configureSessionIfNeeded()
        guard let player = player(for: effect) else { return }
        player.currentTime = 0
        player.play()
    }

    private func player(for effect: SoundEffect) -> AVAudioPlayer? {
        if let player = players[effect] { return player }
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: effect.fileExtension) else {
            logger.error("Missing sound file \(effect.rawValue, privacy: .public)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[effect] = player
            return player
        } catch {
            logger.error("Could not load sound \(effect.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        isSessionConfigured = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
        } catch {
            logger.error("Could not set the audio session: \(error.localizedDescription, privacy: .public)")
        }
    }
}
