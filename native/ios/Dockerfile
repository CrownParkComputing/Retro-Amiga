# Build environment for the iOS core.
#
# mobaiapp/iosbox supplies the cross toolchain (clang targeting
# arm64-apple-ios, ld64.lld) and an iOS SDK mounted from the iosbox-sdk
# volume. It does not carry CMake or Ninja, which this core's build needs,
# nor the host tools its dependencies expect. Everything installed here runs
# on the host as ordinary amd64 packages; nothing targets iOS.
FROM mobaiapp/iosbox:latest

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        cmake ninja-build pkg-config file python3 \
    && rm -rf /var/lib/apt/lists/*
