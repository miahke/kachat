# kachat Android with qWDTT

Modified 2026-11-03. Based on Nymchat by 21 Million LLC:
https://github.com/Spl0itable/NYM (base ead1401c81160043f0f8770d7d7fe3fa17601ca0).
The Flutter messenger UI and its backend APIs remain upstream NYM. This change
adds Android qWDTT transport settings; it does not replace NYM server storage or
change the Nostr message encryption formats.

## Build

Use Flutter 3.47.9 / Dart 3.13.7, JDK 17, Android SDK 36, NDK 28.2.13676358,
Gradle 8.14.3 / AGP 8.13.2 from the wrapper. Android 10 (API29) is the floor.

```sh
cd flutter
flutter pub get
flutter test test/qwdtt
flutter build apk --debug --split-per-abi --target-platform android-arm,android-arm64,android-x64
```

Configure Flutter's JDK with `flutter config --jdk-dir /path/to/jdk17` if another
JDK is selected automatically. Release signing remains configured via an
untracked `android/key.properties` or `NYM_KEY_PROPERTIES`; never commit keys.
This fork uses `com.panchat.nym` and installs beside stock NYM and old panchat.

The prebuilt qWDTT executables include this fork’s manual captcha changes;
SHA256 hashes are in `third_party/panchat-qwdtt/native-sha256.json` and sources
in `native/qwdtt`. To rebuild with Go 1.27.3 and Android NDK r27d:

```sh
ANDROID_NDK_HOME=/path/to/android-ndk-r27d tools/build-qwdtt.sh arm64-v8a
ANDROID_NDK_HOME=/path/to/android-ndk-r27d tools/build-qwdtt.sh armeabi-v7a
ANDROID_NDK_HOME=/path/to/android-ndk-r27d tools/build-qwdtt.sh x86_64
```

Native libraries are extracted so the embedded PIE executable can be launched.
No executable code is downloaded by the client. Server kit binaries, scripts,
checksums and corresponding sources are bundled in
`flutter/android/app/src/main/assets/network/panchan-deployer.zip`.

## User flow

Open Settings → Tor and qWDTT → qWDTT → paste a `qwdtt://config?...` subscription, or create a
manual profile with a VPS and server password. Ready call hashes do not require
VK login. Optional official VK login obtains a transport-scoped token for
creating call hashes. Connect selects qWDTT persistently. Stop keeps the route
blocked; direct internet access requires the separate explicit Direct action.
The local SOCKS listener uses loopback and generated password authentication.

WG / authenticated Raw v2, two workers, automatic DTLS/RTP AEAD selection,
TURN TCP/UDP, ports, DNS, MTU, keepalive and timeouts use the existing core.
Readiness comes from the actual core protocol, not from launching the process.
Diagnostics expose only whitelisted stages and counters, never raw core logs.

Server and subscriptions opens explicit SSH administration. Deployment supports
Debian x86_64, root or passwordless sudo. The server key is probed before any
password/key authentication and must be compared with the VPS console. SSH
credentials are held only in the open page. Installation changes the VPS's
services and routing only after the separate Install confirmation. Existing
subscriptions can be listed, created, activated, deactivated, deleted, copied
or imported locally. qWDTT server protocol remains compatible with panchat.3.

## Routing boundaries

Dart HTTPS/WSS clients use an authenticated loopback CONNECT adapter installed
before account boot. TLS certificates are still checked end to end. SOCKS
receives relay/media DNS names without local destination DNS. Route changes
close existing adapter sockets. Selected unavailable qWDTT fails closed.

Native media players receive files downloaded by that routed Dart client.
WebRTC calls and P2P are unavailable while qWDTT is selected, and existing peer
connections are closed on selection. Google/Apple native cloud-account login
and platform attestation are not silently treated as proxied. Native FCM is
not configured in this build. These controls are app-local, not a system VPN.
External browsers/apps opened by the user retain their own network routes.
Transport bootstrap (VK/TURN) and explicit SSH administration use independent
connections; they cannot recurse into their own proxy.

A new APK requires live validation on a synthetic account before use with real
messages. Unit/loopback tests do not prove an active VK TURN allocation, VPS
reachability, GrapheneOS background behavior or physical-device battery usage.

## kachat test release 1

The published test APKs use Flutter Release (AOT), not Debug mode. They retain
the existing applicationId `com.panchat.nym` and local test signing certificate
for update compatibility. Signing keys are not published. These are prerelease
test artifacts; production signing and physical-device validation remain
separate. For Pixel 6/7 Pro use the arm64-v8a APK.

To make your own Release APK, provide your own untracked key.properties as
described above, then run:

```sh
cd flutter
flutter build apk --release --obfuscate --split-debug-info=/path/to/private-symbols --split-per-abi --target-platform android-arm,android-arm64,android-x64
```

A new source-only repository starts with this modified snapshot. The original
upstream revision and attribution are recorded above and in NOTICE. The
original NYM web payment frontend is not part of this Android distribution.

Keep the generated symbol files locally for crash symbolication. They are not
release assets and can contain development paths. Packaging uses split debug
information to keep those paths out of the distributed Dart AOT libraries.

For published artifacts, build from a neutral checkout path such as
`/var/tmp/kachat-build-src/flutter`: Flutter can embed the generated plugin
registrant URI even with split debug info. The test release is built there
and scanned for local personal paths after packaging.

## Tor and test release 2

See `third_party/tor/README.md` for pinned Arti/PT sources and rebuilding all three ABIs. Native checksums are in `third_party/tor/SHA256SUMS`; run `tools/arti-build/verify-checksums.sh` from the repository root. Tor and qWDTT share one persistent route selector. Snowflake has a built-in public configuration; obfs4 and WebTunnel require the user’s bridge lines. No destination DNS is sent outside the selected SOCKS route. VK/TURN/Tor bootstrap, official login/captcha and explicit SSH remain independent service connections.

Upstream qWDTT subscription `port` is the local SOCKS port; a remote port belongs in `peer=host:port` (default 56000). Re-import old subscriptions if the old importer misinterpreted this field; existing deliberately configured server ports are not silently rewritten. See `docs/qwdtt-settings-parity.md`.
