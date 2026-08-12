#!/usr/bin/env bash
# Build the iOS app on Linux, without macOS or Xcode.
#
# iosbox supplies clang + swiftc targeting arm64-apple-ios, linked with
# ld64.lld against an iOS SDK extracted from Xcode. The SDK is not in the
# image: it lives in the `iosbox-sdk` Docker volume.
#
# Output: app/build/iosbox/Runner.ipa (unsigned, debug configuration).
# MobAI signs it at install time; see tools/device-push.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IOSBOX_IMAGE:-mobaiapp/iosbox:latest}"
SDK_VOLUME="${IOSBOX_SDK_VOLUME:-iosbox-sdk}"
CORE="$REPO_ROOT/native/ios/out/libuae4arm.dylib"

if ! docker volume inspect "$SDK_VOLUME" >/dev/null 2>&1; then
    echo "error: Docker volume '$SDK_VOLUME' not found - the iOS SDK is not registered." >&2
    exit 1
fi

# An unparseable Info.plist does not warn: the plist just fails to load, iOS
# ignores the scene configuration, and the app launches to a black screen with
# nothing in any log. Cheaper to catch here than on the device.
echo "==> checking Info.plist"
python3 -c 'import plistlib,sys; plistlib.load(open(sys.argv[1],"rb"))' \
    "$REPO_ROOT/app/ios/Runner/Info.plist" \
    || { echo "error: app/ios/Runner/Info.plist is not valid XML." >&2; exit 1; }

echo "==> building the iOS app"
docker run --rm \
    -v "$SDK_VOLUME:/root/.iosbox" \
    -v "$REPO_ROOT:/proj" \
    "$IMAGE" iosbox build /proj/app

# The container runs as root and everything it wrote into the bind mount is
# left root-owned, which breaks the host Flutter afterwards and blocks the
# bundling below. Hand ownership back before touching anything.
echo "==> restoring file ownership"
docker run --rm -v "$REPO_ROOT:/proj" alpine \
    chown -R "$(id -u):$(id -g)" /proj

APP="$REPO_ROOT/app/build/iosbox/Runner.app"
IPA="$REPO_ROOT/app/build/iosbox/Runner.ipa"

# iosbox regenerates its SwiftPM package each run, so there is no supported way
# to add link flags to the Runner target. The core is copied in afterwards and
# found at runtime through @rpath, and the IPA is repacked because iosbox has
# already zipped one without it.
# iosbox cannot compile Assets.xcassets - actool is macOS-only - so the app
# bundle comes out with no icon at all. Loose PNGs in the bundle root, named by
# CFBundleIconFiles in Info.plist, are the mechanism that predates asset
# catalogues and iOS still honours it.
if [ -d "$REPO_ROOT/app/ios/Runner/LooseIcons" ]; then
    echo "==> bundling the launcher icon"
    cp "$REPO_ROOT/app/ios/Runner/LooseIcons/"*.png "$APP/" 2>/dev/null || true
fi

if [ -f "$CORE" ]; then
    echo "==> bundling the emulator core"
    mkdir -p "$APP/Frameworks"
    cp -v "$CORE" "$APP/Frameworks/"

    rm -rf "$REPO_ROOT/app/build/iosbox/Payload"
    mkdir -p "$REPO_ROOT/app/build/iosbox/Payload"
    cp -a "$APP" "$REPO_ROOT/app/build/iosbox/Payload/"
    ( cd "$REPO_ROOT/app/build/iosbox" \
        && rm -f Runner.ipa \
        && zip -qry Runner.ipa Payload \
        && rm -rf Payload )
    echo "    repacked $(basename "$IPA")"
else
    echo "==> WARNING: no core at $CORE - the app will build and launch but"
    echo "    cannot start emulation. Build it with tools/build-ios-core.sh"
fi

echo "==> done"
ls -lh "$IPA"
