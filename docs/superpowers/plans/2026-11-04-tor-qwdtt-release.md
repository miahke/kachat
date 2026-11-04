# Tor and qWDTT integration release plan

> **For agentic workers:** use subagent-driven-development for the isolated native Tor, VK captcha and qWDTT settings tasks; root integrates shared routing, validates and publishes.

**Goal:** Add functioning Tor obfs4/WebTunnel/Snowflake, real bootstrap percentages, applicable original qWDTT settings and manual VK captcha handling, then publish APKs.

**Architecture:** One persistent selected route (DIRECT/VK/TOR); unavailable protected routes remain blocked. Existing authenticated Dart CONNECT gateway and remote SOCKS DNS carry messenger HTTPS/WSS/media unchanged. Tor reuses the panchat Arti and PT cores with source/binaries rebuilt for Snowflake. VK manual challenges travel through a bounded native pipe and an official-domain in-app popup.

**Tech stack:** Flutter/Dart, Kotlin/coroutines/Android Keystore, Rust Arti JNI, Go pluggable transports/qWDTT.

**Spec:** User request in this chat, 2026-11-04; the preceding Russian localization patch is included.

## Constraints and review focus

- Android API29+, arm64-v8a/armeabi-v7a/x86_64; no system VpnService or downloaded executables.
- Persist selected protected route before teardown; never silently revert to direct on failure, restart, cancelled captcha or stale RPC.
- No passwords, bridges, room keys, captcha URLs/tokens or raw native logs in diagnostics/source history.
- Display 100% only after genuine Tor bootstrap readiness; show endpoint reachability separately.
- User solves official VK challenges; cancellation, expiry, logout and process replacement must reject stale answers.
- qWDTT settings must map to actual core options; system-wide VPN-only options remain explicitly excluded, workers stay at two.
- Preserve user identities, messaging protocols, stock compatibility, original attribution and AGPL/component licensing.

## Tasks

- [x] Native Tor module: import/rebuild actual Arti/PT sources, validate bridges and Snowflake, expose authenticated endpoint + sanitized progress, unit checks.
- [x] VK captcha: hash and TURN paths, official HTTPS popup, correlated bounded retry/expiry/cancellation, synthetic tests, rebuild qWDTT cores.
- [x] qWDTT settings parity: original source audit, field validation/mapping, complete import/export, clearer status and parity report.
- [x] Root: serialized shared engine lifecycle + route persistence/migration, Tor page/network chooser, controller route guarding, foreground captcha prompt and optional HTTPS probe.
- [x] Validate: Flutter tests/analyze, JVM/Go checks, native ABI/checksum/packaging, synthetic route switch and restart tests; live tests only when an isolated runtime is available.
- [x] Release preparation: bump version, clean neutral-path AOT build, private test signing, secret scan and verified APK/checksum artifacts.
- Publication is the final action after committing these verified sources; release notes retain the live-test limitations.
