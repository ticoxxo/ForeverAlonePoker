# 0004. Drive the table UI from a single observable session client

- **Status:** Accepted
- **Date:** 2026-10-07
- **Feature / area:** `ForeverAlonePoker/Shared/Session`, `ForeverAlonePoker/Shared/Transport`, `ForeverAlonePoker/Features/Table`, `ForeverAlonePoker/Shared/DesignSystem`

## Context

The table is the one screen both play modes share. It must render whatever the authority says, offer exactly the legal actions, and never contain poker rules or transport code (tdr/0003). The project's SwiftUI guidance asks for `@Observable` models with `Equatable` properties, separate `View` structs per section with narrow inputs, and no Combine.

## Decision

1. **`MatchSessionClient` is the only thing views talk to.** It is `@Observable` (main-actor by the app target's default isolation), owns a `MatchTransport`, consumes `ServerMessage`s in a background `Task`, and exposes `view: PlayerView?`, `connection`, `events`, `lastRejection`, `opponentLeft` plus async action methods (`ready`, `fold`, `check`, `call`, `bet`, `raise(to:)`, `allIn`). All exposed types are `Equatable`, so redundant updates do not invalidate views.

2. **`MatchTransport` is a `nonisolated protocol`** with `incoming: AsyncStream<ServerMessage>`, `send`, `close`. `InMemoryTable`/`InMemoryTransport` is the in-process implementation that routes through a `MatchAuthority`; it serves tests, previews, and the Multipeer host's own seat.

3. **Presentation logic is pure and tested.** `TableActionModel` (buttons and slider range from `LegalActions`), `TableStatus` (what to tell the player) and `HandOutcome` (last-hand summary) are `nonisolated` value types in `Features/Table/TableModels.swift` with unit tests. Views only format them.

4. **Views are sectioned.** `TableView` composes `OpponentSeatView`, `BoardView`, `StatusBanner`, `MySeatView`, `ActionBar`; card rendering lives in `Shared/DesignSystem/CardViews.swift`. Each takes only the fields it renders.

5. **Debug-only practice table.** `AutoCallingOpponent` and `PracticeSession` (under `#if DEBUG`) seat an opponent that readies and checks/calls, so the table can be played in previews and in the app before local and online play exist. `ContentView` shows it until the Home feature replaces it. It is not a bot feature and is not compiled into release builds.

## Consequences

- Adding a transport (Multipeer, WebSocket) requires zero changes to the table.
- The client tracks `view` as one struct, so any state message re-renders the table; acceptable because a state message always reflects a real change.
- Test target has no default actor isolation: anything touching the client in tests is marked `@MainActor`, and async assertions use `eventually { }` instead of fixed sleeps.

## Alternatives considered

- **Views reading `MatchRoom`/`HandState` directly.** Would put unredacted state on the client and couple UI to engine internals.
- **One view model per screen section.** Unnecessary; per-property observation on a single client already scopes invalidation.
- **Pass-and-play mode for development.** Rejected by the user; the debug auto-caller serves the development need without becoming a product feature.

## Test strategy

- `MatchSessionClientTests` and `InMemoryTransportTests` (ForeverAlonePokerTests/Shared) play scripted hands through two clients.
- `TableModelsTests` cover action model, status mapping and outcome text inputs.
- Visual check: `TableView` and `ActionBar` previews, and running the app (practice table) on a simulator.
