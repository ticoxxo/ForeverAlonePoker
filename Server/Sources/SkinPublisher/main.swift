import Foundation
import PokerServerCore
import SkinKit

// Development publisher for the skin store (tdr/0012). The production pricing
// project produces the same manifest with the same SkinKit types; prices live
// in App Store Connect, never here.
//
//   swift run --package-path Server SkinPublisher import <artwork-folder> [skins-dir]
//   swift run --package-path Server SkinPublisher import-chips <artwork-folder> [skins-dir] [--bundled DIR]
//   swift run --package-path Server SkinPublisher manifest [skins-dir] [--version N] [--base /skins/]
//   swift run --package-path Server SkinPublisher keygen
//
// skins-dir defaults to Server/SkinAssets; --bundled (the free chips) to
// ForeverAlonePoker/Assets.xcassets/Skins. After `manifest`, a running server
// picks the new catalog up on the next request.

let defaultSkinsDirectory = "Server/SkinAssets"
/// Where the free defaults are bundled into the app.
let defaultBundledSkinsDirectory = "ForeverAlonePoker/Assets.xcassets/Skins"
/// Splits `--name value` pairs from positional arguments.
func parse(_ raw: [String]) -> (positional: [String], options: [String: String]) {
    var positional: [String] = []
    var options: [String: String] = [:]
    var iterator = raw.makeIterator()
    while let argument = iterator.next() {
        if argument.hasPrefix("--"), let value = iterator.next() {
            options[argument] = value
        } else {
            positional.append(argument)
        }
    }
    return (positional, options)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let (positional, options) = parse(Array(CommandLine.arguments.dropFirst()))
let command = positional.first ?? "help"
let arguments = Array(positional.dropFirst())

switch command {
case "import":
    guard let source = arguments.first else { fail("usage: SkinPublisher import <artwork-folder> [skins-dir]") }
    let skins = URL(filePath: arguments.dropFirst().first ?? defaultSkinsDirectory, directoryHint: .isDirectory)
    let counts = try CatalogPublisher.importArtwork(from: URL(filePath: source, directoryHint: .isDirectory), into: skins)
    for (item, count) in counts.sorted(by: { $0.key < $1.key }) {
        print("\(item): \(count) file(s)")
    }

case "import-chips":
    guard let source = arguments.first else { fail("usage: SkinPublisher import-chips <artwork-folder> [skins-dir] [--bundled DIR]") }
    let skins = URL(filePath: arguments.dropFirst().first ?? defaultSkinsDirectory, directoryHint: .isDirectory)
    let bundled = URL(filePath: options["--bundled"] ?? defaultBundledSkinsDirectory, directoryHint: .isDirectory)
    let counts = try CatalogPublisher.importChips(from: URL(filePath: source, directoryHint: .isDirectory), into: skins, bundledAssets: bundled)
    for (item, count) in counts.sorted(by: { $0.key < $1.key }) {
        print("\(item): \(count) file(s)")
    }

case "manifest":
    let base = options["--base"] ?? "/skins/"
    let explicitVersion = options["--version"].flatMap(Int.init)
    let skins = URL(filePath: arguments.first ?? defaultSkinsDirectory, directoryHint: .isDirectory)
    let manifestURL = skins.appending(path: "manifest.json")
    let previous = (try? Data(contentsOf: manifestURL)).flatMap { try? SkinCatalog.decode(from: $0) }
    let version = explicitVersion ?? (previous?.catalogVersion ?? 0) + 1
    let catalog = try CatalogPublisher.buildManifest(skinsDirectory: skins, catalogVersion: version, assetBaseURL: base)
    try catalog.encoded().write(to: manifestURL, options: .atomic)
    print("Wrote catalog version \(version) with \(catalog.items.count) item(s) to \(manifestURL.path)")

case "keygen":
    let pair = CatalogPublisher.generateKeyPair()
    print("CATALOG_SIGNING_KEY=\(pair.privateKey)    # server secret; never commit")
    print("Public key for Info.plist SkinCatalogPublicKeys: \(pair.publicKey)")

default:
    print("usage: SkinPublisher import <artwork-folder> [skins-dir] | import-chips <artwork-folder> [skins-dir] [--bundled DIR] | manifest [skins-dir] [--version N] [--base URL] | keygen")
}
