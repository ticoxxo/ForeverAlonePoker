@testable import ForeverAlonePoker

/// Records what `MusicPlayer` asks the speaker to do, without playing audio.
@MainActor
final class FakeMusicOutput: MusicOutput {
    enum Call: Equatable {
        case play(MusicTrack, volume: Float)
        case pause
        case resume
        case volume(Float)
    }

    private(set) var calls: [Call] = []

    func play(_ track: MusicTrack, volume: Float) { calls.append(.play(track, volume: volume)) }
    func pause() { calls.append(.pause) }
    func resume() { calls.append(.resume) }
    func setVolume(_ volume: Float) { calls.append(.volume(volume)) }
}
