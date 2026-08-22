#!/usr/bin/env bash
# Package the device and simulator cores into libuae4arm.xcframework.
#
#   tools/make-core-xcframework.sh
#
# WHY AN XCFRAMEWORK. The app embeds one artifact and dlopens it by the fixed
# path "libuae4arm.framework/libuae4arm" (see AmigaCore._libraryPath). A plain
# .framework can only hold one platform, so the embedded core was a DEVICE
# binary and every simulator run failed to dlopen it -- "incompatible platform
# (have 'iOS', need 'iOS-simulator')". An .xcframework holds both slices and
# Xcode embeds whichever matches the destination, so the same dlopen path
# works in every mode and no build step has to swap files around.
#
# It is frameworks inside, not bare dylibs, precisely so that path does not
# change: -library would embed "libuae4arm.dylib" and break the Dart side.
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$PROJ/native/ios/xcframework-stage"
OUT="$PROJ/app/ios/Frameworks/libuae4arm.xcframework"

DEVICE_LIB="${DEVICE_LIB:-$PROJ/native/ios/out/libuae4arm.dylib}"
SIM_LIB="${SIM_LIB:-$PROJ/native/ios/out-simulator/libuae4arm.dylib}"

# The committed framework is the device build's shipping form, so it stands in
# when native/ios/out has been cleaned -- which it usually has, since the
# device core is built in a container that is not kept around.
if [ ! -f "$DEVICE_LIB" ]; then
    DEVICE_LIB="$PROJ/app/ios/Frameworks/libuae4arm.framework/libuae4arm"
fi

[ -f "$DEVICE_LIB" ] || { echo "error: no device core at $DEVICE_LIB" >&2; exit 1; }
[ -f "$SIM_LIB" ] || {
    echo "error: no simulator core at $SIM_LIB" >&2
    echo "       build it with native/ios/build-core-simulator.sh" >&2
    exit 1
}

# Guard against the two inputs being the same platform. Both slices being
# device binaries produces an xcframework that Xcode accepts and that fails at
# dlopen on a simulator -- the exact bug this script exists to end.
check_platform() {
    local lib="$1" want="$2"
    vtool -show-build "$lib" | grep -q "platform $want" || {
        echo "error: $lib is not a $want binary:" >&2
        vtool -show-build "$lib" | sed 's/^/       /' >&2
        exit 1
    }
}
check_platform "$DEVICE_LIB" IOS
check_platform "$SIM_LIB" IOSSIMULATOR

# Info.plist mirrors the committed device framework, including
# MinimumOSVersion: the two slices of one xcframework must agree, and 15.0 is
# what the shipping device framework declares.
make_framework() {
    local src="$1" dest="$2" platform="$3"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp "$src" "$dest/libuae4arm"
    # dyld finds it through the app's rpath, which points at Frameworks/.
    # Without this the install name is whatever the build tree happened to be.
    install_name_tool -id "@rpath/libuae4arm.framework/libuae4arm" \
        "$dest/libuae4arm" 2>/dev/null
    cat > "$dest/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>libuae4arm</string>
	<key>CFBundleIdentifier</key><string>com.crownparkcomputing.libuae4arm</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>libuae4arm</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
	<key>MinimumOSVersion</key><string>15.0</string>
</dict>
</plist>
PLIST
    plutil -lint "$dest/Info.plist" >/dev/null
}

rm -rf "$STAGE"
mkdir -p "$STAGE"
echo "==> staging device framework"
make_framework "$DEVICE_LIB" "$STAGE/device/libuae4arm.framework" iPhoneOS
echo "==> staging simulator framework"
make_framework "$SIM_LIB" "$STAGE/simulator/libuae4arm.framework" iPhoneSimulator

echo "==> creating $OUT"
rm -rf "$OUT"
xcodebuild -create-xcframework \
    -framework "$STAGE/device/libuae4arm.framework" \
    -framework "$STAGE/simulator/libuae4arm.framework" \
    -output "$OUT" >/dev/null

rm -rf "$STAGE"
echo "==> done:"
find "$OUT" -name libuae4arm -exec sh -c \
    'printf "    %s -> " "${1#*libuae4arm.xcframework/}"; vtool -show-build "$1" | awk "/platform/{print \$2}"' _ {} \;
