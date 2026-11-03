# 0032. Keep the server address a debug setting and host the server on Fly.io

- **Status:** Accepted
- **Date:** 2026-11-03
- **Feature / area:** `ForeverAlonePoker/Features/Profile`, `ForeverAlonePoker/Shared/Identity`, `ForeverAlonePoker/Features/OnlineMatch`, `fly.toml`

## Context

tdr/0008 put the server address on `PlayerProfile.serverURLOverride`, edited in Profile, with `http://127.0.0.1:8080` as the default. That suited development, but TestFlight and App Store players saw a "Game server" field they should never touch, and a release build had no real server to reach.

`PlayerProfile` syncs through CloudKit, so an address typed on a development device reaches every install signed in to the same iCloud account.

The server keeps rooms in memory (`RoomRegistry`): every player at a table must reach the same process, and a restarted or stopped machine drops its tables.

## Decision

The "Game server" section in `ProfileView` exists only in `DEBUG` builds, and `IdentityStore.serverURL` honours `serverURLOverride` only in `DEBUG`. Release builds always use `HTTPRoomService.defaultBaseURL`, which is the local server in debug and `https://forever-alone-poker.fly.dev` in release (`https` becomes `wss` for the match socket). The model property stays, so the schema does not change.

The server runs on Fly.io from `Server/Dockerfile`, configured by `fly.toml` at the repo root (the build needs `Packages/` beside `Server/`; `.dockerignore` keeps the context to those two). One machine in one region, never auto-stopped, health-checked on `GET /health`. Secrets go through `fly secrets set`.

## Consequences

- Testers and players can no longer point the app at another server; developers still can from a debug build.
- A stale override synced from a debug device is ignored by release builds.
- One region serves the world. Poker is turn-based, so the extra latency is acceptable for now.
- Scaling to several machines or regions needs room-to-machine routing first. Follow-up: encode the machine or region in the room code and answer requests for a room on another machine with Fly's `fly-replay` header.
- A deploy restarts the machine and drops tables in play (unchanged from tdr/0008: no server persistence).

## Alternatives considered

- **Per-configuration build setting read from Info.plist.** Needs `project.pbxproj` edits, which the project avoids; `#if DEBUG` matches the other debug-only switches (`CatalogTrust.fromBundle`, `TransactionCertificateValidator`).
- **A plain VPS (Hetzner, DigitalOcean) behind Caddy.** Cheapest for one region, but no path to multiple regions with room routing.
- **Serverless containers (Cloud Run, App Runner).** Scale to zero and short-lived or no WebSockets break in-memory rooms.

## Test strategy

Unit tests run in debug, so the override behaviour they cover is unchanged. Release behaviour is verified by building the Release configuration (the field and override code compile out) and by playing online from a TestFlight build against the Fly app.
