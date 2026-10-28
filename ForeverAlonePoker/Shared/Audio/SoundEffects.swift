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

/// Plays the app's sound effects. Uses the ambient audio session category so
/// effects mix with the player's music and respect the silent switch.
/// Players are loaded once per effect and reused.
final class SoundEffects {
    static let shared = SoundEffects()

    private enum SessionState {
        case idle, activating, ready
    }

    private var players: [SoundEffect: AVAudioPlayer] = [:]
    private var sessionState = SessionState.idle
    /// Effects requested while the session is still activating.
    private var pending: [SoundEffect] = []
    private let logger = Logger(subsystem: "Ticoxxo.ForeverAlonePoker", category: "Audio")

    private init() {}

    /// Plays `effect` from the start, cutting off a previous play of the
    /// same effect. Missing or unreadable files are logged and ignored.
    func play(_ effect: SoundEffect) {
        switch sessionState {
        case .ready:
            start(effect)
        case .activating:
            pending.append(effect)
        case .idle:
            // Activating the session blocks, and `AVAudioPlayer.play()` would
            // do it implicitly on the main thread. Activate it off the main
            // actor once, then play whatever was requested meanwhile.
            sessionState = .activating
            pending.append(effect)
            Task {
                await Self.activateSession(logger: logger)
                sessionState = .ready
                let effects = pending
                pending.removeAll()
                effects.forEach(start)
            }
        }
    }

    private func start(_ effect: SoundEffect) {
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

    /// Runs on the global executor (nonisolated async), keeping the blocking
    /// session calls off the main thread.
    private nonisolated static func activateSession(logger: Logger) async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient)
            try session.setActive(true)
        } catch {
            logger.error("Could not set the audio session: \(error.localizedDescription, privacy: .public)")
        }
    }
}
