# 0002. Build every feature test-first with shared object builders

- **Status:** Accepted
- **Date:** 2026-10-07
- **Feature / area:** all test targets

## Context

The rules of poker have many edge cases (short blinds, all-in for less, chops, the big-blind option) that are expensive to find by playing. We want every feature to arrive with tests, and we do not want each test target to re-invent card fixtures or scripted hands.

## Decision

1. **Red, green, refactor for every step.** A feature begins with a failing Swift Testing test that states the behaviour; then the minimum implementation; then cleanup. Tests are named as behaviours ("big blind keeps the option after a limp"), one scenario per test.

2. **Builders live in one place: `PokerCoreTestSupport`.** It is a regular library target in the `PokerCore` package (not a test target) so that `PokerCoreTests`, `ForeverAlonePokerTests` and the server's tests can all import it. Nothing in it is duplicated elsewhere. Current builders:
   - `cards("As Kd")`, `card("As")`, `Deck.rigged(...)` for cards.
   - `HandStateBuilder` for a started hand with chosen stacks, blinds, button, hole cards and board; `HandEngine.play(state, script)` for scripted action sequences.
   - `MatchStateBuilder`, `MatchRoomBuilder`, `TestPlayers` and `[Outbound]` helpers (`latestView(for:)`, `events(for:)`, `rejections(for:)`) for match and room tests.
   App-side builders (persistence, transports) will be added to the app test target only when they depend on app-only frameworks; anything expressible with PokerCore types goes in `PokerCoreTestSupport`.

3. **Determinism over mocking.** The engine takes a pre-shuffled `Deck`, and `MatchRoom` takes a deck provider, so tests rig outcomes instead of mocking random numbers. `SeededRandomNumberGenerator` exists in CORE for reproducible shuffles.

4. **Frameworks.** Unit tests use Swift Testing (`@Test`, `#expect`, `#require`). UI tests use XCTest/XCUIApplication and stay minimal (smoke only).

## Consequences

- Builders are production-quality code: they are public, documented and compiled in Swift 6 mode.
- A change to a CORE type that breaks a builder breaks every test target at once, which is the intended early warning.
- Tests read like hand histories; new contributors can learn the rules from them.

## Alternatives considered

- **Builders duplicated per test target.** Violates the "no repeated test code" requirement and drifts over time.
- **Protocol-based mocks for the deck and RNG.** More ceremony than injecting a value; rigged decks are clearer.
- **XCTest everywhere.** Swift Testing has parameterised tests and better failure messages for value types; the project already uses it.

## Test strategy

This record is validated by the existence of `Packages/PokerCore/Sources/PokerCoreTestSupport` and by the absence of fixture code in `Tests/`. `swift test --package-path Packages/PokerCore` must stay green at every step.
