#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to NDK 27.3.13750724}"
[[ "$(sed -n 's/Pkg.Revision *= *//p' "$ANDROID_NDK_HOME/source.properties")" == 27.3.13750724 ]]
[[ "$(go env GOVERSION)" == go1.27.3* ]]
cd "$root/native/pt"
for spec in arm64-v8a:arm64:aarch64-linux-android armeabi-v7a:arm:armv7a-linux-androideabi x86_64:amd64:x86_64-linux-android; do
  IFS=: read -r abi arch target <<< "$spec"
  mkdir -p "$root/flutter/android/app/src/main/jniLibs/$abi"
  GOOS=android GOARCH="$arch" GOARM=7 CGO_ENABLED=1 \
  CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/${target}29-clang" \
  CGO_CFLAGS=-O2 CGO_CXXFLAGS=-O2 \
  go build -mod=readonly -trimpath -buildmode=pie \
    -ldflags='-s -w -checklinkname=0 -extldflags=-Wl,-z,max-page-size=16384' \
    -o "$root/flutter/android/app/src/main/jniLibs/$abi/libbitchat_pt.so" ./cmd/lyrebird
done
