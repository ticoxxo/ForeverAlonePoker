import Foundation
import Testing
@testable import ForeverAlonePoker

@MainActor
@Suite("MusicPlayer")
struct MusicPlayerTests {
    private let settings = AudioSettings(defaults: isolatedDefaults())
    private let output = FakeMusicOutput()

    private func activePlayer() -> MusicPlayer {
        let player = MusicPlayer(settings: settings, output: output)
        player.isAppActive = true
        return player
    }

    @Test("an active app plays the selected track")
    func playsSelectedTrack() {
        _ = activePlayer()
        #expect(output.calls == [.play(.subtlety, volume: AudioSettings.defaultMusicVolume)])
    }

    @Test("nothing plays before the app is active")
    func waitsForActive() {
        _ = MusicPlayer(settings: settings, output: output)
        #expect(output.calls.isEmpty)
    }

    @Test("leaving the active state pauses, coming back resumes where it was")
    func pausesAndResumes() {
        let player = activePlayer()
        player.isAppActive = false
        player.isAppActive = true
        #expect(output.calls.dropFirst() == [.pause, .resume])
    }

    @Test("music switched off never plays")
    func musicOff() {
        settings.isMusicOn = false
        _ = activePlayer()
        #expect(output.calls.isEmpty)
    }

    @Test("switching music off pauses it, on again resumes it")
    func toggleMusic() {
        let player = activePlayer()
        settings.isMusicOn = false
        player.update()
        settings.isMusicOn = true
        player.update()
        #expect(output.calls.dropFirst() == [.pause, .resume])
    }

    @Test("choosing another track starts it")
    func switchesTrack() {
        let player = activePlayer()
        settings.selectedTrack = .thisFeeling
        player.update()
        #expect(output.calls.last == .play(.thisFeeling, volume: AudioSettings.defaultMusicVolume))
    }

    @Test("a track chosen while music is off starts when it is switched on")
    func switchesTrackWhileOff() {
        let player = activePlayer()
        settings.isMusicOn = false
        player.update()
        settings.selectedTrack = .thisFeeling
        player.update()
        settings.isMusicOn = true
        player.update()
        #expect(output.calls.dropFirst() == [.pause, .play(.thisFeeling, volume: AudioSettings.defaultMusicVolume)])
    }

    @Test("moving the slider changes the volume of what plays")
    func volume() {
        let player = activePlayer()
        settings.musicVolume = 0.3
        player.update()
        #expect(output.calls.last == .volume(0.3))
    }

    @Test("settings changes reach the player without being told")
    func observesSettings() async {
        let player = activePlayer()
        settings.isMusicOn = false
        #expect(await eventually { output.calls.last == .pause })
        withExtendedLifetime(player) {}
    }

    @Test("every track ships with the app", arguments: MusicTrack.allCases)
    func bundled(track: MusicTrack) {
        #expect(Bundle.main.url(forResource: track.rawValue, withExtension: MusicTrack.fileExtension) != nil)
    }
}
