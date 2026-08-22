#!/usr/bin/env bash
# Build libuae4arm.dylib for the iOS SIMULATOR, natively on a Mac.
#
#   native/ios/build-core-simulator.sh              # SDL3 then the core
#   SKIP_SDL=1 native/ios/build-core-simulator.sh   # relink the core alone
#
# WHY THIS EXISTS. build-core-ios.sh cross-compiles a DEVICE binary
# (platform IOS) from Linux. A simulator cannot dlopen one at all --
# "incompatible platform (have 'iOS', need 'iOS-simulator')" -- so with only
# that build the emulator core is missing from every simulator run, and the
# app comes up as a UI with no machine behind it.
#
# WHY IT IS SO MUCH SHORTER than the Linux script. Everything that made that
# one long is Linux not being a Mac: the iosbox clang shims, ld64.lld with an
# explicit -platform_version, a named libclang_rt.ios.a, an SDK unpacked from
# an Xcode archive into a Docker volume. On a Mac, Xcode's own clang targets
# the simulator from CMAKE_OSX_SYSROOT alone and CMake derives the
# arm64-apple-ios<min>-simulator triple itself. None of that scaffolding is
# needed, and none of it is repeated here.
#
# The output pairs with the device dylib to make the XCFramework that the app
# embeds -- see tools/make-core-xcframework.sh.
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$PROJ/native/ios/build-sim"
PREFIX="$BUILD/prefix"

# Kept in step with build-core-ios.sh: the two slices of one XCFramework must
# agree on the deployment target or the framework is rejected at embed time.
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-13.0}"
SDL_TAG="${SDL_TAG:-release-3.4.4}"
SDL_IMAGE_TAG="${SDL_IMAGE_TAG:-release-3.4.2}"
FLAC_TAG="${FLAC_TAG:-1.5.0}"
LIBPNG_TAG="${LIBPNG_TAG:-v1.6.44}"

for tool in cmake ninja; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: $tool is not installed -- brew install cmake ninja" >&2
        exit 1
    }
done

SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)" || {
    echo "error: no iPhoneSimulator SDK -- is Xcode installed and selected?" >&2
    exit 1
}
echo "==> simulator SDK: $SIM_SDK"

mkdir -p "$BUILD" "$PREFIX"

# CMAKE_OSX_SYSROOT is the whole trick: with CMAKE_SYSTEM_NAME=iOS it is what
# separates a simulator build from a device one, and clang picks up the
# -simulator triple from it without being told.
#
# FIND_ROOT_PATH_MODE_PROGRAM=NEVER because the deps install host-side helper
# binaries into the prefix; letting find_program see them would hand a
# simulator binary to a build step that needs to RUN it.
cmake_sim_args=(
    -G Ninja
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_SYSROOT="$SIM_SDK"
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
    -DCMAKE_FIND_ROOT_PATH="$PREFIX;$SIM_SDK"
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY
    -DCMAKE_PREFIX_PATH="$PREFIX"
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
    -DCMAKE_BUILD_TYPE=Release
    # Same reason as the device build: SDL3_image reads BUILD_SHARED_LIBS, not
    # its own SDLIMAGE_SHARED, when deciding which SDL3 component to require.
    -DBUILD_SHARED_LIBS=OFF
)

fetch() {
    local name="$1" repo="$2" tag="$3"
    if [ ! -d "$BUILD/$name" ]; then
        echo "==> fetching $name $tag"
        git clone --depth 1 --branch "$tag" "$repo" "$BUILD/$name"
    fi
}

if [ "${SKIP_SDL:-0}" != "1" ]; then
    echo "==> stage 1/2: SDL3 for the simulator"
    fetch SDL https://github.com/libsdl-org/SDL.git "$SDL_TAG"
    cmake -S "$BUILD/SDL" -B "$BUILD/SDL-build" "${cmake_sim_args[@]}" \
        -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
    cmake --build "$BUILD/SDL-build" --target install

    echo "==> stage 1/2: SDL3_image for the simulator"
    fetch SDL_image https://github.com/libsdl-org/SDL_image.git "$SDL_IMAGE_TAG"
    cmake -S "$BUILD/SDL_image" -B "$BUILD/SDL_image-build" "${cmake_sim_args[@]}" \
        -DSDLIMAGE_SHARED=OFF -DSDLIMAGE_STATIC=ON \
        -DSDLIMAGE_DEPS_SHARED=OFF \
        -DSDLIMAGE_SAMPLES=OFF -DSDLIMAGE_TESTS=OFF \
        -DSDLIMAGE_JXL=OFF -DSDLIMAGE_AVIF=OFF -DSDLIMAGE_TIF=OFF \
        -DSDLIMAGE_WEBP=OFF
    cmake --build "$BUILD/SDL_image-build" --target install

    # Not optional, despite the iOS branch of Dependencies.cmake reading as if
    # it were: blkdev_cdimage.cpp includes <FLAC/all.h> unconditionally via
    # archivers/chd, so without it there is no CD32 and no CDTV.
    echo "==> stage 1/2: FLAC for the simulator"
    fetch flac https://github.com/xiph/flac.git "$FLAC_TAG"
    cmake -S "$BUILD/flac" -B "$BUILD/flac-build" "${cmake_sim_args[@]}" \
        -DBUILD_PROGRAMS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF \
        -DBUILD_DOCS=OFF -DINSTALL_MANPAGES=OFF -DWITH_OGG=OFF
    cmake --build "$BUILD/flac-build" --target install

    # Same story: specialmonitors.cpp includes png.h unconditionally for
    # screenshots and specialmonitor output. zlib comes from the SDK.
    echo "==> stage 1/2: libpng for the simulator"
    fetch libpng https://github.com/pnggroup/libpng.git "$LIBPNG_TAG"
    cmake -S "$BUILD/libpng" -B "$BUILD/libpng-build" "${cmake_sim_args[@]}" \
        -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF \
        -DPNG_FRAMEWORK=OFF
    cmake --build "$BUILD/libpng-build" --target install
else
    echo "==> stage 1/2: skipped (SKIP_SDL=1)"
fi

echo "==> stage 2/2: the emulator core"
# Identical option set to the device build. Anything that differs between the
# two slices is a difference the simulator cannot tell you about.
cmake -S "$PROJ" -B "$BUILD/core" "${cmake_sim_args[@]}" \
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

OUT="$PROJ/native/ios/out-simulator"
mkdir -p "$OUT"
find "$BUILD/core" -name "libuae4arm*.dylib" -exec cp -v {} "$OUT/" \;

# Prove it is what it claims before anything downstream trusts it: a device
# slice copied here by accident fails at dlopen, on a simulator, at runtime --
# the slowest possible place to find out.
for lib in "$OUT"/*.dylib; do
    if vtool -show-build "$lib" | grep -q "platform IOSSIMULATOR"; then
        echo "    ok: $(basename "$lib") is a simulator binary"
    else
        echo "error: $(basename "$lib") is NOT a simulator binary:" >&2
        vtool -show-build "$lib" | sed 's/^/       /' >&2
        exit 1
    fi
done

ls -lh "$OUT"
echo "==> done"
