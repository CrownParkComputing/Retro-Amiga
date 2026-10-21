cmake_minimum_required(VERSION 3.16)

project(uae4arm
    VERSION 4.3.0
    LANGUAGES C CXX
    DESCRIPTION "UAE4ARM 2026 - Amiga emulator for Android"
    HOMEPAGE_URL "https://github.com/uae4arm-dev/uae4arm_2026"
)

# Prevent in-tree builds
if(CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_CURRENT_BINARY_DIR)
    message(FATAL_ERROR "In-tree builds are not supported. Use a separate build directory.")
endif()

# Set CMake module path
set(CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake ${CMAKE_MODULE_PATH})

# Feature options
option(USE_PCEM          "Use PCem for hardware emulation (no support for RISC-V)" ON)
option(USE_PPC           "Enable PowerPC accelerator board support" OFF)
option(USE_LIBSERIALPORT "Use LibSerialPort for serial port emulation" ON)
option(USE_LIBENET       "Use LibENET for network emulation" ON)
option(USE_PORTMIDI      "Use PortMidi for MIDI emulation" ON)
option(USE_ZSTD          "Use Zstandard for CHD compressed disk images" ON)
option(USE_OPENGL        "Use OpenGL for rendering" ON)
option(USE_GLES          "Use OpenGL ES instead of desktop OpenGL" ON)
option(USE_VULKAN        "Use Vulkan for rendering (experimental, mutually exclusive with USE_OPENGL)" OFF)
option(WITH_LTO          "Enable Link Time Optimization" OFF)
option(WITH_OPTIMIZE     "Enable GCC native CPU optimizations" OFF)

# Automatically disable PCem on architectures without a PCem backend
if(CMAKE_SYSTEM_PROCESSOR MATCHES "riscv" OR CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "riscv"
   OR CMAKE_SYSTEM_PROCESSOR MATCHES "loongarch" OR CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "loongarch")
    if(USE_PCEM)
        message(STATUS "Detected ${CMAKE_SYSTEM_PROCESSOR} architecture. Disabling USE_PCEM (no backend available).")
    else()
        message(STATUS "Detected ${CMAKE_SYSTEM_PROCESSOR} architecture. USE_PCEM already disabled.")
    endif()
    set(USE_PCEM OFF CACHE BOOL "Use PCem for hardware emulation (no backend for this architecture)" FORCE)
endif()

if(ANDROID)
    # Android 15+ (API 35) requires 16KB page size alignment for Play Store.
    # We apply it to all Android builds to ensure forward compatibility.
    add_link_options("-Wl,-z,max-page-size=16384")
endif()

# Vulkan and OpenGL are mutually exclusive rendering backends
if(USE_VULKAN AND USE_OPENGL)
    message(FATAL_ERROR "USE_VULKAN and USE_OPENGL are mutually exclusive. Please enable only one.")
endif()

# Pre-release version suffix (project version is set in project() above)
set(VERSION_PRE_RELEASE "" CACHE STRING "Pre-release version")

# Project identity
set(UPSTREAM_EMULATOR_NAME "Copperline")
set(PRODUCT_DISPLAY_NAME "Retro-Amiga")
set(PROJECT_COMPANY_NAME "UAE4Arm Team")
set(PROJECT_COMPANY_NAMESPACE "com.uae4arm2026")
# Legacy variable retained for existing packaging logic.
set(AMIBERRY_DISPLAY_NAME "${PRODUCT_DISPLAY_NAME}")

# Shared Android-native build configuration
include(GNUInstallDirs)
include(cmake/StandardProjectSettings.cmake)
include(cmake/SourceFiles.cmake)

if(ANDROID)
    # The texture JNI lives in a library of its own, NOT in a core. Both
    # cores export the same uae4arm_host_* surface, and Java_... symbols in
    # two loaded libraries race JNI's lazy binding -- whichever copy ART
    # found first would own the surface. This lib owns the entry points and
    # is told which core is running (nativeUseCore), then reaches it through
    # dlopen/dlsym. See native/amigatexture/amigatexture.cpp.
    add_library(amigatexture SHARED native/amigatexture/amigatexture.cpp)
    target_link_libraries(amigatexture PRIVATE android log)

    # The second core is a Rust cdylib, built by cargo-ndk straight into
    # jniLibs/ -- see the buildCopperlineCore task in
    # app/android/app/build.gradle.kts, which is what puts
    # libcopperline_ffi.so in the APK.
endif()

include(cmake/Dependencies.cmake)
