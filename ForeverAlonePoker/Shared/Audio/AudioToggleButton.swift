import SwiftUI

/// The quick sound switch for the navigation bar: silences the music and the
/// sound effects at once, or turns them back on (tdr/0026).
struct AudioToggleButton: View {
    @Environment(AudioSettings.self) private var audio

    var body: some View {
        Button {
            audio.toggleAll()
        } label: {
            if audio.isAnythingAudible {
                Label("Mute sound", systemImage: "speaker.wave.2.fill")
            } else {
                Label("Turn sound on", systemImage: "speaker.slash.fill")
            }
        }
        .labelStyle(.iconOnly)
        .contentTransition(.symbolEffect(.replace))
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        Text("Content")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AudioToggleButton()
                }
            }
    }
    .previewEnvironment()
}
#endif
