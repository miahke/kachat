# kachat payments, About and performance patch

User-authorized scope: no store/payments; localized notice for payment content;
remove optional upstream About checks, rename UI and themes; one GPT-6 Astra
performance pass preserving messenger/qWDTT functionality. No APK or GitHub
publication before presenting changes to the user.

- [x] Remove store/payment modals, wallet actions and menu/gesture entries;
  enforce financial API barriers before transport/signing and migrate old gestures.
- [x] Replace payment receipts/payload actions with an inert localized notice;
  keep ordinary chat content and non-financial styling compatible.
- [x] Remove NYM publisher canary/build panels and network checks from About;
  show installed local version, preserve attribution and Android APK signing.
- [x] Use color-based theme names and client branding kachat; retain protocol,
  backend, account and shared-channel identifiers for interoperability.
- [x] Run one read-only Astra pass; implement bounded chat groups/cache,
  native secret-free profile metadata cache, unchanged-status notification
  suppression, bounded/deduplicated media queue and buffered stream writes.
- [x] Verify synthetic grouping, route races, payment barriers, old settings,
  media limits/deduplication/concurrency, About and native metadata cache.
- [ ] Present patch and limitations; wait for user direction before build/publish.
