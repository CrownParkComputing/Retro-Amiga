#!/usr/bin/env bash
# Cross-compile the Copperline core (Rust) for arm64 iOS. Runs INSIDE the
# container built from Dockerfile.copperline; use
# tools/build-ios-copperline.sh on the host.
#
# Output: native/ios/out/libcopperline.dylib, which build-ios-app.sh packs
# as Frameworks/libcopperline.framework/libcopperline.
set -euo pipefail

PROJ="${PROJ:-/proj}"
OUT="$PROJ/native/ios/out"
BUILD="$PROJ/native/ios/build"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-13.0}"

IOSBOX_ROOT="${IOSBOX_ROOT:-/root/.iosbox}"
IOS_SDK="${IOS_SDK:-$IOSBOX_ROOT/sdk/darwin.artifactbundle/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk}"

if [ ! -d "$IOS_SDK" ]; then
    echo "error: no iOS SDK at $IOS_SDK" >&2
    echo "       the iosbox-sdk volume is not mounted, or the SDK was never registered" >&2
    exit 1
fi

export PATH="/root/.cargo/bin:$PATH"
export IPHONEOS_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
# clang reads SDKROOT for -isysroot when it is not passed explicitly.
export SDKROOT="$IOS_SDK"
export CARGO_TARGET_AARCH64_APPLE_IOS_LINKER="$PROJ/native/ios/ios-linker.sh"
# C sources in dependency build scripts (objc shims and friends) get the
# same cross compiler the CMake build uses.
export CC_aarch64_apple_ios=/usr/bin/clang
export AR_aarch64_apple_ios=/usr/bin/llvm-ar
export CFLAGS_aarch64_apple_ios="-target arm64-apple-ios$DEPLOYMENT_TARGET"

cargo build --release --target aarch64-apple-ios \
    --manifest-path "$PROJ/native/copperline_ffi/Cargo.toml" \
    --target-dir "$BUILD/copperline-target"

mkdir -p "$OUT"
cp -v "$BUILD/copperline-target/aarch64-apple-ios/release/libcopperline_ffi.dylib" \
    "$OUT/libcopperline.dylib"
ls -lh "$OUT"
echo "==> done"
