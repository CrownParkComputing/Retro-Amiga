#!/bin/sh
# Xcode Cloud post-clone step.
#
# Xcode Cloud's images have Xcode and CocoaPods but no Flutter, and it does not
# run `flutter build` -- it invokes xcodebuild on the Runner scheme directly.
# That only works if Flutter has already generated ios/Flutter/Generated.xcconfig,
# because the Runner target's "Thin Binary" build phase calls
# "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" and FLUTTER_ROOT is
# defined in that file. So: install Flutter, resolve packages, and let
# `--config-only` write the config the Xcode build needs.
#
# Apple runs this from the ci_scripts directory, which must sit next to the
# Xcode project -- hence app/ios/ci_scripts/ rather than the repo root.
set -e

# Pinned rather than tracking stable. A newer Flutter resolves newer transitive
# packages and rewrites pubspec.lock mid-build, so an untracked toolchain makes
# cloud builds differ from CI for reasons that have nothing to do with the
# commit being built. This is the same version ViceMultiplatform pins, and it
# satisfies this app's Dart constraint (sdk: ^3.11.5).
FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.9}"
FLUTTER_HOME="$HOME/flutter"

echo "--- installing Flutter $FLUTTER_VERSION"
git clone --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
export PATH="$FLUTTER_HOME/bin:$PATH"
flutter --version

# The Flutter app lives in app/, not at the repo root.
APP_DIR="$CI_PRIMARY_REPOSITORY_PATH/app"
cd "$APP_DIR"

# The emulator core cannot be rebuilt here: it needs the cross-compiled Amiberry
# object tree, which lives outside this repository. It is committed for exactly
# this reason, so fail clearly if it is absent rather than producing an app that
# installs and then dies at "dlopen failed".
#
# An .xcframework holding frameworks, never a bare .dylib: a loose dylib in
# Frameworks/ is rejected by App Store validation as 90426 Invalid Swift
# Support, and the framework path inside is the one EmulatorHost.swift
# dlopens. The xcframework carries the device slice AND the simulator one so
# Xcode can embed whichever the destination needs; both are checked here,
# because a half-populated one builds for a device and then fails at dlopen
# on a simulator -- the exact failure it exists to prevent.
CORE_XC="ios/Frameworks/libuae4arm.xcframework"
for slice in ios-arm64 ios-arm64-simulator; do
  if [ ! -f "$CORE_XC/$slice/libuae4arm.framework/libuae4arm" ]; then
    echo "error: missing $CORE_XC/$slice -- the emulator core must be committed" >&2
    exit 1
  fi
done

# Flutter 3.47 enables Swift Package Manager by default, and gamepads_ios has
# not adopted it. The mixed SPM/CocoaPods registrant then fails to compile for
# device -- "Module 'gamepads_ios' not found" -- which Flutter reports as the
# far less specific "No Xcode build settings have been found".
#
# GitHub Actions sets this explicitly in the workflow. Xcode Cloud runs THIS
# script instead, and `flutter config` is a per-machine setting, so a fix made
# on a laptop or in a workflow file never reaches these builders: they have to
# be told separately, which is why cloud builds failed while CI was green.
#
# Tolerated if the flag does not exist: older Flutter has no SPM to disable.
flutter config --no-enable-swift-package-manager || true

echo "--- resolving packages"
flutter precache --ios
flutter pub get

echo "--- generating the Xcode config Flutter's build phases rely on"
flutter build ios --release --no-codesign --config-only

# Plugin linkage. This project resolves file_picker and shared_preferences
# through Swift Package Manager, not CocoaPods, so there is normally no Podfile
# and `pod install` would fail with "no Podfile found". Run it only if
# --config-only actually produced one, so the script survives either mechanism.
cd ios
if [ -f Podfile ]; then
  echo "--- pod install"
  pod install --repo-update
else
  echo "note: no Podfile -- plugins resolve via Swift Package Manager"
fi

echo "--- ready for xcodebuild"
