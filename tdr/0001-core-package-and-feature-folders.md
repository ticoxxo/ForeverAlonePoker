# 0001. Keep game logic in a pure Swift package and organise the app by feature

- **Status:** Accepted
- **Date:** 2026-10-07
- **Feature / area:** whole repository

## Context

ForeverAlonePoker is a heads-up (1v1) No-Limit Texas Hold'em app for iPhone and iPad. Players will face each other over the local network and over the internet. The rules of poker must behave identically on every device and on the server, must be testable without a simulator, and must not be influenced by UI or transport details.

The Xcode project has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and Swift language mode 5. Types declared inside the app target are implicitly main-actor isolated, which is wrong for an engine that a server will run on background threads.

## Decision

1. **`Packages/PokerCore` is the CORE.** It is a local Swift package (Swift 6 language mode) containing only value types and pure functions: cards, hand evaluation, the hand engine, match state, the wire protocol and the room authority. It imports nothing but the standard library. It has its own test target and a `PokerCoreTestSupport` library (see 0002). The iOS app and the Hummingbird server both depend on it, so one engine runs everywhere.

   Folder layout inside the package mirrors the domain: `Cards/`, `HandEvaluation/`, `Hand/`, `Match/`, `Protocol/`, `Authority/`, later `Rating/`.

2. **The app is organised by feature.** `ForeverAlonePoker/Features/<FeatureName>/` holds the views, view models and feature-specific glue for one user-facing capability (Home, Table, LocalMatch, OnlineMatch, Profile, Leaderboard). `ForeverAlonePoker/Shared/` holds cross-feature layers (Transport, Session, Persistence, Identity, DesignSystem). `ForeverAlonePoker/App/` holds the `@main` entry and routing only.

3. **Dependency direction is one way:** `App → Features → Shared → PokerCore`. Features never import each other; they communicate through Shared types. PokerCore never imports anything from the app.

## Consequences

- Rules are unit-tested with `swift test` in seconds and cannot regress differently on client and server.
- Adding a file to the app is enough to include it (file-system-synchronised groups). Adding a file to the package works the same way.
- The package reference is the only reason to touch `project.pbxproj`.
- Every new feature gets a folder, a test file and a decision record. There is no "misc" folder.
- CORE types must be `Sendable`; this is enforced by Swift 6 mode in the package.

## Alternatives considered

- **Folder inside the app target.** Simpler, but every type would need `nonisolated` and the server could not share the code.
- **Separate repository for the engine.** Cleaner versioning but slows down iteration while the rules are still being written. Can be split out later without changing imports.
- **Layered folders (Models/Views/ViewModels) instead of features.** Spreads one feature across three folders and makes it hard to see what a feature owns.

## Test strategy

- `Packages/PokerCore/Tests/PokerCoreTests/*` cover every CORE module using builders from `PokerCoreTestSupport`.
- `ForeverAlonePokerTests/` covers Shared and Features; it imports `PokerCoreTestSupport` rather than redefining fixtures.
- The architecture rule itself is checked by review: a `import SwiftUI` or `import Foundation` networking type inside `Packages/PokerCore/Sources/PokerCore` is a bug.
