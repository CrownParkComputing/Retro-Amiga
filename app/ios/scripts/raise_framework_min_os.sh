#!/bin/sh
# Raises MinimumOSVersion on everything embedded in the app bundle, as a build
# phase, so the archive is correct when it is produced rather than corrected
# afterwards.
#
# Validation 90068 rejects an upload whose embedded binaries declare a
# MinimumOSVersion below Apple's floor, and two sources here sit below it no
# matter what IPHONEOS_DEPLOYMENT_TARGET says:
#
#   - The Flutter engine ships Flutter.framework and App.framework at its own
#     floor. Setting MinimumOSVersion in ios/Flutter/AppFrameworkInfo.plist
#     does not help: the tool rewrites that plist during the build.
#   - libuae4arm.framework is a committed prebuilt binary, cross-compiled at
#     13.0. Confirmed, not assumed: llvm-objdump -p reports
#     "platform ios / sdk 16.0 / minos 13.0 / tool lld". Rebuilding it to
#     change one load command would need the cross-compiled Amiberry object
#     tree, which is not in this repository, and native/ios/build-core-ios.sh
#     pins 13.0 as the floor SDL3 supports.
#
# Both .framework bundles and bare dylibs are patched. This app ships no loose
# dylib -- the core is wrapped as a framework precisely because a bare one is
# rejected as 90426 -- but the dylib loop stays so a future one cannot slip
# through unpatched.
#
# Both places the version is recorded have to agree -- the Info.plist key and
# the Mach-O LC_BUILD_VERSION load command -- because Apple reads the load
# command, not just the plist.
#
# Runs as the last phase of the Runner target: after "Thin Binary"
# (embed_and_thin), "[CP] Embed Pods Frameworks" and the Embed Frameworks phase
# that copies the cores have all put everything in place. Editing a binary
# invalidates its signature, so each one is re-signed here with
# EXPANDED_CODE_SIGN_IDENTITY, the identity Xcode resolved for this build --
# which is what makes this work under Xcode Cloud's managed signing, where no
# identity can be named ahead of time. Xcode signs the outer .app after all
# build phases, so the app's own signature is unaffected.
set -eu

APP="${CODESIGNING_FOLDER_PATH:-${TARGET_BUILD_DIR:-}/${WRAPPER_NAME:-}}"
MIN="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"

[ -n "$APP" ] && [ -d "$APP/Frameworks" ] || {
  echo "note: no embedded frameworks to patch"
  exit 0
}

# Re-sign one embedded item. An unsigned build (flutter build ios
# --no-codesign) has no identity and needs none -- the patch is still correct,
# it just is not signed. Only skip in that case; a signing build that somehow
# lacks the identity should fail loudly rather than ship a broken signature.
# Flags deliberately match Pods-Runner-frameworks.sh, which re-signs the
# embedded frameworks in this same bundle -- same identity, same preserved
# metadata, so this phase cannot disagree with the one before it.
resign() {
  [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] || return 0
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:?no signing identity for $1}" \
    ${OTHER_CODE_SIGN_FLAGS:-} --preserve-metadata=identifier,entitlements "$1"
}

# -replace rewrites an existing LC_BUILD_VERSION rather than appending a second
# one, which would make the binary invalid.
set_min() {
  xcrun vtool -set-build-version ios "$MIN" "$MIN" -replace \
    -output "$1" "$1" >/dev/null
}

for fw in "$APP"/Frameworks/*.framework; do
  [ -d "$fw" ] || continue
  name="$(basename "$fw" .framework)"
  plist="$fw/Info.plist"
  binary="$fw/$name"

  if [ -f "$plist" ]; then
    /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $MIN" "$plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string $MIN" "$plist"
  fi

  [ -f "$binary" ] && set_min "$binary"
  resign "$fw"
  echo "note: $name.framework -> MinimumOSVersion $MIN"
done

for dylib in "$APP"/Frameworks/*.dylib; do
  [ -f "$dylib" ] || continue
  set_min "$dylib"
  resign "$dylib"
  echo "note: $(basename "$dylib") -> minos $MIN"
done
