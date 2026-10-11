import Crypto
import Foundation
import SkinKit

/// Signs catalogs with the publisher's Ed25519 key. The app pins the public
/// half and refuses catalogs that do not verify (tdr/0012).
public struct CatalogSigner: Sendable {
    public let keyID: String
    public let privateKey: Curve25519.Signing.PrivateKey

    public init(keyID: String, privateKey: Curve25519.Signing.PrivateKey) {
        self.keyID = keyID
        self.privateKey = privateKey
    }

    public func sign(_ manifest: Data) throws -> Data {
        try privateKey.signature(for: manifest)
    }
}

/// Where the store's files live and how the catalog is signed.
public struct StoreConfiguration: Sendable {
    public enum EnvironmentKey {
        /// Folder with `manifest.json` and one sub-folder per item, served at `/skins`.
        public static let skinsDirectory = "SKINS_DIR"
        /// Base64 raw 32-byte Ed25519 private key (`SkinPublisher keygen`).
        public static let signingKey = "CATALOG_SIGNING_KEY"
        public static let keyID = "CATALOG_KEY_ID"
    }

    public enum ConfigurationError: Error {
        case invalidSigningKey
    }

    public let skinsDirectory: URL
    public let signer: CatalogSigner?

    public init(skinsDirectory: URL, signer: CatalogSigner?) {
        self.skinsDirectory = skinsDirectory
        self.signer = signer
    }

    public var manifestURL: URL { skinsDirectory.appending(path: "manifest.json") }

    /// `nil` when no skins directory is configured or found; the store routes
    /// then answer 503. Without `SKINS_DIR`, `SkinAssets` or `Server/SkinAssets`
    /// under the working directory is used when present.
    public static func fromEnvironment(
        _ env: [String: String],
        fileManager: FileManager = .default
    ) throws -> StoreConfiguration? {
        let directory: URL
        if let configured = env[EnvironmentKey.skinsDirectory], !configured.isEmpty {
            directory = URL(filePath: configured, directoryHint: .isDirectory)
        } else if let found = ["SkinAssets", "Server/SkinAssets"].first(where: { fileManager.fileExists(atPath: "\($0)/manifest.json") }) {
            directory = URL(filePath: found, directoryHint: .isDirectory)
        } else {
            return nil
        }

        var signer: CatalogSigner?
        if let encoded = env[EnvironmentKey.signingKey], !encoded.isEmpty {
            guard let raw = Data(base64Encoded: encoded),
                  let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
                throw ConfigurationError.invalidSigningKey
            }
            signer = CatalogSigner(keyID: env[EnvironmentKey.keyID] ?? "default", privateKey: key)
        }
        return StoreConfiguration(skinsDirectory: directory, signer: signer)
    }
}

/// Serves the current catalog. Re-reads `manifest.json` when it changes on
/// disk, so publishing a set is a file copy with no restart, and keeps serving
/// the last good catalog when a new file is malformed.
public actor CatalogService {
    public struct Published: Sendable, Equatable {
        public let catalog: SignedCatalog
        public let etag: String
    }

    private let manifestURL: URL
    private let signer: CatalogSigner?
    private var cached: (modified: Date, published: Published)?

    public init(manifestURL: URL, signer: CatalogSigner?) {
        self.manifestURL = manifestURL
        self.signer = signer
    }

    public func current() throws -> Published {
        let attributes = try FileManager.default.attributesOfItem(atPath: manifestURL.path)
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        if let cached, cached.modified == modified { return cached.published }

        let manifest = try Data(contentsOf: manifestURL)
        do {
            _ = try SkinCatalog.decode(from: manifest)
        } catch {
            // Keep serving what clients already trust rather than a broken store.
            if let cached { return cached.published }
            throw error
        }
        let signature = try signer?.sign(manifest) ?? Data()
        let digest = SHA256.hash(data: manifest).prefix(16).map { String(format: "%02x", $0) }.joined()
        let published = Published(
            catalog: SignedCatalog(manifest: manifest, signature: signature, keyID: signer?.keyID ?? ""),
            etag: "\"\(digest)\""
        )
        cached = (modified, published)
        return published
    }
}
