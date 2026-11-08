#!/usr/bin/env bash
set -euo pipefail
# Supply ANDROID_NDK_HOME and a rustup toolchain with the three Android targets.
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to an installed Android NDK}"
base="$(cd "$(dirname "$0")" && pwd)"
clang="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$clang/aarch64-linux-android29-clang"
export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$clang/armv7a-linux-androideabi29-clang"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$clang/x86_64-linux-android29-clang"
out="$base/../../flutter/android/app/src/main/jniLibs"
for item in aarch64-linux-android:arm64-v8a armv7-linux-androideabi:armeabi-v7a x86_64-linux-android:x86_64; do
  target="${item%%:*}"; abi="${item#*:}"
  cargo build --locked --release --lib --target "$target" --manifest-path "$base/crate/Cargo.toml"
  mkdir -p "$out/$abi"
  cp "$base/crate/target/$target/release/libmesh_frag.so" "$out/$abi/"
done
