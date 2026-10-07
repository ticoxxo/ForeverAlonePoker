# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ForeverAlonePoker is a SwiftUI iOS app (iPhone + iPad) for heads-up (1v1) No-Limit Texas Hold'em, playable over the local network (Network.framework with Bonjour and a passcode-derived TLS key) and the internet (Hummingbird server over WebSockets). The game rules live in a pure Swift package shared by the app and the server.

Decision records in `tdr/` are the source of truth for architecture. **Read the relevant record before changing a feature; write a new one (from `tdr/TEMPLATE.md`) for every new feature or changed decision.**

## Layout

```
Packages/PokerCore/            CORE: pure engine, Swift 6, no UI/network imports (tdr/0001)
  Sources/PokerCore/           Cards, HandEvaluation, Hand, Match, Protocol, Authority
  Sources/PokerCoreTestSupport Builders shared by every test target (tdr/0002)
  Tests/PokerCoreTests/
ForeverAlonePoker/             app target (files auto-included)
  App/                         @main entry and routing only
  Shared/                      Transport, Session, Persistence, Identity, DesignSystem
  Features/<Name>/             one folder per user-facing feature
ForeverAlonePokerTests/        Swift Testing; imports PokerCoreTestSupport
ForeverAlonePokerUITests/      XCTest smoke tests
Server/                        Hummingbird package depending on ../Packages/PokerCore (tdr/0008)
  Sources/PokerServerCore/     rooms, registry, REST + WebSocket routes (library, tested)
  Sources/PokerServer/         executable (HOST/PORT env)
  Sources/PokerBot/            dev opponent: joins a room and checks/calls
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

Single scheme `ForeverAlonePoker`; targets: `ForeverAlonePoker`, `ForeverAlonePokerTests`, `ForeverAlonePokerUITests`. Deployment target is iOS 27.0, so a matching simulator runtime is required.

```sh
# CORE package (fastest feedback; run after every engine change)
swift test --package-path Packages/PokerCore

# Server package
swift test --package-path Server
swift run --package-path Server PokerServer            # listens on 0.0.0.0:8080
swift run --package-path Server PokerBot [ROOMCODE]    # omit the code to create a room and print it
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

Use `xcrun simctl list devices available` to pick a valid simulator name if `iPhone 17` on iOS 27.0 isn't installed. Specify `OS=27.0`, because the same device name also exists on older runtimes that are below the deployment target.

## Things that aren't obvious from the code

- **Files are auto-included.** Targets use Xcode's file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup`), so any file added under `ForeverAlonePoker/`, `ForeverAlonePokerTests/`, or `ForeverAlonePokerUITests/` is automatically part of that target. Never edit `project.pbxproj` directly (it can crash an open Xcode). The local package `Packages/PokerCore` is linked through Xcode's UI: File > Add Package Dependencies > Add Local, then link `PokerCore` to the app target and `PokerCore` + `PokerCoreTestSupport` to `ForeverAlonePokerTests`.
- **Default MainActor isolation in the app target only.** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the `ForeverAlonePoker` app target, so app types are implicitly `@MainActor` unless marked `nonisolated`. The **test targets do not have it**: test suites and helpers that touch `MatchSessionClient` or other app types must be marked `@MainActor` explicitly, or the build emits isolation warnings that become errors in Swift 6 mode. The package has normal (nonisolated) defaults and Swift 6 strict concurrency.
- **App Swift language mode is 5.0** (`SWIFT_VERSION = 5.0`); `Packages/PokerCore` is Swift 6 mode.
- **Dealing order is fixed** (seat one's two cards, seat two's, then the board, no burns) so rigged decks in tests are predictable.
- **Expected runtime warning in tests:** `Class _TtC9PokerCore14MatchAuthority is implemented in both …PokerCore…framework and …ForeverAlonePokerTests`. The test bundle links PokerCore statically while the app gets Xcode's dynamic package framework. Making the products dynamic is blocked (Xcode refuses a dynamic product named like its target without a project-file change). Harmless for this code; do not chase it.
- **MultipeerConnectivity is deprecated in iOS 27.** Local play uses Network.framework (`Shared/Transport/Nearby`, tdr/0007). Do not reintroduce `MCSession`.
- **SwiftData in tests:** keep the `ModelContainer` alive for the whole test (see `Fixture` in `IdentityStoreTests`); a model whose container was released asserts on property access.
- **Test frameworks differ by target:** unit tests use Swift Testing with `@testable import ForeverAlonePoker`; UI tests use XCTest/XCUIApplication.
- Bundle ID prefix: `Ticoxxo.ForeverAlonePoker`. Planned iCloud container: `iCloud.Ticoxxo.ForeverAlonePoker`.
