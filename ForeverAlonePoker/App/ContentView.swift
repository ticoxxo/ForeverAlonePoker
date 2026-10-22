import SwiftUI

struct ContentView: View {
    @Environment(SkinStore.self) private var skins

    var body: some View {
        HomeView()
            // Every card in the app draws with the player's own skins unless a
            // view (the opponent's seat, the store) says otherwise (tdr/0011).
            .environment(\.cardSkin, skins.myCardSkin)
    }
}

#if DEBUG
#Preview("Returning player") {
    ContentView()
        .previewEnvironment()
}

#Preview("First launch") {
    ContentView()
        .previewEnvironment(identity: PreviewIdentity.newPlayer, skins: PreviewSkins.empty)
}
#endif
