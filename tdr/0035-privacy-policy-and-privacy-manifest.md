# 0035. Serve the privacy policy from the game server and ship a privacy manifest

- **Status:** Accepted
- **Date:** 2026-11-05
- **Feature / area:** `Server/Sources/PokerServerCore/PrivacyPolicy.swift` (`GET /privacy`), `ForeverAlonePoker/PrivacyInfo.xcprivacy`, `ForeverAlonePoker/Shared/Skins/SupportContact.swift`, Profile and the community guidelines

## Context

App Review Guideline 5.1.1(i) requires a privacy policy linked in App Store Connect and easy to reach in the app. App Store Connect also rejects uploads that use "required reason" APIs without a privacy manifest; the app uses `UserDefaults` / `@AppStorage`. The project has no website.

## Decision

The game server serves the policy as HTML at `/privacy` (`https://forever-alone-poker.fly.dev/privacy`, `SupportContact.privacyPolicy`). The text is a Swift string in `PrivacyPolicy`, so the Docker image needs no extra files. The app links it from Profile ("Safety and support") and from the community guidelines, which every player sees before playing (tdr/0029).

`PrivacyInfo.xcprivacy` in the app target declares no tracking, `UserDefaults` with reason `CA92.1`, and two collected data types, both linked and for app functionality: User ID (Sign in with Apple subject and display name on the leaderboard) and Gameplay Content (rating and record). Nothing else leaves the device to us: the private iCloud database is the player's, purchases are checked on the device, and reports are emails the player sends.

The policy, the manifest and the App Store privacy label must stay in step. Change all three together.

## Consequences

- The policy URL works only after the server is deployed with this route.
- Policy changes ship with a server deploy, not an app update.
- A new third-party SDK, analytics or a new server-side store means updating the manifest, the policy and the label.

## Alternatives considered

- **A separate static site (GitHub Pages).** Another thing to host; the server is already public.
- **Policy only inside the app.** App Store Connect needs a URL.

## Test strategy

- `Server/Tests/PokerServerTests/AccountDeletionTests.swift` (`PrivacyPolicyRouteTests`): `/privacy` answers HTML that explains account deletion.
- Manual: `plutil -lint` on the manifest, and Xcode's privacy report (Product > Archive > Generate Privacy Report) before submission.

## Notes

- **2026-11-06:** The policy promises that server logs carry no IP address, name or game content and are kept 7 days (Fly.io log search retention). At `info` level the server logs only startup, rejected tokens and failures, none with player data; `LogRequestsMiddleware` runs at `debug`. Keep it that way, or update the policy with the change.
