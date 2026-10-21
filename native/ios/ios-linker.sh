#!/usr/bin/env bash
# Linker driver rustc calls for aarch64-apple-ios.
#
# The iosbox clang shim only rewrites a link it recognises as iOS by the
# literal `arm64-apple-ios*` value of -target; rustc's invocation does not
# take that shape, so the platform flags are spelled out here the same way
# build-core-ios.sh passes them to CMake.
set -euo pipefail

IOSBOX_ROOT="${IOSBOX_ROOT:-/root/.iosbox}"
IOS_LD="${IOS_LD:-$IOSBOX_ROOT/sdk/darwin.artifactbundle/toolset/bin/ld64.lld}"
IOS_BUILTINS="${IOS_BUILTINS:-$IOSBOX_ROOT/sdk/darwin.artifactbundle/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/17/lib/darwin/libclang_rt.ios.a}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-13.0}"

exec /usr/bin/clang -target "arm64-apple-ios$DEPLOYMENT_TARGET" \
    -fuse-ld="$IOS_LD" \
    -Wl,-platform_version,ios,"$DEPLOYMENT_TARGET",16.0.0 \
    -Wl,-adhoc_codesign \
    "$@" "$IOS_BUILTINS"
