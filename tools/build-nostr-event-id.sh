#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/native/nostr_event_id"
# Requires cargo-ndk, Rust Android targets and ANDROID_NDK_HOME.
cargo ndk -t armeabi-v7a -t arm64-v8a -t x86_64 -P 29 \
  -o "$root/flutter/android/app/src/main/jniLibs" \
  build --manifest-path "$root/native/nostr_event_id/Cargo.toml" --release --locked
