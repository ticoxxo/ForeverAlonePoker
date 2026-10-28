import AVFoundation
import os

/// The app's one audio session, shared by the music and the sound effects.
/// Uses the ambient category, so the app mixes with the player's own music
/// and stays quiet when the silent switch is on.
final class AudioSession {
    static let shared = AudioSession()

    private enum State {
        case idle, activating, ready
    }

    private var state = State.idle
    /// Work requested while the session is still activating.
    private var pending: [() -> Void] = []
    let logger = Logger(subsystem: "Ticoxxo.ForeverAlonePoker", category: "Audio")

    private init() {}

    /// Runs `work` once the session is active: right away if it already is,
    /// otherwise after activating it.
    func whenReady(_ work: @escaping () -> Void) {
        switch state {
        case .ready:
            work()
        case .activating:
            pending.append(work)
        case .idle:
            // Activating the session blocks, and `AVAudioPlayer.play()` would
            // do it implicitly on the main thread. Activate it off the main
            // actor once, then run whatever was requested meanwhile.
            state = .activating
            pending.append(work)
            Task {
                await Self.activate(logger: logger)
                state = .ready
                let work = pending
                pending.removeAll()
                work.forEach { $0() }
            }
        }
    }

    /// Runs on the global executor (nonisolated async), keeping the blocking
    /// session calls off the main thread.
    private nonisolated static func activate(logger: Logger) async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient)
            try session.setActive(true)
        } catch {
            logger.error("Could not set the audio session: \(error.localizedDescription, privacy: .public)")
        }
    }
}
