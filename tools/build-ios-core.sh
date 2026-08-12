#!/usr/bin/env bash
# Host entry point: build libuae4arm.dylib for arm64 iOS from Linux, with no
# Mac involved.
#
# Uses the mobaiapp/iosbox cross toolchain (clang targeting arm64-apple-ios,
# ld64.lld) against an iOS SDK extracted from Xcode. The SDK is not in the
# image: it lives in the `iosbox-sdk` Docker volume, put there once with
# `iosbox setup /path/to/Xcode.xip`.
#
#   tools/build-ios-core.sh              # SDL3 then the core (slow first time)
#   SKIP_SDL=1 tools/build-ios-core.sh   # relink the core alone
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${UAE4ARM_IOS_IMAGE:-uae4arm-iosbox:latest}"
SDK_VOLUME="${IOSBOX_SDK_VOLUME:-iosbox-sdk}"

if ! docker volume inspect "$SDK_VOLUME" >/dev/null 2>&1; then
    echo "error: Docker volume '$SDK_VOLUME' not found - the iOS SDK is not registered." >&2
    echo "       Register it once with iosbox setup /path/to/Xcode.xip" >&2
    exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "==> building $IMAGE"
    docker build -t "$IMAGE" "$REPO_ROOT/native/ios"
fi

docker run --rm \
    -e "SKIP_SDL=${SKIP_SDL:-0}" \
    -v "$SDK_VOLUME:/root/.iosbox" \
    -v "$REPO_ROOT:/proj" \
    "$IMAGE" bash -lc "/proj/native/ios/build-core-ios.sh"

# The container runs as root and everything it wrote into the bind mount is
# left root-owned, which silently breaks the host Flutter afterwards (the next
# build dies trying to refresh .dart_tool). Hand ownership back immediately.
echo "==> restoring file ownership"
docker run --rm -v "$REPO_ROOT:/proj" alpine \
    chown -R "$(id -u):$(id -g)" /proj/native/ios

ls -lh "$REPO_ROOT/native/ios/out" 2>/dev/null || true
