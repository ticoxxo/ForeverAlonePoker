# 0009. Rate ranked matches with Elo computed in CORE

- **Status:** Accepted
- **Date:** 2026-10-07
- **Feature / area:** `Packages/PokerCore/Sources/PokerCore/Rating`

## Context

World and country rankings (tdr/0006) need a rating. The server publishes it after each ranked online match and the app may preview it, so both must compute identical numbers. CORE imports nothing beyond the Swift standard library, which has no `pow` or `exp`.

## Decision

- **Elo**, starting at 1200. K-factor 40 for the first 10 ranked matches ("provisional"), 24 afterwards. Draws score 0.5 (heads-up matches end on a bust, so draws are theoretical, but the math stays total).
- `Rating` (value + matches played), `MatchOutcome`, and `EloCalculator.update(player:opponent:outcome:)` live in `PokerCore/Rating/`. Deltas are rounded to the nearest point away from zero.
- `exp` and `10^x` are implemented in CORE with range reduction and a short Taylor series; accuracy is far below one rating point and the implementation is unit-tested against known values. This keeps the package free of Foundation and platform math libraries.
- Only online matches refereed by the server are rated (tdr/0003, tdr/0006). Local and practice matches never touch ratings.

## Consequences

- Client and server agree bit-for-bit because they run the same code on the same integer inputs.
- Glicko-2 or per-country adjustments can replace this later behind the same `update` signature; a new record would document the change and ratings would be recomputed server-side.
- Match history on device stores the outcome, not the rating; ratings live in the CloudKit public database written by the server (tdr/0006 tier 2).

## Alternatives considered

- **Glicko-2.** Better uncertainty modelling but far more state per player; premature for a 1v1 game with no players yet.
- **`import Foundation` for `pow`.** Would work on Linux too, but breaks the "standard library only" rule for a ten-line function.

## Test strategy

`RatingTests` in `PokerCoreTests`: expected score bounds and symmetry, math helper accuracy, half-K exchange between equals, provisional vs established K, upset pays more than a routine win, loss mirrors win, draw between equals is neutral, conservation with equal K, `Comparable`.
