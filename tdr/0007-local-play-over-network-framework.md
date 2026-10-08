# 0007. Use Network.framework with a passcode-derived TLS key for local play

- **Status:** Accepted (supersedes 0005)
- **Date:** 2026-10-07
- **Feature / area:** `ForeverAlonePoker/Shared/Transport/Nearby`, `ForeverAlonePoker/Features/LocalMatch`

## Context

0005 implemented local play with MultipeerConnectivity. Building against the iOS 27 SDK flags every MultipeerConnectivity type as **deprecated in iOS 27 ("Use Network Framework instead")**. Our deployment target is iOS 27, so the feature would have been born on a deprecated stack. Thanks to the `PeerLink` boundary from 0005, only the two radio adapters and the lobby's discovery flow were affected.

## Decision

1. **Network.framework replaces MultipeerConnectivity.** `NearbyDiscovery` advertises with `NWListener` + `NWListener.Service` (Bonjour type `_fapoker._tcp`) and browses with `NWBrowser`; `NearbyLink` implements `PeerLink` over `NWConnection`. `includePeerToPeer = true` keeps direct Wi-Fi working without a router.

2. **Passcode-based TLS-PSK.** The host shows a 4-digit passcode; the guest enters it after picking the host. Both derive the same 256-bit pre-shared key (`PasscodeKey`, HMAC-SHA256 with a fixed app salt) and open TLS with `TLS_PSK_WITH_AES_128_GCM_SHA256`. This restores the encryption MultipeerConnectivity provided and also stops strangers on the same network from taking the seat: a wrong passcode fails the handshake and the host keeps waiting.

3. **Length-prefixed framing.** TCP is a byte stream, so `LengthPrefixedFraming` adds a 4-byte big-endian length per message with a 1 MiB cap. It is a pure value and unit-tested; the link only feeds bytes into it.

4. **Lobby flow:** idle → hosting(passcode) / browsing → passcodeEntry(peer) → connecting → connected, with `failed(reason)` from any step. Host auto-accepts the first guest whose handshake succeeds and turns later connections away.

5. **Info.plist** keeps `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_fapoker._tcp`).

## Consequences

- No deprecated API in the local-play path; Bluetooth-only transport is no longer available (Network.framework peer-to-peer uses Wi-Fi), which matches Apple's direction.
- One extra step for the guest (typing four digits) in exchange for encryption and seat protection.
- The protocol layer (`WireCodec`, `PeerLinkTransport`, `RemoteGuestBridge`, `HostedTable`) and all their tests were untouched, which is the payoff of the `PeerLink` abstraction.
- Wi-Fi Aware (`WASharedSecret`) could replace the typed passcode with proximity pairing later; not pursued now.

## Alternatives considered

- **Stay on MultipeerConnectivity.** Works today, but deprecated on our minimum OS; every build emits dozens of warnings and the API may disappear.
- **Network.framework without TLS.** Hole cards would cross the Wi-Fi in clear text and anyone could join; rejected.
- **TLS with certificates.** No identity infrastructure exists for a local game; PSK from a passcode is Apple's documented pattern for this case.

## Test strategy

- `LengthPrefixedFramingTests`: framing layout, reassembly across arbitrary chunk boundaries, empty payload, oversize rejection.
- `PasscodeKeyTests`: deterministic derivation, distinct passcodes, passcode format.
- `PeerLinkTransportTests` (unchanged) cover everything above the link with `FakePeerLink`.
- `NearbyDiscovery`, `NearbyLink` and `LocalLobbyModel` are verified manually on two physical devices: host sees passcode, guest finds host, wrong passcode fails cleanly, right passcode seats both players, a full hand plays.
  - **Done 2026-10-08.** Passed on two iPhones over Wi-Fi. The only defect found was visual, not transport: `CardView` drew black suits with `.primary`, which is white in dark mode, so spades and clubs looked blank on the white card face. Fixed by pinning the ink colour and forcing a light colour scheme on the card; confirmed on-device.
