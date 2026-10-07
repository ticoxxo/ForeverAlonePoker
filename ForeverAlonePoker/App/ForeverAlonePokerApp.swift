import SwiftData
import SwiftUI

@main
struct ForeverAlonePokerApp: App {
    private let container: ModelContainer
    private let identity: IdentityStore

    init() {
        // Fall back to an in-memory store rather than crash on a corrupt
        // database; the player can still play, just without history.
        let container: ModelContainer
        do {
            container = try Persistence.container()
        } catch {
            assertionFailure("Persistent store unavailable: \(error)")
            container = try! Persistence.inMemoryContainer()
        }
        self.container = container
        identity = try! IdentityStore(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(identity)
        }
        .modelContainer(container)
    }
}

#if DEBUG
/// Shared in-memory identity for previews.
enum PreviewIdentity {
    static let store: IdentityStore = {
        let container = try! Persistence.inMemoryContainer()
        return try! IdentityStore(context: container.mainContext, defaultCountryCode: "MX")
    }()
}
#endif
