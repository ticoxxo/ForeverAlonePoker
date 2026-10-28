# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ForeverAlonePoker is a SwiftUI iOS app (iPhone + iPad) for No-Limit Texas Hold'em at tables of two to six players (heads-up by default; tdr/0013), playable over the local network (Network.framework with Bonjour and a passcode-derived TLS key) and the internet (Hummingbird server over WebSockets). The game rules live in a pure Swift package shared by the app and the server.

Decision records in `tdr/` are the source of truth for architecture. **Read the relevant record before changing a feature; write a new one (from `tdr/TEMPLATE.md`) for every new feature or changed decision.**

## Layout

```
Packages/PokerCore/            CORE: pure engine, Swift 6, no UI/network imports (tdr/0001)
  Sources/PokerCore/           Cards, HandEvaluation, Hand, Match, Protocol, Authority
  Sources/PokerCoreTestSupport Builders shared by every test target (tdr/0002)
  Tests/PokerCoreTests/
Packages/SkinKit/              Pure skin model: slots, catalog, loadout, resolver (tdr/0011); reads PokerCore, never the reverse
  Sources/SkinKitTestSupport   SkinCatalogBuilder, LoadoutBuilder
ForeverAlonePoker/             app target (files auto-included)
  App/                         @main entry and routing only
  Shared/                      Transport, Session, Persistence, Identity, DesignSystem, Audio (music, effects, sound settings), Skins (store, StoreKit, catalog, downloads, transaction pinning, support contact)
  Features/<Name>/             one folder per user-facing feature
ForeverAlonePokerTests/        Swift Testing; imports PokerCoreTestSupport
ForeverAlonePokerUITests/      XCTest smoke tests
Server/                        Hummingbird package depending on ../Packages/PokerCore (tdr/0008)
  Sources/PokerServerCore/     rooms, registry, REST + WebSocket routes, Store/ (signed skin catalog, tdr/0012)
  Sources/PokerServer/         executable (HOST/PORT env)
  Sources/PokerBot/            dev opponent: joins a room and checks/calls
  Sources/SkinPublisher/       dev tool: artwork -> SkinAssets + manifest.json, keygen
  SkinAssets/                  remote skins served at /skins (Spanish set, red backs)
StoreKit/SkinStore.storekit    local StoreKit configuration for the skin products
  Tests/PokerServerTests/
tdr/                           decision records
```

Dependency direction: `App → Features → Shared → PokerCore`. Features never import each other.

## Working rules

- **TDD.** Write the failing Swift Testing test first, then the implementation. One behaviour per test.
- **Builders, never duplicated fixtures.** Use `cards("As Kd")`, `HandStateBuilder`, `HandEngine.play`, `MatchStateBuilder`, `MatchRoomBuilder`, `TestPlayers` from `PokerCoreTestSupport`. Add new builders there when they only need PokerCore types.
- **Persistence on device is SwiftData.** Schema must stay CloudKit-compatible (defaults on all properties, optional relationships, no unique attributes).
- **CORE stays pure.** No `import SwiftUI`, `UIKit`, `Combine` or networking in `Packages/PokerCore/Sources/PokerCore`. Prefer Swift concurrency over Combine everywhere.
- **Authority, not trust.** Clients never run rules; they send `ClientMessage` and render `PlayerView` (tdr/0003).

## Build & test

Single scheme `ForeverAlonePoker`; targets: `ForeverAlonePoker`, `ForeverAlonePokerTests`, `ForeverAlonePokerUITests`. Deployment target is iOS 17 (the packages declare `.iOS(.v17)` too); Liquid Glass is iOS 26+, so it is only used through the availability-gated helpers in `Theme.swift` (tdr/0018).

