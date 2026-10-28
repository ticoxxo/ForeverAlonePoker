import AVFoundation
import os
import UIKit

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

    private init() {
        observeDeactivation()
    }

    /// Runs `work` once the session is active: right away if it already is,
    /// otherwise after activating it.
    func whenReady(_ work: @escaping () -> Void) {
        switch state {
        case .ready:
            work()
        case .activating:
            pending.append(work)
        case .idle:
            // Activating the session blocks, and `AVAudioPlayer` would do it
            // implicitly on the main thread. Activate it off the main actor,
            // then run whatever was requested meanwhile.
            state = .activating
            pending.append(work)
            Task {
                let isActive = await Self.activate(logger: logger)
                let work = pending
                pending.removeAll()
                // On failure stay idle and drop the work: playing now would
                // make `AVAudioPlayer` retry the activation on the main thread.
                // The next request retries off the main actor instead.
                state = isActive ? .ready : .idle
                if isActive { work.forEach { $0() } }
            }
        }
    }

    /// The system deactivates the session behind our back when the app goes
    /// to the background or another app interrupts it. Forget it was active,
    /// so the next play activates it off the main thread again rather than
    /// letting `AVAudioPlayer` reactivate it on the main thread.
    private func observeDeactivation() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                self?.markInactive()
            }
        }
        Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if rawType.flatMap(AVAudioSession.InterruptionType.init) == .began {
                    self?.markInactive()
                }
            }
        }
    }

    private func markInactive() {
        // An activation in flight settles the state itself.
        if state == .ready { state = .idle }
    }

    /// Prepares and plays `player` off the main thread. `prepareToPlay()` and
    /// `play()` (re)activate the session synchronously whenever AVFAudio thinks
    /// it needs to, even after `whenReady` activated it, and that blocking call
    /// must not run on the main thread. Callers reconcile pauses or stops that
    /// happened meanwhile once this returns.
    func start(_ player: AVAudioPlayer) async {
        await Self.start(PlayerHandoff(player: player))
    }

    @concurrent
    private nonisolated static func start(_ handoff: PlayerHandoff) async {
        handoff.player.prepareToPlay()
        handoff.player.play()
    }

    /// Runs on the global executor, keeping the blocking session calls off the
    /// main thread. `@concurrent` is required: with nonisolated(nonsending) by
    /// default, a plain `nonisolated async` function inherits the caller's
    /// actor and would still run on the main thread.
    @concurrent
    private nonisolated static func activate(logger: Logger) async -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient)
            try session.setActive(true)
            return true
        } catch {
            logger.error("Could not set the audio session: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

/// Carries an `AVAudioPlayer` to the global executor to start it. The main
/// actor keeps owning the player; only `prepareToPlay()` and `play()` run
/// elsewhere.
private nonisolated struct PlayerHandoff: @unchecked Sendable {
    let player: AVAudioPlayer
}
