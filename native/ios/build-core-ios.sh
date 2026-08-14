#!/usr/bin/env bash
# Cross-compile libuae4arm.dylib for arm64 iOS. Runs INSIDE the container
# built from the Dockerfile next to this file; use tools/build-ios-core.sh on
# the host.
#
# Two stages. SDL3 has to exist before the core can be configured, because
# the iOS branch of cmake/Dependencies.cmake resolves it with
# find_package(SDL3 CONFIG REQUIRED) rather than fetching it.
#
#   1. SDL3 + SDL3_image, installed into a prefix inside the build tree
#   2. the emulator core, linked as a dylib the Flutter app dlopens
#
# Stage 1 is slow and only needs redoing when the pinned SDL version changes;
# pass SKIP_SDL=1 to rebuild the core alone.
set -euo pipefail

PROJ="${PROJ:-/proj}"
BUILD="$PROJ/native/ios/build"
PREFIX="$BUILD/prefix"
IOSBOX_ROOT="${IOSBOX_ROOT:-/root/.iosbox}"
IOS_SDK="${IOS_SDK:-$IOSBOX_ROOT/sdk/darwin.artifactbundle/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk}"

# iOS 13 is the floor SDL3 supports; the target device runs far newer.
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-13.0}"
SDL_TAG="${SDL_TAG:-release-3.4.4}"
SDL_IMAGE_TAG="${SDL_IMAGE_TAG:-release-3.4.2}"
FLAC_TAG="${FLAC_TAG:-1.5.0}"
LIBPNG_TAG="${LIBPNG_TAG:-v1.6.44}"

# iosbox keeps its Apple binutil shims (install_name_tool, otool, libtool,
# dsymutil) out of the default PATH. CMake's Objective-C language check looks
# for install_name_tool by name and fails configure without it, so put the
# shims in front of everything.
IOSBOX_SHIMS="${IOSBOX_SHIMS:-/usr/local/lib/iosbox/shims}"
export PATH="$IOSBOX_SHIMS:$PATH"

# Linking Mach-O needs ld64.lld, and it needs to be told the platform
# explicitly: the host default linker cannot produce iOS binaries at all, so
# without this every one of CMake's try_link feature probes fails and SDL
# concludes the platform has no threads, no dlopen and no Metal.
IOS_LD="${IOS_LD:-$IOSBOX_ROOT/sdk/darwin.artifactbundle/toolset/bin/ld64.lld}"
# compiler-rt's iOS builtins carry __clear_cache and __isPlatformVersionAtLeast
# (the latter backs ObjC @available checks, which SDL's UIKit code uses).
# clang would add this automatically on a Mac; cross-compiling it has to be
# named explicitly.
IOS_BUILTINS="${IOS_BUILTINS:-$IOSBOX_ROOT/sdk/darwin.artifactbundle/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/17/lib/darwin/libclang_rt.ios.a}"
IOS_LINK_FLAGS="-fuse-ld=$IOS_LD -Wl,-arch,arm64 -Wl,-platform_version,ios,${DEPLOYMENT_TARGET}.0,16.0.0 -Wl,-adhoc_codesign $IOS_BUILTINS"

if [ ! -d "$IOS_SDK" ]; then
    echo "error: no iOS SDK at $IOS_SDK" >&2
    echo "       the iosbox-sdk volume is not mounted, or the SDK was never registered" >&2
    exit 1
fi

mkdir -p "$BUILD" "$PREFIX"

# Everything the cross build needs, in one place. CMake is told this is iOS
# via CMAKE_SYSTEM_NAME, which is what makes our own if(IOS) branches fire.
cmake_ios_args=(
    -G Ninja
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_SYSTEM_PROCESSOR=arm64
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_OSX_SYSROOT="$IOS_SDK"
    # Full paths, not bare names: CMake resolves the compiler against its own
    # PATH view and SDL3_image's enable_language(OBJC) fails on a bare "clang".
    # The iosbox clang is a shim that injects the linker and Mach-O platform
    # flags; there is no clang++ shim, which is why C++ uses the plain driver
    # and the link flags below are supplied explicitly.
    -DCMAKE_C_COMPILER="$IOSBOX_SHIMS/clang"
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++
    -DCMAKE_C_COMPILER_TARGET="arm64-apple-ios$DEPLOYMENT_TARGET"
    -DCMAKE_CXX_COMPILER_TARGET="arm64-apple-ios$DEPLOYMENT_TARGET"
    -DCMAKE_C_COMPILER_WORKS=ON
    -DCMAKE_CXX_COMPILER_WORKS=ON
    # SDL3 enables Objective-C for the UIKit backend. Without its own target
    # triple clang falls back to the host one and rejects -mios-version-min,
    # so the ObjC compiler check fails even though C and C++ are fine.
    -DCMAKE_OBJC_COMPILER="$IOSBOX_SHIMS/clang"
    -DCMAKE_OBJCXX_COMPILER=/usr/bin/clang++
    -DCMAKE_OBJC_COMPILER_TARGET="arm64-apple-ios$DEPLOYMENT_TARGET"
    -DCMAKE_OBJCXX_COMPILER_TARGET="arm64-apple-ios$DEPLOYMENT_TARGET"
    -DCMAKE_OBJC_COMPILER_WORKS=ON
    -DCMAKE_OBJCXX_COMPILER_WORKS=ON
    -DCMAKE_FIND_ROOT_PATH="$PREFIX;$IOS_SDK"
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY
    -DCMAKE_PREFIX_PATH="$PREFIX"
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
    -DCMAKE_BUILD_TYPE=Release
    # SDL3_image decides which SDL3 component to require from BUILD_SHARED_LIBS,
    # not from its own SDLIMAGE_SHARED flag: left on, it demands SDL3-shared and
    # rejects the static SDL3 we just installed. Our own core passes SHARED to
    # add_library explicitly, so this does not affect it.
    -DBUILD_SHARED_LIBS=OFF
    -DCMAKE_INSTALL_NAME_TOOL="$IOSBOX_SHIMS/install_name_tool"
    -DCMAKE_EXE_LINKER_FLAGS="$IOS_LINK_FLAGS"
    -DCMAKE_SHARED_LINKER_FLAGS="$IOS_LINK_FLAGS"
    -DCMAKE_MODULE_LINKER_FLAGS="$IOS_LINK_FLAGS"
    -DCMAKE_AR=/usr/bin/llvm-ar
    -DCMAKE_RANLIB=/usr/bin/llvm-ranlib
)