```sh
# CORE package (fastest feedback; run after every engine change)
swift test --package-path Packages/PokerCore

# Skin model package
swift test --package-path Packages/SkinKit

# Server package
swift test --package-path Server
swift run --package-path Server PokerServer            # listens on 0.0.0.0:8080
swift run --package-path Server PokerBot [ROOMCODE]    # omit the code to create a room and print it
swift run --package-path Server SkinPublisher import <artwork-dir>   # artist PNGs -> Server/SkinAssets/<item>/<slot>.png
swift run --package-path Server SkinPublisher manifest              # rehash and bump Server/SkinAssets/manifest.json
swift run --package-path Server SkinPublisher keygen                # catalog signing key pair (private half is a server secret)
# Docker image (build context = repo root): docker build -f Server/Dockerfile -t pokerserver .

# Build the app
xcodebuild -scheme ForeverAlonePoker -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' build

# All app tests (unit + UI)
xcodebuild -scheme ForeverAlonePoker -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test

# Unit tests only
xcodebuild ... test -only-testing:ForeverAlonePokerTests

# Single test (Swift Testing: Target/Suite/function())
xcodebuild ... test -only-testing:'ForeverAlonePokerTests/AppLinksPokerCoreTests/linksCore()'

# Single UI test (XCTest: Target/Class/method)
xcodebuild ... test -only-testing:ForeverAlonePokerUITests/ForeverAlonePokerUITests/testExample
```

Use `xcrun simctl list devices available` to pick a valid simulator name if `iPhone 17` on iOS 27.0 isn't installed, and specify `OS=` to choose the runtime. Run tests on a simulator: Xcode's active destination may be a physical iPhone, where the unit-test runner fails to bootstrap.

## Things that aren't obvious from the code

