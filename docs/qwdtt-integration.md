# qWDTT integration in the native NYM Android client

Requested on 2026-11-03: add the working panchat qWDTT transport to NYM settings,
including subscription import, WG/Raw, local authenticated proxy, diagnostics,
VK login/hash generation, server administration and the existing encrypted
server protocol. Keep the NYM UI and messaging implementation.

## Architecture

Reuse the pinned panchat Go executable, native status parser, subscription
parser and authenticated SOCKS connector. Android owns the process, secrets and foreground lifetime. Dart owns a loopback
authenticated HTTP CONNECT adapter. Dart
HttpClient and WebSocket connections use that adapter from before account boot.
The adapter has explicit DIRECT, BLOCKED and QWDTT states. A selected stopped,
starting or failed tunnel is BLOCKED; only explicit selection of DIRECT can
create direct internet connections. Route changes close existing adapter
connections. Domain names are sent in SOCKS CONNECT without local DNS.

A pure Flutter UI rewrite of transport internals would duplicate reviewed code.
Embedding the whole old Compose application would duplicate account/region/Tor
lifecycle. Neither is required for this integration.

Native media plugins must use downloaded local files, or be blocked while
qWDTT is selected. WebRTC calls/file transfer and external authentication cannot
be declared proxied by merely changing HttpClient. They require explicit guards
until an enforced supported route exists. VK bootstrap is the transport's own
separate network client and is not routed into itself.

## Steps and acceptance

- [x] Install a SHA-256 verified Flutter SDK satisfying the upstream constraints;
  resolve dependencies and record the clean baseline build limitations.
- [x] Add Dart-tested loopback CONNECT/SOCKS gateway: remote DNS, authentication,
  route-change cancellation, bounded headers/timeouts/concurrency, no fallback.
- [x] Reuse native qWDTT/config/status code and ABI executables with corresponding
  source and licenses; encrypted profile storage and a foreground service.
- [x] Install Dart routing before foreground/background account boot. Test HTTPS
  and WebSocket through the adapter and failure while selected tunnel is down.
- [x] Add the settings entry and page: saved profiles, import/manual edit,
  WG/Raw, TURN/DTLS/DNS/MTU/timeouts, connect/disconnect, upstream-style pipeline,
  two-worker counters and bounded redacted diagnostic records.
- [x] Port the existing safe VK login/hash flow and SSH deploy/subscription tools.
- [x] Route native media through local files; guard WebRTC and native outbound
  authentication paths. Test every identified HTTP and socket creation path.
- [ ] Complete app tests, build and package verification. Physical-device/live
  egress tests use authorized synthetic data only and are reported separately.

Android 10+; Android Flutter ABIs arm64-v8a, armeabi-v7a and x86_64. Flutter no
longer targets Android x86 (32-bit). Native keys and protocol remain compatible
with the existing qWDTT server; no direct relay or DNS fallback is permitted.

This is a modified fork, Based on Nymchat by 21 Million LLC:
https://github.com/Spl0itable/NYM. Preserve LICENSE and NOTICE, add the required
attribution and modified-version notice to About, and retain GPL notices and
corresponding source for reused qWDTT/panchat components.

## Verification 2026-11-04

Android debug APK builds for all three supported ABIs. 32 JVM tests and 16
Flutter tests pass (including synthetic UI preview), as do two Android 10
instrumentation tests for Keystore/profile persistence and executing the
packaged core with an invalid configuration before any network requests.
Native qWDTT, server and admission Go suites pass. Live VK/VPS/NYM account and
physical GrapheneOS tests remain separate acceptance items; this is a test
build, not a production release. See BUILD-QWDTT.md for routing boundaries.

The single independent review and the fixed stale-snapshot race are recorded
in qwdtt-review-2026-11-04.md.
