import Crypto
import Foundation
import Hummingbird
import HummingbirdTesting
import PokerCoreTestSupport
import SkinKit
import SkinKitTestSupport
import Testing
@testable import PokerServerCore

/// A throwaway skins directory with a published manifest.
private struct SkinsFixture {
    let directory: URL

    init(catalog: SkinCatalog = SkinCatalogBuilder().with(SkinCatalogBuilder.back("red_check")).build()) throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "skins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory.appending(path: "red_check"), withIntermediateDirectories: true)
        try Data("png-bytes".utf8).write(to: directory.appending(path: "red_check/back.png"))
        try write(catalog)
    }

    var manifestURL: URL { directory.appending(path: "manifest.json") }

    func write(_ catalog: SkinCatalog) throws {
        try catalog.encoded().write(to: manifestURL)
    }

    func writeRaw(_ text: String) throws {
        try Data(text.utf8).write(to: manifestURL)
    }
}

@Suite("Catalog service")
struct CatalogServiceTests {
    @Test("signs the manifest bytes with the configured key")
    func signs() async throws {
        let fixture = try SkinsFixture()
        let key = Curve25519.Signing.PrivateKey()
        let service = CatalogService(manifestURL: fixture.manifestURL, signer: CatalogSigner(keyID: "k1", privateKey: key))
        let published = try await service.current()
        #expect(published.catalog.keyID == "k1")
        #expect(published.catalog.manifest == (try Data(contentsOf: fixture.manifestURL)))
        #expect(key.publicKey.isValidSignature(published.catalog.signature, for: published.catalog.manifest))
    }

    @Test("serves an unsigned catalog when no key is configured")
    func unsigned() async throws {
        let fixture = try SkinsFixture()
        let published = try await CatalogService(manifestURL: fixture.manifestURL, signer: nil).current()
        #expect(!published.catalog.isSigned)
    }

    @Test("picks up a new manifest without a restart, and keeps the last good one when the new one is broken")
    func reloads() async throws {
        let fixture = try SkinsFixture()
        let service = CatalogService(manifestURL: fixture.manifestURL, signer: nil)
        let first = try await service.current()

        try fixture.write(SkinCatalogBuilder().version(2).with(SkinCatalogBuilder.back("red_check")).build())
        let second = try await service.current()
        #expect(second.etag != first.etag)
        #expect(try SkinCatalog.decode(from: second.catalog.manifest).catalogVersion == 2)

        try fixture.writeRaw("{ not json")
        let third = try await service.current()
        #expect(third == second)
    }

    @Test("a missing manifest is an error, not an empty store")
    func missing() async throws {
        let service = CatalogService(manifestURL: URL(filePath: "/nonexistent/manifest.json"), signer: nil)
        await #expect(throws: (any Error).self) { try await service.current() }
    }

    @Test("reads the signing key and directories from the environment")
    func environment() throws {
        let key = Curve25519.Signing.PrivateKey()
        let configuration = try #require(try StoreConfiguration.fromEnvironment([
            "SKINS_DIR": "/srv/skins",
            "CATALOG_SIGNING_KEY": key.rawRepresentation.base64EncodedString(),
            "CATALOG_KEY_ID": "2026-10",
        ]))
        #expect(configuration.skinsDirectory.path == "/srv/skins")
        #expect(configuration.manifestURL.path == "/srv/skins/manifest.json")
        #expect(configuration.signer?.keyID == "2026-10")
        #expect(configuration.signer?.privateKey.publicKey.rawRepresentation == key.publicKey.rawRepresentation)
        #expect(throws: (any Error).self) {
            try StoreConfiguration.fromEnvironment(["SKINS_DIR": "/srv/skins", "CATALOG_SIGNING_KEY": "not-a-key"])
        }
    }
}

@Suite("Store routes")
struct StoreRouteTests {
    @Test("serves the signed catalog with an ETag and answers 304 when unchanged")
    func catalog() async throws {
        let fixture = try SkinsFixture()
        let store = StoreConfiguration(skinsDirectory: fixture.directory, signer: nil)
        let app = buildApplication(registry: RoomRegistry(), store: store)
        try await app.test(.router) { client in
            let etag = try await client.execute(uri: "/store/catalog", method: .get) { response in
                #expect(response.status == .ok)
                let signed = try JSONDecoder().decode(SignedCatalog.self, from: response.body)
                #expect(try SkinCatalog.decode(from: signed.manifest).item("red_check") != nil)
                return try #require(response.headers[.eTag])
            }
            try await client.execute(uri: "/store/catalog", method: .get, headers: [.ifNoneMatch: etag]) { response in
                #expect(response.status == .notModified)
            }
        }
    }

