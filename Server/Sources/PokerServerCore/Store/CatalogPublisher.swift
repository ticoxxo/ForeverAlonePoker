import Crypto
import Foundation
import PokerCore
import SkinKit

/// Turns artwork into what the store serves (tdr/0012). Used by the
/// `SkinPublisher` tool here; the separate pricing project produces the same
/// manifest with the same SkinKit types.
///
/// Layout of a skins directory:
/// ```
/// manifest.json
/// spanish_001/item.json        optional metadata (kind, names, badge, …)
/// spanish_001/front.As.png     one file per slot, named by AssetNaming
/// red_check/back.png
/// premium_01_chips/chips.100.top.small.png
/// ```
public enum CatalogPublisher {
    /// Optional per-item metadata in `<item>/item.json`.
    struct ItemMetadata: Decodable {
        var kind: CosmeticKind?
        var names: [String: String]?
        var productID: String?
        var minAppVersion: AppVersion?
        var badge: String?
    }

    /// Copies every PNG under `source` whose name `AssetNaming` understands
    /// into `<skins>/<item>/<slot>.png`. Jokers, previews and SVG masters are
    /// skipped. Returns how many files each item received.
    @discardableResult
    public static func importArtwork(from source: URL, into skins: URL) throws -> [SkinID: Int] {
        let fileManager = FileManager.default
        var counts: [SkinID: Int] = [:]
        guard let files = fileManager.enumerator(at: source, includingPropertiesForKeys: nil) else { return [:] }
        for case let file as URL in files where file.pathExtension.lowercased() == "png" {
            guard let (item, slot) = AssetNaming.parse(fileStem: file.deletingPathExtension().lastPathComponent) else { continue }
            let folder = skins.appending(path: item.rawValue, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appending(path: AssetNaming.fileName(for: slot))
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.copyItem(at: file, to: destination)
            counts[item, default: 0] += 1
        }
        return counts
    }

    /// Copies chip artwork named as `AssetNaming.parseChip` expects (tdr/0027).
    /// Premium sets go to `<skins>/<item>/<slot>.png` to be sold; the classic
    /// set goes into `bundledAssets` (the app's `Assets.xcassets/Skins`) as one
    /// image set per slot, because defaults ship in the binary. Returns how
    /// many files each item received.
    @discardableResult
    public static func importChips(from source: URL, into skins: URL, bundledAssets: URL) throws -> [SkinID: Int] {
        let fileManager = FileManager.default
        var counts: [SkinID: Int] = [:]
        guard let files = fileManager.enumerator(at: source, includingPropertiesForKeys: nil) else { return [:] }
        for case let file as URL in files where file.pathExtension.lowercased() == "png" {
            guard let (item, slot) = AssetNaming.parseChip(fileStem: file.deletingPathExtension().lastPathComponent) else { continue }
            let destination: URL
            if item == SkinCatalog.defaultChipsID {
                let name = AssetNaming.bundledImageName(item: item, slot: slot)
                let imageSet = bundledAssets.appending(path: "\(name).imageset", directoryHint: .isDirectory)
                try fileManager.createDirectory(at: imageSet, withIntermediateDirectories: true)
                try imageSetContents(fileName: "\(name).png").write(to: imageSet.appending(path: "Contents.json"), options: .atomic)
                destination = imageSet.appending(path: "\(name).png")
            } else {
                let folder = skins.appending(path: item.rawValue, directoryHint: .isDirectory)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                destination = folder.appending(path: AssetNaming.fileName(for: slot))
            }
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.copyItem(at: file, to: destination)
            counts[item, default: 0] += 1
        }
        return counts
    }

    /// The `Contents.json` Xcode writes for a single universal image.
    private static func imageSetContents(fileName: String) -> Data {
        Data("""
        {
          "images": [
            {
              "filename": "\(fileName)",
              "idiom": "universal"
            }
          ],
          "info": {
            "author": "xcode",
            "version": 1
          }
        }

        """.utf8)
    }

    /// Scans a skins directory and describes every item folder. Product ids
    /// follow `ProductIDs` unless `item.json` overrides them.
    public static func buildManifest(
        skinsDirectory: URL,
        catalogVersion: Int,
        assetBaseURL: String,
        publishedAt: Date = Date()
    ) throws -> SkinCatalog {
        let fileManager = FileManager.default
        let folders = try fileManager.contentsOfDirectory(at: skinsDirectory, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var items: [SkinItem] = []
        for folder in folders {
            let id = SkinID(folder.lastPathComponent)
            var assets: [CosmeticSlot: AssetRef] = [:]
            for file in try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where file.pathExtension == "png" {
                let slot = CosmeticSlot(rawValue: file.deletingPathExtension().lastPathComponent)
                let data = try Data(contentsOf: file)
                assets[slot] = AssetRef(
                    path: "\(id.rawValue)/\(file.lastPathComponent)",
                    sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                    bytes: data.count
                )
            }
            guard !assets.isEmpty else { continue }

            let metadataURL = folder.appending(path: "item.json")
            let metadata = fileManager.fileExists(atPath: metadataURL.path)
                ? try JSONDecoder().decode(ItemMetadata.self, from: Data(contentsOf: metadataURL))
                : ItemMetadata()
            let kind = metadata.kind ?? inferredKind(of: assets.keys)
            let soldWhole = kind == .cardFront || kind == .chips
            let productID = metadata.productID ?? (soldWhole ? ProductIDs.set(id) : ProductIDs.single(id))
            let preview = assets[.cardFront(Card(rank: .ace, suit: .spades))]
                ?? assets[.cardBack]
                ?? assets[.chip(.init(1_000), face: .top, size: .large)]
                ?? assets.sorted { $0.key < $1.key }.first?.value

            items.append(SkinItem(
                id: id,
                kind: kind,
                names: metadata.names ?? ["en": id.rawValue],
                productID: productID,
                assets: assets,
                preview: preview,
                minAppVersion: metadata.minAppVersion,
                badge: metadata.badge
            ))
        }
        return SkinCatalog(
            catalogVersion: catalogVersion,
            publishedAt: ISO8601DateFormatter().string(from: publishedAt),
            assetBaseURL: assetBaseURL,
            items: items
        )
    }

    private static func inferredKind(of slots: Dictionary<CosmeticSlot, AssetRef>.Keys) -> CosmeticKind {
        if slots.contains(.cardBack) { return .cardBack }
        if slots.contains(where: { $0.kind == .chips }) { return .chips }
        return .cardFront
    }

    /// A new Ed25519 signing key: the private half goes in `CATALOG_SIGNING_KEY`
    /// on the server (never in the repository), the public half is pinned in
    /// the app's Info.plist (`SkinCatalogPublicKeys`).
    public static func generateKeyPair() -> (privateKey: String, publicKey: String) {
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation.base64EncodedString(), key.publicKey.rawRepresentation.base64EncodedString())
    }
}
