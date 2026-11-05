# kachat release 4 — 2026-11-05

- qWDTT admin API validates three subscription ports before creating credentials.
- Telegram administration safely handles malformed legacy port records and validates manually entered ports in the range 1–65535.
- The embedded deployer contains the updated server binary and corresponding source.

The app remains a modified Nymchat fork; qWDTT is a transport and does not replace the NYM messaging backend. Release APKs retain the prior local test signing certificate and are not production-certified. On Pixel 6/7 Pro use arm64-v8a. Device and live VK validation remain pending.