fetch() {
    local name="$1" repo="$2" tag="$3"
    if [ ! -d "$BUILD/$name" ]; then
        echo "==> fetching $name $tag"
        git clone --depth 1 --branch "$tag" "$repo" "$BUILD/$name"
    fi
}

if [ "${SKIP_SDL:-0}" != "1" ]; then
    echo "==> stage 1/3: SDL3 for arm64 iOS"
    fetch SDL https://github.com/libsdl-org/SDL.git "$SDL_TAG"
    # COMPILER_SUPPORTS_FOBJC_ARC is pre-seeded because the probe cannot
    # succeed here even though the flag works. clang derives -ios_version_min
    # from the target triple when linking, ld64.lld answers "not yet
    # implemented", and check_c_compiler_flag counts any warning in the
    # compile-or-link output as failure. The probe itself exits 0; see
    # CMakeConfigureLog.yaml.
    cmake -S "$BUILD/SDL" -B "$BUILD/SDL-build" "${cmake_ios_args[@]}" \
        -DCOMPILER_SUPPORTS_FOBJC_ARC=1 \
        -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
    cmake --build "$BUILD/SDL-build" --target install

    echo "==> stage 1/3: SDL3_image for arm64 iOS (after its deps)"
    fetch SDL_image https://github.com/libsdl-org/SDL_image.git "$SDL_IMAGE_TAG"
    cmake -S "$BUILD/SDL_image" -B "$BUILD/SDL_image-build" "${cmake_ios_args[@]}" \
        -DSDLIMAGE_SHARED=OFF -DSDLIMAGE_STATIC=ON \
        -DSDLIMAGE_DEPS_SHARED=OFF \
        -DSDLIMAGE_SAMPLES=OFF -DSDLIMAGE_TESTS=OFF \
        -DSDLIMAGE_JXL=OFF -DSDLIMAGE_AVIF=OFF -DSDLIMAGE_TIF=OFF \
        -DSDLIMAGE_WEBP=OFF
    cmake --build "$BUILD/SDL_image-build" --target install

    # FLAC is not optional here despite the comment in Dependencies.cmake's iOS
    # branch: CHD CD images store their audio tracks FLAC-compressed, and
    # blkdev_cdimage.cpp includes <FLAC/all.h> unconditionally through
    # archivers/chd. Without it there is no CD32 or CDTV.
    echo "==> stage 1/3: FLAC for arm64 iOS"
    fetch flac https://github.com/xiph/flac.git "$FLAC_TAG"
    cmake -S "$BUILD/flac" -B "$BUILD/flac-build" "${cmake_ios_args[@]}" \
        -DBUILD_PROGRAMS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF \
        -DBUILD_DOCS=OFF -DINSTALL_MANPAGES=OFF -DWITH_OGG=OFF
    cmake --build "$BUILD/flac-build" --target install

    # Same story as FLAC: specialmonitors.cpp includes png.h unconditionally
    # for screenshot and specialmonitor output, so a QUIET find is not enough.
    # zlib comes from the iOS SDK.
    echo "==> stage 1/3: libpng for arm64 iOS"
    fetch libpng https://github.com/pnggroup/libpng.git "$LIBPNG_TAG"
    cmake -S "$BUILD/libpng" -B "$BUILD/libpng-build" "${cmake_ios_args[@]}" \
        -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF \
        -DPNG_FRAMEWORK=OFF
    cmake --build "$BUILD/libpng-build" --target install
else
    echo "==> stage 1/3: skipped (SKIP_SDL=1)"
fi

echo "==> stage 3/3: the emulator core"
# Everything optional is off. PCem is x86 hardware emulation, the serial,
# MIDI and network backends have no iOS story, and the self-updater is
# forbidden by the App Store anyway. JIT is already disabled for iOS in
# sysconfig.h, so this is an interpreter-only build by construction.
cmake -S "$PROJ" -B "$BUILD/core" "${cmake_ios_args[@]}" \
    -DAMIBERRY_IOS=ON \
    -DUSE_PCEM=OFF \
    -DUSE_PPC=OFF \
    -DUSE_LIBSERIALPORT=OFF \
    -DUSE_PORTMIDI=OFF \
    -DUSE_LIBENET=OFF \
    -DUSE_ZSTD=OFF \
    -DUSE_OPENGL=ON \
    -DUSE_GLES=ON

cmake --build "$BUILD/core"

OUT="$PROJ/native/ios/out"
mkdir -p "$OUT"
find "$BUILD/core" -name "libuae4arm*.dylib" -exec cp -v {} "$OUT/" \;
ls -lh "$OUT" || true
echo "==> done"