    @Test("serves skin files under /skins")
    func files() async throws {
        let fixture = try SkinsFixture()
        let app = buildApplication(registry: RoomRegistry(), store: StoreConfiguration(skinsDirectory: fixture.directory, signer: nil))
        try await app.test(.router) { client in
            try await client.execute(uri: "/skins/red_check/back.png", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "png-bytes")
            }
        }
    }

    @Test("answers 503 when the store is not configured")
    func unavailable() async throws {
        let app = buildApplication(registry: RoomRegistry())
        try await app.test(.router) { client in
            try await client.execute(uri: "/store/catalog", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
            }
        }
    }
}

@Suite("Catalog publisher")
struct CatalogPublisherTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "publisher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("imports artist files by slot name and skips jokers and previews")
    func importsArtwork() throws {
        let source = try temporaryDirectory()
        let skins = try temporaryDirectory()
        try FileManager.default.createDirectory(at: source.appending(path: "png"), withIntermediateDirectories: true)
        for name in ["spades_10_spanish_001", "hearts_A_spanish_001", "joker_red_spanish_001", "spanish_set_preview", "back_red_check"] {
            try Data(name.utf8).write(to: source.appending(path: "png/\(name).png"))
        }
        try Data().write(to: source.appending(path: "png/spades_10_spanish_001.svg"))

        let imported = try CatalogPublisher.importArtwork(from: source, into: skins)

        #expect(imported == ["spanish_001": 2, "red_check": 1])
        #expect(FileManager.default.fileExists(atPath: skins.appending(path: "spanish_001/front.Ts.png").path))
        #expect(FileManager.default.fileExists(atPath: skins.appending(path: "spanish_001/front.Ah.png").path))
        #expect(FileManager.default.fileExists(atPath: skins.appending(path: "red_check/back.png").path))
        #expect(!FileManager.default.fileExists(atPath: skins.appending(path: "spanish_001/joker_red.png").path))
    }

    @Test("builds the manifest with hashes, sizes, conventional product ids and item metadata")
    func buildsManifest() throws {
        let skins = try temporaryDirectory()
        let folder = skins.appending(path: "spanish_001")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("ace".utf8).write(to: folder.appending(path: "front.As.png"))
        try Data("ten".utf8).write(to: folder.appending(path: "front.Ts.png"))
        try Data(#"{"kind": "cardFront", "names": {"en": "Spanish"}, "sellsSingleCards": true, "badge": "New"}"#.utf8)
            .write(to: folder.appending(path: "item.json"))
        let back = skins.appending(path: "red_check")
        try FileManager.default.createDirectory(at: back, withIntermediateDirectories: true)
        try Data("back".utf8).write(to: back.appending(path: "back.png"))

        let catalog = try CatalogPublisher.buildManifest(skinsDirectory: skins, catalogVersion: 3, assetBaseURL: "/skins/")

        #expect(catalog.catalogVersion == 3)
        #expect(catalog.items.map(\.id) == ["red_check", "spanish_001"])
        let spanish = try #require(catalog.item("spanish_001"))
        #expect(spanish.productID == "fap.skin.spanish_001.set")
        #expect(spanish.sellsSingleCards)
        #expect(spanish.badge == "New")
        let ace = try #require(spanish.assets[.cardFront(card("As"))])
        #expect(ace.path == "spanish_001/front.As.png")
        #expect(ace.bytes == 3)
        #expect(ace.sha256 == SHA256.hash(data: Data("ace".utf8)).map { String(format: "%02x", $0) }.joined())
        #expect(spanish.preview == ace, "the ace of spades previews a set")
        let backItem = try #require(catalog.item("red_check"))
        #expect(backItem.kind == .cardBack, "kind is inferred from the files when item.json is absent")
        #expect(backItem.productID == "fap.skin.red_check")
        #expect(backItem.preview == backItem.assets[.cardBack])
    }

    @Test("generates an Ed25519 key pair as base64")
    func keygen() throws {
        let pair = CatalogPublisher.generateKeyPair()
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: try #require(Data(base64Encoded: pair.privateKey)))
        #expect(privateKey.publicKey.rawRepresentation.base64EncodedString() == pair.publicKey)
    }
}