- **Files are auto-included.** Targets use Xcode's file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup`), so any file added under `ForeverAlonePoker/`, `ForeverAlonePokerTests/`, or `ForeverAlonePokerUITests/` is automatically part of that target. Never edit `project.pbxproj` directly (it can crash an open Xcode). The local package `Packages/PokerCore` is linked through Xcode's UI: File > Add Package Dependencies > Add Local, then link `PokerCore` to the app target and `PokerCore` + `PokerCoreTestSupport` to `ForeverAlonePokerTests`.
- **Default MainActor isolation in the app target only.** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the `ForeverAlonePoker` app target, so app types are implicitly `@MainActor` unless marked `nonisolated`. The **test targets do not have it**: test suites and helpers that touch `MatchSessionClient` or other app types must be marked `@MainActor` explicitly, or the build emits isolation warnings that become errors in Swift 6 mode. The package has normal (nonisolated) defaults and Swift 6 strict concurrency.
- **App Swift language mode is 5.0** (`SWIFT_VERSION = 5.0`); `Packages/PokerCore` is Swift 6 mode.
- **Dealing order is fixed** (two cards to each seat with chips in seat order, then the board, no burns) so rigged decks in tests are predictable. `HandStateBuilder().stacks(...)` takes one stack per seat; seats three to six get default small pairs.
- **The room starts in a lobby** (tdr/0013). Heads-up deals as soon as the second player sits down (no Ready for the first hand); bigger tables deal when the host sends `startMatch` and the hosting layer (`HostedTable` / server `Room`) calls `beginMatch()` after its grace period. Tests drive `MatchRoom.beginMatch()` directly or use `seatThreeAndDeal()`. Between hands nobody presses Ready (tdr/0014): the hosting layer deals after `nextHandPause` via `nextHandTicket`/`dealNextHand(ticket:)`, and expires a dropped seat after `absenceTimeout` via `Absence`/`expire(_:)`; Ready only accepts a rematch. Tests call `room.dealNextHand()`. Leaving a match in play is a drop too (tdr/0016): the hand is folded and the seat held until the absence expires; hosting layers call `MatchAuthority.receive` to learn the absence. A join from the same identity always takes its seat back. Online clients reconnect by themselves (`MatchSessionClient(reconnect:)`).
- **Expected runtime warning in tests:** `Class _TtC9PokerCore14MatchAuthority is implemented in both …PokerCore…framework and …ForeverAlonePokerTests`. The test bundle links PokerCore statically while the app gets Xcode's dynamic package framework. Making the products dynamic is blocked (Xcode refuses a dynamic product named like its target without a project-file change). Harmless for this code; do not chase it.
- **MultipeerConnectivity is deprecated in iOS 27.** Local play uses Network.framework (`Shared/Transport/Nearby`, tdr/0007). Do not reintroduce `MCSession`.
- **SwiftData in tests:** keep the `ModelContainer` alive for the whole test (see `Fixture` in `IdentityStoreTests`); a model whose container was released asserts on property access.
- **CloudKit mirroring traps without the entitlement.** `Persistence.store()` only tries `cloudKitDatabase: .private(...)` when `Persistence.isCloudEligible` (not a test host, `disableCloudSync` default unset). Building with `CODE_SIGNING_ALLOWED=NO` (useful when signing is blocked) produces an unsigned app: unit tests still work because the test host is detected, but do not run such a build as an app with cloud enabled.
- **Signing needs the capabilities registered.** `ForeverAlonePoker.entitlements` carries iCloud/CloudKit, Push and Sign in with Apple; Xcode registers them on the App ID with automatic signing, which fails until the current Program License Agreement is accepted on developer.apple.com.
- **Glass only through `Theme`** (tdr/0018). Use `tableGlass`/`surfaceGlass`/`glassButtonStyle`/`GlassGroup`; calling `glassEffect` or `.buttonStyle(.glass)` directly breaks the iOS 17 build. Movement goes through `motion(_:value:)` so Reduce Motion is honoured.
- **Layout follows space, not device** (tdr/0017). The table picks `TableArrangement` (portrait / landscape / spacious) from its container size, so rotation, iPad split view and the foldable all go through one rule; never branch on `UIDevice` or hard-code card sizes. Use `Theme` tokens (`Shared/DesignSystem/Theme.swift`): tap targets ≥ 44 pt, main actions 56 pt, semantic text styles only.
- **Skins never reach the game.** Cards read `@Environment(\.cardSkin)`; ownership comes only from StoreKit entitlements, never SwiftData; prices come only from the App Store (`Product.displayPrice`), never the catalog. Every fallback goes through `SkinResolver` (tdr/0011, tdr/0012).
- **Transactions are pinned to a bundled root** (tdr/0022, tdr/0024). `TransactionCertificateValidator` pins every App Store transaction (production, sandbox, TestFlight) to `AppleIncRootCertificate.cer` (holds Apple Root CA – G3) in `ForeverAlonePoker/Resources/Certificates/` (whitelisted in `.gitignore`, which ignores `*.cer`); without it every purchase is denied. Xcode StoreKit testing transactions cannot be pinned (their key chains to no bundleable root; the saved `StoreKitTestCertificate.cer` only signs legacy receipts), so Debug builds accept `environment == .xcode` on StoreKit's verification and Release builds deny them. Refunds go through Apple's sheet only (`Features/SkinStore/Help`); support mail is in `SupportContact`.
- **SkinKit is a second local package** linked through Xcode's UI like PokerCore: `SkinKit` to the app, `SkinKit` + `SkinKitTestSupport` to `ForeverAlonePokerTests`.
- **Skin artwork is PNG** (750×1050). SVG masters cannot be rendered at runtime on iOS (no public renderer; CoreSVG drops `<text>`). Jokers are never shipped.
- **Ranked play on the server is opt-in by environment** (`SESSION_SECRET`, `CLOUDKIT_KEY_ID`, `CLOUDKIT_PRIVATE_KEY[_PATH]`, see tdr/0010). Without them every match is unranked and `POST /auth/apple` answers 503.
- **Test frameworks differ by target:** unit tests use Swift Testing with `@testable import ForeverAlonePoker`; UI tests use XCTest/XCUIApplication.
- Bundle ID prefix: `Ticoxxo.ForeverAlonePoker`. Planned iCloud container: `iCloud.Ticoxxo.ForeverAlonePoker`.
