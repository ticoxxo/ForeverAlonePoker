import CryptoKit
import Foundation
import Testing
import SkinKit
import SkinKitTestSupport
@testable import ForeverAlonePoker

@Suite("CatalogClient")
struct CatalogClientTests {
    private let key = Curve25519.Signing.PrivateKey()
    private let catalog = SkinCatalogBuilder().version(4).with(SkinCatalogBuilder.back("red_check")).build()

    private func signed(_ catalog: SkinCatalog, with key: Curve25519.Signing.PrivateKey? = nil, keyID: String = "k1") throws -> SignedCatalog {
        let manifest = try catalog.encoded()
        return SignedCatalog(manifest: manifest, signature: try (key ?? self.key).signature(for: manifest), keyID: keyID)
    }

    private var trust: CatalogTrust { CatalogTrust(keys: ["k1": key.publicKey.rawRepresentation]) }

    @Test("a catalog signed by a pinned key verifies")
    func verifies() throws {
        #expect(try trust.verify(signed(catalog)) == catalog)
    }

    @Test("tampered manifests, foreign keys and unknown key ids are refused")
    func refuses() throws {
        let good = try signed(catalog)
        let tampered = SignedCatalog(manifest: try SkinCatalogBuilder().version(5).build().encoded(), signature: good.signature, keyID: "k1")
        #expect(throws: CatalogError.badSignature) { try trust.verify(tampered) }
        #expect(throws: CatalogError.badSignature) { try trust.verify(signed(catalog, with: Curve25519.Signing.PrivateKey())) }
        #expect(throws: CatalogError.unknownKey("k9")) { try trust.verify(signed(catalog, keyID: "k9")) }
    }

    @Test("unsigned catalogs are refused unless development trust allows them")
    func unsigned() throws {
        let unsigned = SignedCatalog(manifest: try catalog.encoded(), signature: Data(), keyID: "")
        #expect(throws: CatalogError.unsigned) { try trust.verify(unsigned) }
        #expect(try CatalogTrust(keys: [:], allowsUnsigned: true).verify(unsigned) == catalog)
    }

    @Test("fetches, caches after verifying, and revalidates with the ETag")
    func fetchAndRevalidate() async throws {
        let body = try JSONEncoder().encode(signed(catalog))
        let cacheURL = URL.temporaryDirectory.appending(path: "catalog-\(UUID().uuidString).json")
        let seenETags = Recorder()
        let client = HTTPCatalogClient(serverURL: URL(string: "http://server.test")!, trust: trust, cacheURL: cacheURL) { request in
            let etag = request.value(forHTTPHeaderField: "If-None-Match")
            await seenETags.append(etag)
            let status = etag == "\"v4\"" ? 304 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["ETag": "\"v4\""])!
            return (status == 200 ? body : Data(), response)
        }

        #expect(try await client.fetchLatest() == catalog)
        #expect(await client.cachedCatalog() == catalog)
        #expect(try await client.fetchLatest() == nil, "unchanged")
        #expect(await seenETags.values == [nil, "\"v4\""])
    }

    @Test("a catalog that fails verification is neither returned nor cached")
    func badCatalogNotCached() async throws {
        let body = try JSONEncoder().encode(signed(catalog, with: Curve25519.Signing.PrivateKey()))
        let cacheURL = URL.temporaryDirectory.appending(path: "catalog-\(UUID().uuidString).json")
        let client = HTTPCatalogClient(serverURL: URL(string: "http://server.test")!, trust: trust, cacheURL: cacheURL) { request in
            (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: CatalogError.badSignature) { try await client.fetchLatest() }
        #expect(await client.cachedCatalog() == nil)
    }

    @Test("asset paths resolve against the catalog's base, relative or absolute")
    func assetURLs() {
        let client = HTTPCatalogClient(serverURL: URL(string: "http://server.test:8080")!, trust: trust)
        let asset = SkinCatalogBuilder.asset("red_check", .cardBack)
        let relative = SkinCatalogBuilder().assetBase("/skins/").build()
        let cdn = SkinCatalogBuilder().assetBase("https://cdn.test/v7/").build()
        #expect(client.assetURL(for: asset, in: relative)?.absoluteString == "http://server.test:8080/skins/red_check/back.png")
        #expect(client.assetURL(for: asset, in: cdn)?.absoluteString == "https://cdn.test/v7/red_check/back.png")
    }
}

private actor Recorder {
    private(set) var values: [String?] = []
    func append(_ value: String?) { values.append(value) }
}
