# kachat

An independent Android client based on Nymchat, with an integrated qWDTT
transport, built-in Tor, external proxies and local chat organization.

**Based on Nymchat by 21 Million LLC** — https://github.com/Spl0itable/NYM.
This is a modified fork, not an official NYM release. Original notices and
AGPL-3.0 terms are retained in [LICENSE](LICENSE) and [NOTICE](NOTICE).
The reused qWDTT/panchat components retain their own GPL/AGPL notices and
corresponding sources under `native`, `server` and `third_party`.

## Android client

- Android 10+; arm64-v8a, armeabi-v7a and x86_64.
- Existing NYM messaging, media, groups, identity formats and encryption.
- qWDTT profiles/import, WG or authenticated Raw, selectable transport workers,
  local authenticated SOCKS, VK call hashes, diagnostics and SSH deployment.
- Built-in Tor with user-supplied obfs4/WebTunnel bridges and Snowflake,
  actual bootstrap percentages and an authenticated loopback SOCKS listener.
- Explicit persistent route selection: unavailable Tor/qWDTT blocks chat traffic.
  Direct mode is a separate action. WebRTC/P2P cannot silently bypass either route.
- Manual VK image/smart captcha popup for call hashes and TURN credentials;
  applicable qWDTT network settings with full import/export.
- Reviewed offline Russian UI, native notifications and localized controls.
- Store and payment functions are available at the bottom of Information (i),
  behind fresh safety confirmations. Inline chat payloads direct users there.
- HTTP/HTTPS CONNECT and SOCKS5 proxies; standard URI/plain-address and
  Telegram SOCKS imports. MTProto/Shadowsocks are distinct unsupported protocols.
- Local per-account archive for chats/groups/channels, with hide/show controls.
- Six color-named themes and a photo-to-glyph adaptive launcher icon with a
  monochrome layer for launchers supporting themed icons.

Review the recipient, invoice and amount independently: payments can be
irreversible; the app cannot guarantee a counterparty or refund. Ordinary
discussion of money remains ordinary chat. Opening an external browser/app uses that app's own network and behavior.

## Backend scope

The client still uses upstream NYM backend APIs; this patch does not replace
NYM server-side storage or claim a fully self-hosted messaging backend.
The included Debian x86_64 deployer installs **the qWDTT tunnel server and
access administration**, not the entire NYM/Cloudflare backend. qWDTT access
subscriptions are server credentials, not an in-app payment system.

See [build/routing instructions](docs/BUILD-QWDTT.md) and the
[patch report](docs/kachat-payments-performance-2026-11-04.md),
[current release verification](docs/kachat-release-3-2026-11-04.md) and
[qWDTT settings parity](docs/qwdtt-settings-parity.md).
Native media uses routed downloads before local playback; streaming playback
through a new local range server is not implemented. Native FCM is not
configured in this Android build.

## Development

Use the pinned Flutter/Dart and Android toolchain described in
[BUILD-QWDTT.md](docs/BUILD-QWDTT.md). No credentials, real call hashes, SSH keys
or signing keys belong in this repository. Android `key.properties`,
`local.properties`, caches and build outputs are ignored.

```sh
cd flutter
flutter pub get
flutter analyze
flutter test test/payments test/performance test/qwdtt
cd android
./gradlew :app:testDebugUnitTest
```

APKs are available under GitHub Releases. For Pixel use arm64-v8a.
They are AOT Release builds signed with the existing local test certificate;
this signing continuity is not a production security certification.

Build/install/release steps are separate from source checks.
The current patch has not been installed or profiled on a physical Pixel.
A source review and synthetic tests do not establish device frame rates,
battery behavior, live tunnel availability or security guarantees.

Original upstream documentation is retained in
[docs/upstream/NYM-README.md](docs/upstream/NYM-README.md).
