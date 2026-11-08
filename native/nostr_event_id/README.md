# Nostr event IDs

Android uses the optional Rust FFI library to compute NIP-01 IDs. If the library
cannot load, the call fails, or any input contains an unpaired UTF-16 surrogate,
the original Dart implementation is used. Wire data and canonical JSON remain
compatible with Nym. The C interface accepts a JSON array of event fields and
writes a 64-byte lowercase hex ID into caller-owned memory.

Rebuild the checked-in Android libraries using `tools/build-nostr-event-id.sh`.
This requires cargo-ndk, an Android NDK, and Rust targets for armeabi-v7a,
arm64-v8a, and x86_64. Run `cargo test --locked` in this directory. To run the
Flutter FFI integration test on a host, build the host library and set
`NOSTR_TEST_LIBRARY` to its absolute path when invoking Flutter test.

`flutter/tool/nostr_event_id_bench.dart` is a host Dart AOT smoke benchmark of
the full FFI path, not an Android or application-level performance claim.
