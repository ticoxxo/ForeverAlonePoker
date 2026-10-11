import CryptoKit
import Foundation
import SkinKit

nonisolated enum SkinAssetError: Error, Equatable {
    case checksumMismatch
    case badResponse(status: Int)
}

/// Fetches one remote file to a temporary location the caller then owns.
nonisolated protocol AssetDownloading: Sendable {
    func download(_ url: URL) async throws -> URL
}

/// The skin files on this device (tdr/0012).
nonisolated protocol SkinAssetStoring: Sendable {
    /// Where an installed file lives. Deterministic, so views can build
    /// sources without awaiting.
    func fileURL(for key: AssetKey) -> URL
    /// Installed files whose hash still matches the catalog; a republished
    /// file with a new hash counts as missing and is downloaded again.
    func installed(matching catalog: SkinCatalog) async -> InstalledAssets
    /// Downloads, verifies the SHA-256 and moves the file into place.
    func install(_ key: AssetKey, from remote: URL, sha256: String) async throws
}

/// Files in `Application Support/Skins/<item>/<slot>.png`, excluded from
/// backup because they can always be downloaded again, plus an index of the
/// hash each file was verified against. An actor so hashing and file I/O stay
/// off the main thread, while several downloads are in flight at once (the
/// actor is free while a download awaits).
actor SkinAssetRepository: SkinAssetStoring {
    nonisolated let root: URL
    private let downloader: any AssetDownloading
    private var index: [AssetKey: String]

    init(root: URL = SkinAssetRepository.defaultRoot, downloader: any AssetDownloading) {
        self.root = root
        self.downloader = downloader
        index = Self.loadIndex(at: root)
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Skins", directoryHint: .isDirectory)
    }

    nonisolated func fileURL(for key: AssetKey) -> URL {
        root.appending(path: key.item.rawValue, directoryHint: .isDirectory)
            .appending(path: AssetNaming.fileName(for: key.slot))
    }

    func installed(matching catalog: SkinCatalog) -> InstalledAssets {
        Set(index.compactMap { key, sha in
            guard catalog.item(key.item)?.assets[key.slot]?.sha256 == sha,
                  FileManager.default.fileExists(atPath: fileURL(for: key).path) else { return nil }
            return key
        })
    }

    func install(_ key: AssetKey, from remote: URL, sha256: String) async throws {
        let downloaded = try await downloader.download(remote)
        defer { try? FileManager.default.removeItem(at: downloaded) }

        let data = try Data(contentsOf: downloaded, options: .mappedIfSafe)
        guard Self.hex(SHA256.hash(data: data)) == sha256.lowercased() else {
            throw SkinAssetError.checksumMismatch
        }

        try prepareRoot()
        let destination = fileURL(for: key)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        index[key] = sha256.lowercased()
        try saveIndex()
    }

    // MARK: - Private

    private var indexURL: URL { root.appending(path: "installed.json") }

    private func prepareRoot() throws {
        guard !FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func saveIndex() throws {
        let entries = index.map { IndexEntry(key: $0.key, sha256: $0.value) }
        try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
    }

    private static func loadIndex(at root: URL) -> [AssetKey: String] {
        guard let data = try? Data(contentsOf: root.appending(path: "installed.json")),
              let entries = try? JSONDecoder().decode([IndexEntry].self, from: data) else { return [:] }
        return Dictionary(entries.map { ($0.key, $0.sha256) }, uniquingKeysWith: { _, last in last })
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct IndexEntry: Codable {
        let key: AssetKey
        let sha256: String
    }
}
