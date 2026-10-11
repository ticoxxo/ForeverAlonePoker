import CryptoKit
import Foundation
import SkinKit

nonisolated enum CatalogError: Error, Equatable {
    case badResponse(status: Int)
    case unsigned
    case unknownKey(String)
    case badSignature
}

/// Where the store's catalog comes from (tdr/0012).
nonisolated protocol CatalogProviding: Sendable {
    /// The last catalog that verified, from disk, for offline launches.
    func cachedCatalog() async -> SkinCatalog?
    /// The server's catalog, or `nil` when it has not changed since the last fetch.
    func fetchLatest() async throws -> SkinCatalog?
    /// Absolute URL of one of the catalog's files.
    func assetURL(for asset: AssetRef, in catalog: SkinCatalog) -> URL?
}

/// The publisher keys the app trusts. Public halves are pinned in Info.plist
/// under `SkinCatalogPublicKeys` (key id → base64 raw Ed25519 public key), so
/// a key can be rotated by shipping the new one before using it.
nonisolated struct CatalogTrust: Sendable {
    /// Raw 32-byte Ed25519 public keys by key id.
    let keys: [String: Data]
    /// Development only: accept a server with no signing key.
    let allowsUnsigned: Bool

    init(keys: [String: Data], allowsUnsigned: Bool = false) {
        self.keys = keys
        self.allowsUnsigned = allowsUnsigned
    }

    /// Pinned keys from the app's Info.plist; debug builds without pinned keys
    /// also accept unsigned development catalogs.
    static func fromBundle(_ bundle: Bundle = .main) -> CatalogTrust {
        let entries = bundle.object(forInfoDictionaryKey: "SkinCatalogPublicKeys") as? [String: String] ?? [:]
        let keys = entries.compactMapValues { encoded in
            Data(base64Encoded: encoded).flatMap { (try? Curve25519.Signing.PublicKey(rawRepresentation: $0))?.rawRepresentation }
        }
        #if DEBUG
        return CatalogTrust(keys: keys, allowsUnsigned: keys.isEmpty)
        #else
        return CatalogTrust(keys: keys)
        #endif
    }

    func verify(_ signed: SignedCatalog) throws -> SkinCatalog {
        if signed.isSigned {
            guard let raw = keys[signed.keyID], let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
                throw CatalogError.unknownKey(signed.keyID)
            }
            guard key.isValidSignature(signed.signature, for: signed.manifest) else { throw CatalogError.badSignature }
        } else if !allowsUnsigned {
            throw CatalogError.unsigned
        }
        return try SkinCatalog.decode(from: signed.manifest)
    }
}

/// `GET /store/catalog` on the game server, revalidated with its ETag and
/// cached on disk only after the signature verified.
actor HTTPCatalogClient: CatalogProviding {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    nonisolated let catalogURL: URL
    private let trust: CatalogTrust
    private let cacheURL: URL
    private let fetch: Fetch

    init(
        serverURL: URL,
        trust: CatalogTrust = .fromBundle(),
        cacheURL: URL = URL.cachesDirectory.appending(path: "skin-catalog.json"),
        fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }
    ) {
        catalogURL = serverURL.appending(path: "store/catalog")
        self.trust = trust
        self.cacheURL = cacheURL
        self.fetch = fetch
    }

    func cachedCatalog() -> SkinCatalog? {
        guard let cached = readCache() else { return nil }
        // Re-verified so a file edited on disk is never trusted.
        return try? trust.verify(cached.signed)
    }

    func fetchLatest() async throws -> SkinCatalog? {
        var request = URLRequest(url: catalogURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let cached = readCache()
        if let etag = cached?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        let (data, response) = try await fetch(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 304, cached != nil { return nil }
        guard status == 200 else { throw CatalogError.badResponse(status: status) }

        let signed = try JSONDecoder().decode(SignedCatalog.self, from: data)
        let catalog = try trust.verify(signed)
        let etag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
        try? JSONEncoder().encode(CacheEntry(signed: signed, etag: etag)).write(to: cacheURL, options: .atomic)
        return catalog
    }

    nonisolated func assetURL(for asset: AssetRef, in catalog: SkinCatalog) -> URL? {
        guard let base = URL(string: catalog.assetBaseURL, relativeTo: catalogURL) else { return nil }
        return URL(string: asset.path, relativeTo: base.absoluteURL)?.absoluteURL
    }

    private func readCache() -> CacheEntry? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }

    private struct CacheEntry: Codable {
        let signed: SignedCatalog
        let etag: String?
    }
}
