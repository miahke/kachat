# Independent qWDTT integration review — 2026-11-04

One read-only GPT-6 Astra pass reviewed the Dart CONNECT/SOCKS gateway,
controller, Android process/lifecycle/profile storage, native media routing,
WebRTC guards, VK login and SSH deployment/administration paths. No real
accounts, phones, credentials or servers were inspected.

## Finding and resolution

P1: a delayed snapshot reporting DIRECT could overwrite a subsequently completed
qWDTT selection. Checking `busy` at response time did not establish that the
response belonged to the current command sequence. The native calls execute in
separate IO coroutines, so completion order cannot be assumed.

The controller now increments a local revision before every command. Both
initialization and periodic polling capture that revision and discard stale
results and errors. A synthetic delayed DIRECT response reproduced the issue
before the fix (selected became false); the same test passes after the fix.
A second regression verifies that an old failed poll cannot overwrite an
explicit selection of DIRECT.

The reviewer reported no other confidently established critical/important
findings in the examined scope. This is a code review, not a penetration test
or a guarantee of security. Fix validation was performed by the implementing
agent; no second independent pass was requested or claimed.

## Validation

- 16 Flutter tests pass, including HTTPS/WSS/TLS/SOCKS, route changes, stale
  snapshots, UI import/connect/delete and SSH fingerprint confirmation.
- 32 JVM tests pass for native protocol/status, subscription, VK and deployment.
- Two Android 10 instrumentation tests pass on a clean synthetic emulator:
  Keystore/profile persistence and executing the packaged qWDTT core with an
  invalid configuration rejected before networking.
- Go client, server and admission suites pass.
- Android debug APK builds for arm64-v8a, armeabi-v7a and x86_64, with API29 floor.
- APK signature and packaged native SHA256 hashes are verified.

Live VK/VPS/NYM message exchange and physical GrapheneOS testing of this fork
remain unverified. WebRTC calls/P2P are deliberately unavailable while qWDTT
is selected. Upstream NYM storage/backend behavior remains unchanged.
