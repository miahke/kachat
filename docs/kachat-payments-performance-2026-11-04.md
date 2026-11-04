> Historical report. Its payment-disabled policy is superseded by [release 3](kachat-release-3-2026-11-04.md), which restores optional commerce behind warnings.

# kachat: payments, About, branding and performance — 2026-11-04

This source patch follows the user's approved icon. No APK build/install or
GitHub publication is part of this review stage.

## Removed payment surfaces

The store and Lightning invoice/wallet modals were removed. Standard mobile,
desktop, context, hover, slash-command and swipe payment entries are absent.
Saved/synced Zap gestures normalize to quote/translate/default hover actions.
Deprecated entry points show a local explanation rather than creating invoices.
Purchases/gifts of bot credits and financial API actions fail before transport
or signing. Old purchases are not reconciled on app wake. Read-only rendering
of existing cosmetic items and normal chat remain compatible with peers.
The editable Lightning-address field was removed without silently deleting
existing profile fields when a user edits their nickname/avatar.

Cashu/payment requests, supported cryptocurrency URIs and invoice-like payloads
render as inert text with a notice. Existing zap receipts show a passive notice.
There is no wallet button or redeem action. This does not prevent a person from
copying text or using an external browser/wallet outside this app.

Copy: "Payments are disabled in kachat. The app does not verify recipients or
guarantee transfer safety." It does not claim that open-source software is
inherently unsafe. Bundled translations of the notice were added for 21 language
packs, including Russian; other locales use the existing localization pipeline.

## About and branding

Removed the original NYM publisher build-comparison panel and live warrant
canary, including their network/version fetches on opening About. They are
optional displays, not a prerequisite for message encryption or delivery.
The old canary is a statement by NYM's publisher, not an attestation about
kachat. Version now comes from the installed local package.
Android's APK signature enforcement, Keystore and message cryptography remain.

The client is named kachat in app titles, launcher, About and notifications.
Color theme labels are Green, Lime, Amber, Magenta, Cyan and White; stored theme
IDs stay unchanged. Required attribution "Based on Nymchat by 21 Million LLC"
and source link are preserved. Actual upstream developer/bot names, account
formats, backend hostnames, client protocol identifiers and the shared #nymchat
channel stay intact for truthful attribution and interoperability.

The planned project links target github.com/miahke/kachat. Publication and artifact status are recorded in
[kachat-test-1.md](kachat-test-1.md). Upstream service privacy/terms URLs still describe
the NYM backend the client continues to use; they are not presented as a new
self-hosted kachat backend.

## One GPT-6 Astra optimization pass

Astra performed one read-only code review, without real accounts/phones or
server calls. It identified scaling problems, not a measured cause of the
reported Pixel hangs. Implemented safe changes:

- Eager same-author groups are capped at 24 messages per rendered unit in both
  single-chat and columns views. A synthetic 1000-message run becomes 42 groups;
  every message ID and order is preserved, as are explicit navigation breaks.
- Cached group widgets for deleted/regrouped units are pruned; retained widget
  configurations are bounded to 256. Message history is not deleted or capped.
- Native qWDTT caches only sanitized profile metadata. Repeated status polls no
  longer decrypt/validate the whole profile store and JSON-roundtrip every
  profile. Import/save/delete invalidate metadata; connect still loads secrets
  from encrypted storage. A counting test checks 100 polls -> one load and
  invalidation/error retry behavior.
- Unchanged qWDTT snapshots do not notify the whole settings page. Route
  application and the previously fixed stale-RPC revision guard remain active.
- Media keeps pending request deduplication separate from completed file cache,
  limits active downloads to two, throttles/serializes cache maintenance and
  protects files currently being written. IOSink.addStream provides backpressure
  instead of flushing every network chunk. HTTPS, the authenticated route,
  100 MiB response limit and partial-file cleanup remain enforced.

Unmeasured/follow-up items: physical profile/release frame-time/heap traces,
progress/cancellation and consumer leases for media, progressive authenticated
range playback, broad user-list revision/merge refactors and an isolate-owned
CONNECT gateway. Passing remote URLs to native players is not an acceptable
shortcut because it could bypass qWDTT. Full media downloads still precede
native playback. No extra Astra review was started.

## Validation and limits

Flutter tests cover financial API rejection without HTTP, inert UI/receipts,
legacy gestures, About opening without network checks, 1000-message grouping,
media deduplication/concurrency/limits and the existing qWDTT route regression
suite. JVM tests cover transport/subscription/VK/deployment and metadata cache.
Static analysis and diff whitespace checks are run separately.

No claim is made that Pixel stutters are fixed on hardware. Radio, real
VK/VPS availability, physical-device scrolling/selection/anchor behavior and
battery use require an approved subsequent build and synthetic device tests.
This patch does not replace upstream NYM server storage or alter message wire
formats. qWDTT administration subscriptions remain access credentials, not a
payment function.

### Final local checks

- Flutter targeted regression suite: 26 passed, one optional preview skipped.
- Android/JVM: 34 tests, zero failures/errors. No APK packaging task was run.
- Receipt badge regression: ordinary reactions show no payment notice; legacy
  payment receipts show an inert localized notice.
- All 21 bundled payment-notice language packs parse as JSON.
- Required attribution remains in NOTICE and About.
- The owner subsequently authorized packaging and publication; see
  [kachat-test-1.md](kachat-test-1.md) for artifact status.
