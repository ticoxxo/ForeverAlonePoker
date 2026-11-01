# 0031. Show country flags on pictures at online tables

- **Status:** Accepted
- **Date:** 2026-10-31
- **Feature / area:** `ForeverAlonePoker/Features/Table`, `ForeverAlonePoker/Features/OnlineMatch`, `ForeverAlonePoker/Features/Profile`, `ForeverAlonePoker/Shared/Identity`

## Context

Every `PlayerSummary` already carries the player's `countryCode` (protocol version 2, tdr/0010), but the table never drew it. Over the internet, players meet strangers from anywhere, and the country is part of who they are playing. In a nearby match everyone is in the same room, so a flag says nothing.

The server copies `PlayerIdentity.countryCode` into the leaderboard entry (`RankingService`), so a player cannot stop sending it without dropping out of their country leaderboard.

## Decision

`PlayerAvatar` draws `CountryFlag.emoji(for:)` as an `.overlay(alignment: .bottomTrailing)` when the environment value `showsCountryFlags` is on. It defaults to off; only `OnlineMatchView` turns it on for its `TableView`, so nearby and practice tables never show flags. VoiceOver reads the country name as the picture's value.

Whether online tables show flags is a per-device viewer preference: `@AppStorage(CountryFlag.showsAtOnlineTablesKey)`, on by default, switched in Profile > Country ("Show flags online"). It changes only what this device draws; the country code still travels in the identity, so leaderboards are unaffected.

A blocked player shows no flag, like their name and picture (`PlayerSummary.shownCountryCode(hiding:)`, tdr/0029).

## Consequences

- Online seats, compact seats and the waiting zone all show flags through the one `PlayerAvatar`.
- The setting does not hide the player's own country from others. Doing that would need a protocol field and a server change so the leaderboard keeps the real country.
- Lobby rows (`LobbyPlayersSection`) still use `AvatarView` and show no flag.

## Alternatives considered

- **Blank `countryCode` in the identity when the switch is off.** Hides the player's flag from others, but the server would then file them under no country on the leaderboard.
- **Pass an `isOnline` flag through `TableView` into every seat.** More parameters through many layers; an environment value reaches every `PlayerAvatar` at once.

## Test strategy

`PlayerSafetyTests.shownCountry` checks that a blocked player's country is hidden. `IdentityStoreTests` already covers `CountryFlag.emoji(for:)`. That flags appear only at online tables, and the Profile switch, are verified manually.
