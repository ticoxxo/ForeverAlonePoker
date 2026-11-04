import Foundation
import Testing
import SkinKit

private struct StoreKitConfiguration: Decodable {
    struct Product: Decodable {
        let productID: String
    }

    let products: [Product]

    static func load(filePath: String = #filePath) throws -> StoreKitConfiguration {
        let root = URL(filePath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "StoreKit/SkinStore.storekit"))
        return try JSONDecoder().decode(StoreKitConfiguration.self, from: data)
    }
}

@Suite("StoreKit configuration")
struct StoreKitConfigurationTests {
    @Test("every premium item built into the app has a local StoreKit product")
    func listsBuiltInProducts() throws {
        let listed = Set(try StoreKitConfiguration.load().products.map(\.productID))
        let sold = SkinCatalog.builtIn.items.compactMap(\.productID)
        #expect(!sold.isEmpty)
        #expect(Set(sold).subtracting(listed).isEmpty)
    }
}
