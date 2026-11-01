# 0030. Pick profile pictures from a bundled catalog instead of uploading photos

- **Status:** Accepted
- **Date:** 2026-10-31
- **Feature / area:** `Packages/SkinKit` (`CosmeticSlot.avatar`, `SkinCatalog.builtIn`), `Packages/PokerCore/Sources/PokerCore/Protocol`, `ForeverAlonePoker/Shared/Skins`, `ForeverAlonePoker/Shared/DesignSystem/AvatarView.swift`, `ForeverAlonePoker/Features/SkinStore`, `ForeverAlonePoker/Features/Profile`

## Context

How pictures worked before:
- Ranked players uploaded a photo. Their app wrote it to a `PublicProfile` record in the CloudKit public database (tdr/0010).
- Opponents fetched it through `AvatarLoader` (tdr/0013).

Why that has to change:
- **Unchecked pictures.** Any picture reached other players unchecked.
- **Legal duties.** Moderating uploads properly brings duties that differ by country: known-CSAM hash matching, NCMEC reports, evidence retention. That isn't worth it for a poker app (tdr/0029).
- **Pictures as a product.** Pictures are also something players would pay for, like card skins.

We have 14 pictures of our own: 8 to give away and 6 to sell.

## Decision

1. **No uploads.**
   - `PhotosPicker`, `AvatarImporter`, `PublicProfile` publishing, `AvatarLoader` and `CloudKitAvatarProvider` are removed.
   - `PlayerProfile.avatar` stays in the SwiftData model, unused, so existing stores and the CloudKit schema need no migration.
   - Clients write nothing to the public database.
2. **Pictures are a cosmetic kind** (tdr/0011): `CosmeticKind.avatar`, with one slot, `CosmeticSlot.avatar`.
   - `SkinCatalog.builtIn` lists all 14 pictures, each with English and Spanish names:
     - **Free:** `avatar_dwarf`, `avatar_goblin`, `avatar_eyepatch_bear`, `avatar_seal`, `avatar_dino`, `avatar_rabbit`, `avatar_pig`, `avatar_scarred_pup`.
     - **Premium**, sold one by one as non-consumables `fap.skin.<id>` (`ProductIDs.single`): `avatar_yellow_cat`, `avatar_zombie_cat`, `avatar_stitched_cat`, `avatar_cigs`, `avatar_wine`, `avatar_girl`.
   - None of them is `isDefault`. A player who picked nothing shows initials.
3. **All 14 are bundled, premium ones included.**
   - They're in `Assets.xcassets/Skins/skin-<id>-avatar`, 512 px PNG, about 3.8 MB in total, resized once from the artist's files with `sips -Z 512`.
   - `SkinItem.isBundled` marks them as always installed. Only the built-in catalog sets it; it's never read from JSON. `SkinResolver` honours a bundled pick once it's owned, and `SkinStore.syncAssets` never downloads bundled items.
   - Buying unlocks *choosing* a picture. Every viewer can always *draw* every picture.
4. **The picture travels with the join.**
   - `PlayerIdentity.avatarID` and `PlayerSummary.avatarID` are optional strings; `ProtocolVersion` is now 5.
   - `MatchRoom.join` keeps the ID (dropping one over 40 characters) and copies it to the summary.
   - The app sends `SkinStore.myAvatarID`, the resolved pick: free, or premium and owned.
   - Viewers draw an ID only when `BundledSkin.avatarImageName(for:)` finds it in their own built-in catalog. Otherwise they draw initials.
   - Blocked players always show initials (tdr/0029).
   - The server checks no ownership. A modified client could show a premium picture it didn't buy; only that player's App Store purchase is lost.
5. **Choosing a picture.**
   - Profile shows `AvatarPicker` (in `Shared/Skins`): the free pictures, the bought ones, and "No picture".
   - The store has a "Profile pictures" section with Use or Buy for each picture. Buying equips the picture, as for other skins.

## Consequences

- No user-uploaded images reach anyone, so there is no picture moderation, CSAM duty or `PublicProfile` record.
- Pictures work offline, in local play and for unranked players.
- Every picture adds to the app's size, and a new picture needs an app update. Pictures sold later still ship to everyone.
- Joins carry one more short string; old builds can't join new ones (protocol 5).
- The leaderboard shows initials: `LeaderboardEntry` has no picture field. A follow-up could add `avatarID` there, as a server write and a schema change.
- `avatar_cigs` and `avatar_wine` show tobacco and alcohol, which the App Store age rating has to declare.

**Operator duties:**
- Create the six non-consumables in App Store Connect with the product IDs above.
- Answer the age-rating questionnaire for alcohol and tobacco references.

## Alternatives considered

- **Keep uploads and moderate them** (OpenAI, PhotoDNA, NCMEC). Dropped for the legal duties per country (tdr/0029).
- **Download premium pictures from `/skins` like chips.** A smaller app, but an opponent would need to download a picture they don't own before seeing it, and local play would depend on the server.
- **Sell the premium pictures as one pack.** Selling one by one lets players buy just the picture they want.
- **Send the full loadout (`cosmetics`) with the join** (tdr/0012 decision 6). Cards and chips stay local for now; one optional field is enough for pictures.

## Test strategy

- **SkinKit** (`AvatarTests`):
  - the slot and kind;
  - 8 free and 6 premium built-in pictures with their product IDs;
  - bundled, never the default, and never bundled when decoded from a server catalog;
  - the resolver for no pick, a free pick, a premium pick bought or not, and an unknown ID.
- **PokerCore** (`AvatarWireTests`):
  - the identity round-trips with a picture, and decodes without one;
  - opponents see the seated picture;
  - an overlong ID is dropped.
  - `TestPlayers.bobWithAvatar`.
- **App:**
  - `SkinStoreAvatarTests`: offered by this build; no pick; free and bought picks need no download; an unbought premium pick isn't shown; clearing; image names for known and unknown IDs.
  - `IdentityStoreTests`: the identity carries the picture.
  - `PlayerSafetyTests`: a blocked player shows initials.
- **Manual,** with `StoreKit/SkinStore.storekit`:
  - pick a free picture in Profile and see it on Home and at the table;
  - buy a premium one and see it equipped;
  - two simulators see each other's pictures, including an unowned premium one.
