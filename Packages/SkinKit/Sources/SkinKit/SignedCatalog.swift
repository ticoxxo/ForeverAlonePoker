import Foundation

/// Body of `GET /store/catalog`: the manifest bytes exactly as signed, and an
/// Ed25519 signature over them. The app pins the publisher's public keys and
/// refuses a catalog whose signature does not verify (tdr/0012). Keeping the
/// manifest as opaque bytes avoids any re-encoding ambiguity.
public struct SignedCatalog: Codable, Hashable, Sendable {
    public let manifest: Data
    /// Empty when the server has no signing key (development only).
    public let signature: Data
    /// Which pinned key signed it, so keys can be rotated.
    public let keyID: String

    public init(manifest: Data, signature: Data, keyID: String) {
        self.manifest = manifest
        self.signature = signature
        self.keyID = keyID
    }

    public var isSigned: Bool { !signature.isEmpty }
}
