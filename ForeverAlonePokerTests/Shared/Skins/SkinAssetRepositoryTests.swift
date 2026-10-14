import CryptoKit
import Foundation
import Testing
import SkinKit
import SkinKitTestSupport
@testable import ForeverAlonePoker

/// Serves bytes from memory as if downloaded.
private struct StubDownloader: AssetDownloading {
    let bytes: Data

    func download(_ url: URL) async throws -> URL {
        let file = URL.temporaryDirectory.appending(path: "download-\(UUID().uuidString)")
        try bytes.write(to: file)
        return file
    }
}

@Suite("SkinAssetRepository")
struct SkinAssetRepositoryTests {
    private let bytes = Data("png".utf8)
    private var sha: String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private let key = AssetKey(item: "red_check", slot: .cardBack)
    private let remote = URL(string: "https://cdn.test/red_check/back.png")!

    private func makeRoot() -> URL {
        URL.temporaryDirectory.appending(path: "skins-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func catalog(sha: String) -> SkinCatalog {
        SkinCatalogBuilder().with(SkinItem(
            id: "red_check",
            kind: .cardBack,
            productID: ProductIDs.single("red_check"),
            assets: [.cardBack: AssetRef(path: "red_check/back.png", sha256: sha, bytes: 3)]
        )).build()
    }

    @Test("a verified file is installed, indexed and survives a new repository instance")
    func installs() async throws {
        let root = makeRoot()
        let repository = SkinAssetRepository(root: root, downloader: StubDownloader(bytes: bytes))
        try await repository.install(key, from: remote, sha256: sha)

        #expect(try Data(contentsOf: repository.fileURL(for: key)) == bytes)
        #expect(await repository.installed(matching: catalog(sha: sha)) == [key])
        let reopened = SkinAssetRepository(root: root, downloader: StubDownloader(bytes: bytes))
        #expect(await reopened.installed(matching: catalog(sha: sha)) == [key])
        #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test("a file whose hash does not match is discarded")
    func checksum() async {
        let repository = SkinAssetRepository(root: makeRoot(), downloader: StubDownloader(bytes: Data("tampered".utf8)))
        await #expect(throws: SkinAssetError.checksumMismatch) {
            try await repository.install(key, from: remote, sha256: sha)
        }
        #expect(!FileManager.default.fileExists(atPath: repository.fileURL(for: key).path))
    }

    @Test("a republished file with a new hash counts as missing")
    func republished() async throws {
        let repository = SkinAssetRepository(root: makeRoot(), downloader: StubDownloader(bytes: bytes))
        try await repository.install(key, from: remote, sha256: sha)
        #expect(await repository.installed(matching: catalog(sha: "ffff")).isEmpty)
    }
}
