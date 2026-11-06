# 0029. Filter names, let players block and report, and ask them to accept the guidelines

- **Status:** Accepted
- **Date:** 2026-10-31
- **Feature / area:** `Packages/PokerCore/Sources/PokerCore/Identity` (`DisplayNamePolicy`), `ForeverAlonePoker/Shared/Moderation`, `ForeverAlonePoker/Features/Table/PlayerSafety.swift`, `ForeverAlonePoker/Features/Profile`, `ForeverAlonePoker/Features/Onboarding`

## Context

Display names are free text that other players see. They show at every seat and in the lobby, they're written to the leaderboard, and they're advertised over Bonjour to nearby strangers before a passcode is entered (tdr/0007). Until now nothing was filtered, and players couldn't block or report anyone.

App Review Guideline 1.2 asks apps with user-generated content for four things:
- a way to filter objectionable material;
- a way to report it, with timely responses;
- a way to block abusive users;
- published contact information.

Reviewers also expect terms that say there is zero tolerance for objectionable content.

A first version of this record also moderated uploaded profile pictures: on the server with OpenAI and PhotoDNA, on the device with SensitiveContentAnalysis, with server-side reports and bans. That version was never released. Accepting uploaded pictures brings legal duties that differ by country: CSAM reporting to NCMEC, evidence retention, and more. That wasn't worth the effort, so players no longer upload pictures (tdr/0030). The only user-generated content left is the name.

Constraints:
- the app targets iOS 17;
- CORE imports no Foundation;
- the server has no database (tdr/0003).

## Decision

1. **Every name passes `DisplayNamePolicy` (CORE) wherever it's shown.** The policy uses only the standard library.
   - **Normalizing:** strips control, format (zero-width, bidi override), private-use and unassigned characters, and collapses whitespace.
   - **Rules:** 2 to 20 characters, at least one letter or digit, and a short English/Spanish blocklist.
   - **Disguises:** the blocklist is checked after folding case, fullwidth forms, Latin accents and leetspeak, and stretched letters ("fuuuck") are caught.
   - **Two kinds of entries:** `roots` match anywhere; `words` match only whole words (the Scunthorpe problem).
   - **Where it's applied:**
     - `MatchRoom.join` seats a rejected name as "Player N" and drops a country code that isn't two letters. This covers local hosts and the server alike, with no protocol change.
     - The server's `Room` gives the leaderboard the name as seated.
     - The Bonjour service name is the filtered name.
     - The Profile screen explains a rejected name instead of saving it (`ProfileSafetyModel`).
2. **Block and Report are on every other player's seat:** as a context menu and as VoiceOver actions, at the table, in the waiting zone and at compact seats. They're off in practice against the computer.
   - **Blocking is local.** It's a SwiftData `BlockedPlayer` synced through the private iCloud database (`BlockList`).
     - A blocked player's name reads "Blocked player".
     - Their picture shows initials.
     - Their emotes are muted.
     - A banner says they're at the table and offers Leave.
     - Profile lists blocked players, with Unblock.
   - **Reporting is an email to support.** It goes through `SupportContact.mailURL(.report(playerID:name:roomCode:))`, with the player's name, ID and room filled in. We review reports within 24 hours.
3. **Terms and contact.**
   - The community guidelines include a zero-tolerance clause. They must be accepted once per `CommunityGuidelines.version`, on a full-screen cover at launch (`TermsView`).
   - Profile has a Safety and support section: blocked players, the guidelines, and the support email.

## Consequences

- Names are filtered on the device and by every host, with no third-party service and no server state.
- The blocklist is a floor. People review reports and act on them: we can rename or remove a ranked player's leaderboard entry. There are no automatic bans.
- Unranked players use local UUIDs, so a report can't follow them to a new install. Blocking still works.
- Nothing a player uploads reaches anyone else, which keeps the legal scope small.

**Operator duties:** read the support mailbox and act on reports within 24 hours.

## Alternatives considered

- **Moderate uploaded pictures on the server.** This means OpenAI for pictures and text, PhotoDNA for known CSAM, and server reports and bans. It was built and then dropped before release, because of the legal duties per country. tdr/0030 replaces uploads with a catalog.
- **A remote text check (OpenAI) on names.** It adds a dependency and a key for little gain, now that names are the only user content. The local policy catches the obvious cases, and people review reports.
- **Reports sent to the server.** That needs server-only CloudKit record types and a review tool. Email to support meets Guideline 1.2 with nothing to run.
- **Server-side blocking (never seating blocked players together).** It needs the block list on the server and gets in the way of private rooms. Left as a follow-up for open-table search (tdr/0021).

## Test strategy

- **PokerCore:**
  - `DisplayNamePolicyTests`: normalizing, lengths, the blocklist with disguises, and the Scunthorpe cases.
  - `MatchRoomNameModerationTests`: a rejected name is seated as Player N, a name is normalized, a country code is dropped. Uses `TestPlayers.offensive` and `TestPlayers.paddedBob`.
- **Server:** `RankedTests` ("the leaderboard gets the name as seated").
- **App:** `PlayerSafetyTests`:
  - `BlockList` persistence;
  - the hidden name and picture;
  - `ProfileSafetyModel`;
  - the report email's subject and body.
- **Manual:**
  - the guidelines cover on first launch;
  - the seat menu, Block and the banner at a real table;
  - Report opens Mail.

## Notes

- **2026-11-05:** Report at the table now checks whether Mail opened. When the device has no mail account, an alert gives the support address and copies the report details, so reporting works on every device (App Review tests on devices without Mail).
