#!/usr/bin/env bash
# Host entry point: build libcopperline.dylib for arm64 iOS from Linux.
#
# Same iosbox cross toolchain as the Amiberry core (clang targeting
# arm64-apple-ios, ld64.lld, iOS SDK from the iosbox-sdk volume), plus a
# Rust toolchain the copperline-iosbox image carries on top.
#
#   tools/build-ios-copperline.sh   # -> native/ios/out/libcopperline.dylib
#
# tools/build-ios-app.sh picks the dylib up and packs it as
# Frameworks/libcopperline.framework/libcopperline.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${COPPERLINE_IOS_IMAGE:-copperline-iosbox:latest}"
SDK_VOLUME="${IOSBOX_SDK_VOLUME:-iosbox-sdk}"

if ! docker volume inspect "$SDK_VOLUME" >/dev/null 2>&1; then
    echo "error: Docker volume '$SDK_VOLUME' not found - the iOS SDK is not registered." >&2
    exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "==> building $IMAGE"
    docker build -t "$IMAGE" -f "$REPO_ROOT/native/ios/Dockerfile.copperline" \
        "$REPO_ROOT/native/ios"
fi

docker run --rm \
    -v "$SDK_VOLUME:/root/.iosbox" \
    -v "$REPO_ROOT:/proj" \
    "$IMAGE" bash -lc "/proj/native/ios/build-copperline-ios.sh"

# The container runs as root; hand ownership back before the host touches
# anything (same reason as build-ios-core.sh).
echo "==> restoring file ownership"
docker run --rm -v "$REPO_ROOT:/proj" alpine \
    chown -R "$(id -u):$(id -g)" /proj/native/ios

ls -lh "$REPO_ROOT/native/ios/out" 2>/dev/null || true
