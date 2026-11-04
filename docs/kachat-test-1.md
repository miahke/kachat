# kachat test 1 — 2026-11-04

Android-only modified NYM client with qWDTT. Based on Nymchat by 21 Million LLC,
https://github.com/Spl0itable/NYM (ead1401c81160043f0f8770d7d7fe3fa17601ca0).
License: AGPL-3.0; original notices and component licenses retained.

## Scope

- kachat branding, photo-to-glyph adaptive/monochrome icon, color-named themes.
- No outgoing payments, shop or invoice execution; localized inert notices.
- qWDTT WG / authenticated Raw v2, profiles, VK call hashes, routing diagnostics,
  SSH deployment and access subscriptions. Access subscriptions are not payments.
- One GPT-6 Astra performance review; bounded render groups/caches, deduplicated
  media downloads and sanitized qWDTT metadata caching. No measured claim about
  Pixel frame times or battery use.

## Checks

- Prepared publication tree: Flutter analyze clean; 26 regression tests pass,
  one optional preview skipped. Android/JVM suite: 34 pass in the working tree.
- Native qWDTT hashes match the recorded source distribution manifest for all
  three ABIs.
- Gitleaks 8.30.1 source scan: three findings manually triaged: upstream public
  Giphy application key, upstream public VK application client credential, and
  a nonsecret local-storage key name. None are personal access credentials.
- The unpacked bundled server deployer: no Gitleaks findings. A separate scan
  found none of the previously supplied test-server credentials or local
  personal filesystem paths in the prepared source/archive. These checks do
  not establish the absence of every possible secret or vulnerability.

## Artifact status

APKs use Release/AOT, with the existing local test certificate for update
compatibility. No signing key is distributed. ApplicationId remains
com.panchat.nym; Android API 29+, arm64-v8a / armeabi-v7a / x86_64.
Use arm64-v8a for Pixel 6/7 Pro. Published artifacts are a prerelease for tests.
Physical Pixel validation of this patch is pending. Native FCM is not configured;
WebRTC/P2P is unavailable while qWDTT is selected. Upstream NYM backend service
usage/storage has not been replaced by this fork.

The source repository starts with a fresh, attributed snapshot; local working
history, personal keys/configuration, build caches and the upstream web payment
frontend are excluded. SHA256SUMS accompanies the release artifacts.
