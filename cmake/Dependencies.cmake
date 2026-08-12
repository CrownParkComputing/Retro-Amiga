if (USE_OPENGL)
    target_compile_definitions(${PROJECT_NAME} PRIVATE USE_OPENGL)
    if(IOS)
        # OpenGLES comes in as a framework via AMIBERRY_PLATFORM_LIBS.
        target_compile_definitions(${PROJECT_NAME} PRIVATE USE_GLES3)
    elseif(ANDROID)
        target_compile_definitions(${PROJECT_NAME} PRIVATE USE_GLES3)
        target_link_libraries(${PROJECT_NAME} PRIVATE GLESv3 EGL)
    elseif(USE_GLES)
        target_compile_definitions(${PROJECT_NAME} PRIVATE USE_GLES3)
        target_link_libraries(${PROJECT_NAME} PRIVATE GLESv2 EGL)
    else()
        find_package(OpenGL REQUIRED)
        target_link_libraries(${PROJECT_NAME} PRIVATE OpenGL::GL)
    endif()
endif ()

if (USE_VULKAN)
    target_compile_definitions(${PROJECT_NAME} PRIVATE USE_VULKAN)
    target_include_directories(${PROJECT_NAME} PRIVATE ${CMAKE_SOURCE_DIR}/external/VulkanMemoryAllocator/include)
    find_package(Vulkan REQUIRED)
    target_link_libraries(${PROJECT_NAME} PRIVATE Vulkan::Vulkan)
    message(STATUS "Vulkan renderer enabled (experimental)")
    if (CMAKE_BUILD_TYPE STREQUAL "Debug")
        message(STATUS "  Vulkan validation layers will be requested (Debug build)")
    endif()
endif ()

# SDL3's static lib exports a dependency on -lGLESv2, a Linux library name.
# iOS provides GLES as -framework OpenGLES (linked via AMIBERRY_PLATFORM_LIBS),
# so give the linker an empty target of that name to resolve against.
if(IOS AND NOT TARGET GLESv2)
    add_library(GLESv2 INTERFACE IMPORTED)
endif()

include(FindHelper)

# SDL3
target_compile_definitions(${PROJECT_NAME} PRIVATE USE_SDL3)
message(STATUS "Using SDL3")

include(FetchContent)

if(ANDROID)
    # Android doesn't provide ALSA. Disable ALSA backends in bundled deps that try to detect it.
    set(SDL_ALSA OFF CACHE BOOL "Disable ALSA for Android" FORCE)
    set(SDL_ALSA_SHARED OFF CACHE BOOL "Disable ALSA shared loading for Android" FORCE)
    set(DEFAULT_OUTPUT_MODULE "" CACHE STRING "Disable mpg123 default output module selection" FORCE)

    # -------------------------------------------------------------------------
    # Android: build third-party deps from source via FetchContent (pinned tags)
    # -------------------------------------------------------------------------
    # Note: Desktop builds use system packages (see non-ANDROID branch below).
    set(FETCHCONTENT_UPDATES_DISCONNECTED ON)

    # SDL3 / SDL3_image (built from source on Android)
    option(USE_SDL3_IMAGE_JXL "Enable JPEG XL (JPEG-XL) image format support in SDL3_image" OFF)
    FetchContent_Declare(
        sdl3
        GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
        GIT_TAG        release-3.4.4
    )
    FetchContent_Declare(
        sdl3_image
        GIT_REPOSITORY https://github.com/libsdl-org/SDL_image.git
        GIT_TAG        release-3.4.2
    )

    # Zstd
    set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "Build zstd programs" FORCE)
    set(ZSTD_BUILD_SHARED OFF CACHE BOOL "Build zstd shared lib" FORCE)
    set(ZSTD_BUILD_STATIC ON CACHE BOOL "Build zstd static lib" FORCE)
    FetchContent_Declare(
        zstd
        GIT_REPOSITORY https://github.com/facebook/zstd.git
        GIT_TAG        v1.5.6
        SOURCE_SUBDIR  build/cmake
    )

    # FLAC
    set(BUILD_PROGRAMS OFF CACHE BOOL "Build and install programs" FORCE)
    set(BUILD_EXAMPLES OFF CACHE BOOL "Build and install examples" FORCE)
    set(BUILD_TESTING OFF CACHE BOOL "Build tests" FORCE)
    set(BUILD_DOCS OFF CACHE BOOL "Build and install doxygen documents" FORCE)
    set(INSTALL_MANPAGES OFF CACHE BOOL "Install MAN pages" FORCE)
    set(WITH_OGG OFF CACHE BOOL "ogg support" FORCE)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libs" FORCE)
    FetchContent_Declare(
        flac
        GIT_REPOSITORY https://github.com/xiph/flac.git
        GIT_TAG        1.5.0
    )

    # mpg123 (only if enabled)
    if(USE_MPG123)
        set(BUILD_PROGRAMS OFF CACHE BOOL "Build programs" FORCE)
        set(BUILD_LIBOUT123 OFF CACHE BOOL "Build libout123" FORCE)
        set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libs" FORCE)
        FetchContent_Declare(
            mpg123
            # madebr/mpg123 is a mirror of the upstream SVN repo but does not publish git tags.
            # Pin to a specific commit for reproducible builds.
            GIT_REPOSITORY https://github.com/madebr/mpg123.git
            GIT_TAG        a06133928e6518bd65314c9cea12ccb5588703e9
        )
    endif()

    # libpng
    set(PNG_SHARED OFF CACHE BOOL "Build shared lib" FORCE)
    set(PNG_STATIC ON CACHE BOOL "Build static lib" FORCE)
    set(PNG_TESTS OFF CACHE BOOL "Build tests" FORCE)
    FetchContent_Declare(
        libpng
        GIT_REPOSITORY https://github.com/pnggroup/libpng.git
        GIT_TAG        v1.6.43
    )

    # mbedTLS (SSL backend for curl — Android NDK doesn't ship OpenSSL)
    set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
    set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
    set(MBEDTLS_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
    set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
    set(USE_STATIC_MBEDTLS_LIBRARY ON CACHE BOOL "" FORCE)
    FetchContent_Declare(
        mbedtls
        GIT_REPOSITORY https://github.com/Mbed-TLS/mbedtls.git
        GIT_TAG        v3.6.3
    )

    # libcurl
    set(BUILD_CURL_EXE OFF CACHE BOOL "" FORCE)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(CURL_USE_OPENSSL OFF CACHE BOOL "" FORCE)
    set(CURL_USE_MBEDTLS ON CACHE BOOL "" FORCE)
    set(CURL_USE_LIBPSL OFF CACHE BOOL "" FORCE)
    set(USE_LIBIDN2 OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(
        curl
        GIT_REPOSITORY https://github.com/curl/curl.git
        GIT_TAG        curl-8_11_1
    )

    # nlohmann-json (header-only)
    set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(
        nlohmann_json
        GIT_REPOSITORY https://github.com/nlohmann/json.git
        GIT_TAG        v3.11.3
    )

    # Materialize mbedTLS first so curl can find it
    FetchContent_GetProperties(mbedtls)
    if(NOT mbedtls_POPULATED)
        FetchContent_Populate(mbedtls)
        add_subdirectory(${mbedtls_SOURCE_DIR} ${mbedtls_BINARY_DIR} EXCLUDE_FROM_ALL)
    endif()
    # Pre-set cache vars as FILE PATHS (not target names) so curl's
    # install(EXPORT CURLTargets) doesn't pull mbedtls targets into
    # the export set — file-path link deps don't need export entries.
    set(MBEDTLS_INCLUDE_DIR "${mbedtls_SOURCE_DIR}/include" CACHE PATH "" FORCE)
    set(MBEDTLS_LIBRARY "${mbedtls_BINARY_DIR}/library/libmbedtls.a" CACHE FILEPATH "" FORCE)
    set(MBEDX509_LIBRARY "${mbedtls_BINARY_DIR}/library/libmbedx509.a" CACHE FILEPATH "" FORCE)
    set(MBEDCRYPTO_LIBRARY "${mbedtls_BINARY_DIR}/library/libmbedcrypto.a" CACHE FILEPATH "" FORCE)

    # Materialize curl
    FetchContent_GetProperties(curl)
    if(NOT curl_POPULATED)
        FetchContent_Populate(curl)
        add_subdirectory(${curl_SOURCE_DIR} ${curl_BINARY_DIR} EXCLUDE_FROM_ALL)
    endif()
    # File-path linking skips automatic target dependency tracking,
    # so explicitly ensure mbedTLS is built before curl links against it.
    if(TARGET libcurl_static)
        add_dependencies(libcurl_static mbedtls mbedx509 mbedcrypto)
    elseif(TARGET libcurl)
        add_dependencies(libcurl mbedtls mbedx509 mbedcrypto)
    endif()

    # SDL3_image options (set before MakeAvailable so they take effect)
    # (removed - using cache variables instead)
    if(NOT USE_SDL3_IMAGE_JXL)
        set(SDL_IMAGE_JXL OFF CACHE BOOL "Disable JPEG XL support in SDL3_image" FORCE)
    endif()

    # Materialize remaining deps (order matters: SDL first for *_image)
    if(USE_MPG123)
        FetchContent_MakeAvailable(sdl3 sdl3_image flac mpg123 libpng zstd nlohmann_json)
    else()
        FetchContent_MakeAvailable(sdl3 sdl3_image flac libpng zstd nlohmann_json)
    endif()

    if(TARGET FLAC)
        # On Android armeabi-v7a, FLAC's compat remaps can conflict with bionic stdio prototypes.
        target_compile_definitions(FLAC PRIVATE HAVE_FSEEKO=1 HAVE_FTELLO=1)
    endif()

    # Make zstd discoverable for the rest of this file (later FindHelper/pkg-config logic).
    if(TARGET libzstd_static)
        set(ZSTD_FOUND TRUE)
        set(ZSTD_LIBRARIES libzstd_static)
        if(EXISTS "${zstd_SOURCE_DIR}/lib")
            set(ZSTD_INCLUDE_DIRS "${zstd_SOURCE_DIR}/lib")
        endif()
    elseif(TARGET zstd)
        set(ZSTD_FOUND TRUE)
        set(ZSTD_LIBRARIES zstd)
        if(EXISTS "${zstd_SOURCE_DIR}/lib")
            set(ZSTD_INCLUDE_DIRS "${zstd_SOURCE_DIR}/lib")
        endif()
    endif()

    # --- Android link hygiene ------------------------------------------------
    # Some upstream CMake projects can propagate a raw "SDL3" or "pthread"
    # library name via INTERFACE properties.
    function(amiberry_android_sanitize_target _tgt)
        if(NOT TARGET ${_tgt})
            return()
        endif()

        # If this is an ALIAS target (e.g. SDL3::SDL3), resolve to the real target.
        get_target_property(_aliased ${_tgt} ALIASED_TARGET)
        if(_aliased)
            set(_tgt ${_aliased})
        else()
            set(_tgt ${_tgt})
        endif()

        foreach(_prop IN ITEMS INTERFACE_LINK_LIBRARIES INTERFACE_LINK_OPTIONS)
            get_target_property(_val ${_tgt} ${_prop})
            if(_val)
                # Remove raw library names and common flag spellings.
                list(REMOVE_ITEM _val SDL3 SDL3_image pthread -lSDL3 -lSDL3_image -pthread)
                set_target_properties(${_tgt} PROPERTIES ${_prop} "${_val}")
            endif()
        endforeach()
    endfunction()

    # -------------------------------------------------------------------------

    # ZLIB is usually available in NDK
    find_package(ZLIB REQUIRED)

    # Link SDL3 + extensions
    # Use real CMake targets to avoid generating raw '-lSDL3' flags on Android.
    set(AMIBERRY_SDL_TARGET "")
    if(TARGET SDL3::SDL3)
        set(AMIBERRY_SDL_TARGET SDL3::SDL3)
    elseif(TARGET SDL3-static)
        set(AMIBERRY_SDL_TARGET SDL3-static)
    elseif(TARGET SDL3)
        set(AMIBERRY_SDL_TARGET SDL3)
    endif()
    if(AMIBERRY_SDL_TARGET STREQUAL "")
        message(FATAL_ERROR "SDL3 target not found (expected SDL3::SDL3, SDL3-static, or SDL3)")
    endif()

    # Resolve SDL3_image target (shared or static depending on BUILD_SHARED_LIBS)
    set(AMIBERRY_SDL_IMAGE_TARGET "")
    if(TARGET SDL3_image::SDL3_image)
        set(AMIBERRY_SDL_IMAGE_TARGET SDL3_image::SDL3_image)
    elseif(TARGET SDL3_image-static)
        set(AMIBERRY_SDL_IMAGE_TARGET SDL3_image-static)
    elseif(TARGET SDL3_image)
        set(AMIBERRY_SDL_IMAGE_TARGET SDL3_image)
    endif()

    # Resolve alias to real target for modification (target_link_libraries, sanitize)
    set(_SDL_IMAGE_REAL_TARGET ${AMIBERRY_SDL_IMAGE_TARGET})
    if(NOT _SDL_IMAGE_REAL_TARGET STREQUAL "")
        get_target_property(_aliased ${_SDL_IMAGE_REAL_TARGET} ALIASED_TARGET)
        if(_aliased)
            set(_SDL_IMAGE_REAL_TARGET ${_aliased})
        endif()
        target_link_libraries(${_SDL_IMAGE_REAL_TARGET} PRIVATE ${AMIBERRY_SDL_TARGET})
    endif()

    # Sanitize known SDL-related targets so they can't inject raw -lSDL3/-pthread
    amiberry_android_sanitize_target(${AMIBERRY_SDL_IMAGE_TARGET})
    amiberry_android_sanitize_target(${AMIBERRY_SDL_TARGET})

    target_link_libraries(${PROJECT_NAME} PRIVATE ${AMIBERRY_SDL_TARGET} ${AMIBERRY_SDL_IMAGE_TARGET})
    target_link_libraries(${PROJECT_NAME} PRIVATE CURL::libcurl nlohmann_json::nlohmann_json)

    # -------------------------------------------------------------------------
    # libopenmpt - MOD/XM/S3M/IT tracker playback for the in-app mod player and
    # the boot intro's music. Upstream ships no top-level CMakeLists (their own
    # build is a custom Makefile/premake setup), so this hand-builds the same
    # source manifest as their own build/android_ndk/Android.mk "openmpt"
    # module, minus the optional external codecs (mpg123/ogg/vorbis/minimp3/
    # zlib) we don't need for plain tracker modules.
    FetchContent_Declare(
        openmpt
        GIT_REPOSITORY https://github.com/OpenMPT/openmpt.git
        GIT_TAG        libopenmpt-0.7.19
    )
    FetchContent_GetProperties(openmpt)
    if(NOT openmpt_POPULATED)
        FetchContent_Populate(openmpt)
    endif()

    set(OPENMPT_SOURCES
        common/ComponentManager.cpp
        common/Logging.cpp
        common/mptFileIO.cpp
        common/mptFileTemporary.cpp
        common/mptFileType.cpp
        common/mptPathString.cpp
        common/mptRandom.cpp
        common/mptStringBuffer.cpp
        common/mptTime.cpp
        common/Profiler.cpp
        common/serialization_utils.cpp
        common/version.cpp
        libopenmpt/libopenmpt_c.cpp
        libopenmpt/libopenmpt_cxx.cpp
        libopenmpt/libopenmpt_impl.cpp
        libopenmpt/libopenmpt_ext_impl.cpp
        soundlib/AudioCriticalSection.cpp
        soundlib/ContainerMMCMP.cpp
        soundlib/ContainerPP20.cpp
        soundlib/ContainerUMX.cpp
        soundlib/ContainerXPK.cpp
        soundlib/Dlsbank.cpp
        soundlib/Fastmix.cpp
        soundlib/InstrumentExtensions.cpp
        soundlib/ITCompression.cpp
        soundlib/ITTools.cpp
        soundlib/Load_667.cpp
        soundlib/Load_669.cpp
        soundlib/Load_amf.cpp
        soundlib/Load_ams.cpp
        soundlib/Load_c67.cpp
        soundlib/Load_dbm.cpp
        soundlib/Load_digi.cpp
        soundlib/Load_dmf.cpp
        soundlib/Load_dsm.cpp
        soundlib/Load_dsym.cpp
        soundlib/Load_dtm.cpp
        soundlib/Load_far.cpp
        soundlib/Load_fmt.cpp
        soundlib/Load_gdm.cpp
        soundlib/Load_gt2.cpp
        soundlib/Load_imf.cpp
        soundlib/Load_it.cpp
        soundlib/Load_itp.cpp
        soundlib/load_j2b.cpp
        soundlib/Load_mdl.cpp
        soundlib/Load_med.cpp
        soundlib/Load_mid.cpp
        soundlib/Load_mo3.cpp
        soundlib/Load_mod.cpp
        soundlib/Load_mt2.cpp
        soundlib/Load_mtm.cpp
        soundlib/Load_mus_km.cpp
        soundlib/Load_okt.cpp
        soundlib/Load_plm.cpp
        soundlib/Load_psm.cpp
        soundlib/Load_ptm.cpp
        soundlib/Load_s3m.cpp
        soundlib/Load_sfx.cpp
        soundlib/Load_stm.cpp
        soundlib/Load_stp.cpp
        soundlib/Load_symmod.cpp
        soundlib/Load_ult.cpp
        soundlib/Load_uax.cpp
        soundlib/Load_wav.cpp
        soundlib/Load_xm.cpp
        soundlib/Load_xmf.cpp
        soundlib/Message.cpp
        soundlib/MIDIEvents.cpp
        soundlib/MIDIMacros.cpp
        soundlib/MixerLoops.cpp
        soundlib/MixerSettings.cpp
        soundlib/MixFuncTable.cpp
        soundlib/ModChannel.cpp
        soundlib/modcommand.cpp
        soundlib/ModInstrument.cpp
        soundlib/ModSample.cpp
        soundlib/ModSequence.cpp
        soundlib/modsmp_ctrl.cpp
        soundlib/mod_specifications.cpp
        soundlib/MPEGFrame.cpp
        soundlib/OggStream.cpp
        soundlib/OPL.cpp
        soundlib/Paula.cpp
        soundlib/patternContainer.cpp
        soundlib/pattern.cpp
        soundlib/RowVisitor.cpp
        soundlib/S3MTools.cpp
        soundlib/SampleFormats.cpp
        soundlib/SampleFormatBRR.cpp
        soundlib/SampleFormatFLAC.cpp
        soundlib/SampleFormatMediaFoundation.cpp
        soundlib/SampleFormatMP3.cpp
        soundlib/SampleFormatOpus.cpp
        soundlib/SampleFormatSFZ.cpp
        soundlib/SampleFormatVorbis.cpp
        soundlib/SampleIO.cpp
        soundlib/Sndfile.cpp
        soundlib/Snd_flt.cpp
        soundlib/Snd_fx.cpp
        soundlib/Sndmix.cpp
        soundlib/SoundFilePlayConfig.cpp
        soundlib/UMXTools.cpp
        soundlib/UpgradeModule.cpp
        soundlib/Tables.cpp
        soundlib/Tagging.cpp
        soundlib/TinyFFT.cpp
        soundlib/tuningCollection.cpp
        soundlib/tuning.cpp
        soundlib/WAVTools.cpp
        soundlib/WindowedFIR.cpp
        soundlib/XMTools.cpp
        soundlib/plugins/DigiBoosterEcho.cpp
        soundlib/plugins/dmo/DMOPlugin.cpp
        soundlib/plugins/dmo/DMOUtils.cpp
        soundlib/plugins/dmo/Chorus.cpp
        soundlib/plugins/dmo/Compressor.cpp
        soundlib/plugins/dmo/Distortion.cpp
        soundlib/plugins/dmo/Echo.cpp
        soundlib/plugins/dmo/Flanger.cpp
        soundlib/plugins/dmo/Gargle.cpp
        soundlib/plugins/dmo/I3DL2Reverb.cpp
        soundlib/plugins/dmo/ParamEq.cpp
        soundlib/plugins/dmo/WavesReverb.cpp
        soundlib/plugins/LFOPlugin.cpp
        soundlib/plugins/PluginManager.cpp
        soundlib/plugins/PlugInterface.cpp
        soundlib/plugins/SymMODEcho.cpp
        sounddsp/AGC.cpp
        sounddsp/DSP.cpp
        sounddsp/EQ.cpp
        sounddsp/Reverb.cpp
    )
    list(TRANSFORM OPENMPT_SOURCES PREPEND "${openmpt_SOURCE_DIR}/")

    add_library(openmpt STATIC ${OPENMPT_SOURCES})
    target_include_directories(openmpt PRIVATE ${openmpt_SOURCE_DIR} ${openmpt_SOURCE_DIR}/src ${openmpt_SOURCE_DIR}/common)
    target_include_directories(openmpt PUBLIC ${openmpt_SOURCE_DIR})
    target_compile_definitions(openmpt PRIVATE LIBOPENMPT_BUILD)
    set_target_properties(openmpt PROPERTIES
        CXX_STANDARD 17
        CXX_STANDARD_REQUIRED ON
        POSITION_INDEPENDENT_CODE ON
    )
    target_compile_options(openmpt PRIVATE -fexceptions -frtti -fvisibility=hidden -Wno-unused-parameter)

    # The mod player's JNI bridge is its OWN small shared library (libmodplayer.so), not part of
    # libuae4arm.so. Uae4ArmEmulatorActivity/the emulation core run in a separate ":sdl" process
    # (see AndroidManifest.xml) where libuae4arm.so gets loaded - MainActivity's process (where
    # ModPlayer/the intro/Configurations actually run) never loads it. Bundling openmpt into
    # libuae4arm.so left its JNI symbols unreachable from the process that needs them
    # (UnsatisfiedLinkError at runtime, symbol present in the .so but never loaded). A separate
    # library that MainActivity's process explicitly System.loadLibrary()s avoids that entirely,
    # and keeps the whole emulation core's static init out of the main app process besides.
    add_library(modplayer SHARED ${CMAKE_SOURCE_DIR}/src/osdep/mod_player_jni.cpp)
    target_link_libraries(modplayer PRIVATE openmpt log)
    set_target_properties(modplayer PROPERTIES
        CXX_STANDARD 17
        CXX_STANDARD_REQUIRED ON
    )

    # Defensive: ensure we never add raw SDL3/pthread libraries or flags on Android.
    # Some transitive/legacy paths may still append plain library names or link options.
    foreach(_prop IN ITEMS LINK_LIBRARIES LINK_OPTIONS INTERFACE_LINK_LIBRARIES INTERFACE_LINK_OPTIONS)
        get_target_property(_amiberry_val ${PROJECT_NAME} ${_prop})
        if(_amiberry_val)
            list(REMOVE_ITEM _amiberry_val SDL3 pthread -lSDL3 -lSDL3_image -pthread)
            set_target_properties(${PROJECT_NAME} PROPERTIES ${_prop} "${_amiberry_val}")
        endif()
    endforeach()

    # mpg123 include path (subproject)
    if(USE_MPG123 AND EXISTS "${mpg123_SOURCE_DIR}/src/include")
        target_include_directories(${PROJECT_NAME} PRIVATE "${mpg123_SOURCE_DIR}/src/include")
    endif()
    # libpng (headers are exported by the target, but keep compatible include behavior)
    if(EXISTS "${libpng_SOURCE_DIR}")
        target_include_directories(${PROJECT_NAME} PRIVATE "${libpng_SOURCE_DIR}")
    endif()
    # pnglibconf.h is generated into libpng's binary dir; include it so png.h can find it.
    if(EXISTS "${libpng_BINARY_DIR}/pnglibconf.h")
        target_include_directories(${PROJECT_NAME} PRIVATE "${libpng_BINARY_DIR}")
    endif()
    # zstd headers
    if(EXISTS "${zstd_SOURCE_DIR}/lib")
        target_include_directories(${PROJECT_NAME} PRIVATE "${zstd_SOURCE_DIR}/lib")
    endif()


    # --- PortMidi ---
    if(USE_PORTMIDI)
        # PortMidi decides whether to use ALSA based on the LINUX_DEFINES cache var.
        # On Android, ALSA is unavailable, so force PortMidi to build with PMNULL.
        set(LINUX_DEFINES "PMNULL" CACHE STRING "Disable PortMidi ALSA backend on Android" FORCE)

        # PortTime: PortMidi's "ptlinux" backend includes sys/timeb.h which is not available
        # on Android NDK. Force PortTime to use the null backend for Android builds.
        set(PT_BACKEND "ptnull" CACHE STRING "PortTime backend" FORCE)

        FetchContent_Declare(
            portmidi
            GIT_REPOSITORY https://github.com/PortMidi/portmidi.git
            GIT_TAG        v2.0.4
            # FetchContent may download a tarball snapshot. Don't rely on git being available
            # in <SOURCE_DIR>. Apply Android fixes via a deterministic CMake script.
            PATCH_COMMAND  ${CMAKE_COMMAND} -E echo "Fixing PortMidi for Android" &&
                           ${CMAKE_COMMAND} -DPORTMIDI_SOURCE_DIR=<SOURCE_DIR>
                                          -DAMIBERRY_SOURCE_DIR=${CMAKE_SOURCE_DIR}
                                          -P "${CMAKE_SOURCE_DIR}/cmake/portmidi_fix_android.cmake"
         )
         FetchContent_MakeAvailable(portmidi)

        target_link_libraries(${PROJECT_NAME} PRIVATE portmidi)

        # Amiberry includes porttime.h directly; ensure PortMidi's porttime headers are visible.
        if (EXISTS "${portmidi_SOURCE_DIR}/porttime/porttime.h")
            target_include_directories(${PROJECT_NAME} PRIVATE "${portmidi_SOURCE_DIR}/porttime")
        endif()

        # Amiberry includes portmidi.h directly; it's located in PortMidi's pm_common directory.
        if (EXISTS "${portmidi_SOURCE_DIR}/pm_common/portmidi.h")
            target_include_directories(${PROJECT_NAME} PRIVATE "${portmidi_SOURCE_DIR}/pm_common")
        endif()
    endif()

    # --- ENet ---
    if(USE_LIBENET)
        FetchContent_Declare(
            enet
            GIT_REPOSITORY https://github.com/lsalzman/enet
            GIT_TAG        v1.3.18
        )
        # ENet doesn't export a target in older versions, so we might need to be careful
        # But lsalzman/enet usually has CMake support.
        FetchContent_MakeAvailable(enet) 
        target_link_libraries(${PROJECT_NAME} PRIVATE enet)

        # Ensure the enet/enet.h header is visible when compiling amiberry on Android.
        if (EXISTS "${enet_SOURCE_DIR}/include/enet/enet.h")
            target_include_directories(${PROJECT_NAME} PRIVATE "${enet_SOURCE_DIR}/include")
        endif()
    endif()

    # --- LibSerialPort ---
    if(USE_LIBSERIALPORT)
        # Use a CMake-friendly fork
        FetchContent_Declare(
            libserialport
            GIT_REPOSITORY https://github.com/scottmudge/libserialport-cmake
            GIT_TAG        c82d28deb05185df8c4dafea96dd520a3c0db7c9
            PATCH_COMMAND  ${CMAKE_COMMAND} -E echo "Fixing libserialport for Android" &&
                           ${CMAKE_COMMAND} -DLIBSERIALPORT_SOURCE_DIR=<SOURCE_DIR>
                                          -P "${CMAKE_SOURCE_DIR}/cmake/libserialport_fix_android.cmake"
        )
        FetchContent_MakeAvailable(libserialport)

        # Link to the produced CMake target to avoid raw '-lserialport' flags.
        # scottmudge/libserialport-cmake defines project(serialport) and creates:
        #   - serialport-static
        #   - serialport-shared
        # Other libserialport setups may use different target names, so keep fallbacks.
        set(AMIBERRY_LIBSERIALPORT_TARGET "")
        if(TARGET serialport-static)
            set(AMIBERRY_LIBSERIALPORT_TARGET serialport-static)
        elseif(TARGET serialport)
            set(AMIBERRY_LIBSERIALPORT_TARGET serialport)
        elseif(TARGET serialport-shared)
            set(AMIBERRY_LIBSERIALPORT_TARGET serialport-shared)
        elseif(TARGET libserialport)
            set(AMIBERRY_LIBSERIALPORT_TARGET libserialport)
        elseif(TARGET libserialport-static)
            set(AMIBERRY_LIBSERIALPORT_TARGET libserialport-static)
        endif()

        if(AMIBERRY_LIBSERIALPORT_TARGET STREQUAL "")
            message(FATAL_ERROR "libserialport target was not created (tried: serialport-static, serialport-shared, serialport, libserialport, libserialport-static)")
        endif()

        target_link_libraries(${PROJECT_NAME} PRIVATE ${AMIBERRY_LIBSERIALPORT_TARGET})

        # The serialport target doesn't consistently propagate public include dirs across toolchains.
        # Ensure the header (<libserialport.h>) is visible when compiling amiberry on Android.
        if (EXISTS "${libserialport_SOURCE_DIR}/libserialport.h")
            target_include_directories(${PROJECT_NAME} PRIVATE "${libserialport_SOURCE_DIR}")
        elseif (EXISTS "${libserialport_SOURCE_DIR}/libserialport")
            target_include_directories(${PROJECT_NAME} PRIVATE "${libserialport_SOURCE_DIR}")
        endif()
    endif()

elseif(IOS)
    # sysconfig.h derives this from TargetConditionals.h, but only in
    # translation units that include it. Headers such as gl_platform.h test
    # AMIBERRY_IOS on their own and would otherwise take the Android/Linux
    # branch, so define it for the whole target.
    target_compile_definitions(${PROJECT_NAME} PRIVATE AMIBERRY_IOS)

    # SDL3 and SDL3_image must be pre-built and reachable via CMAKE_FIND_ROOT_PATH.
    # Most optional codecs and network libraries are unavailable or pointless here:
    # no FLAC or mpg123 (no CD audio ripping on a phone) and no CURL (self-update
    # is disabled, and the App Store would not allow it anyway).
    find_package(SDL3 CONFIG REQUIRED)
    find_package(SDL3_image CONFIG REQUIRED)
    find_package(ZLIB REQUIRED)
    # Required, not optional: specialmonitors.cpp includes png.h unconditionally.
    find_package(PNG REQUIRED)
    target_link_libraries(${PROJECT_NAME} PRIVATE PNG::PNG)

    # CHD CD images carry FLAC-compressed audio tracks and archivers/chd
    # includes <FLAC/all.h> unconditionally, so this is required for CD32 and
    # CDTV support rather than for ripping.
    find_package(FLAC REQUIRED)

    find_package(nlohmann_json CONFIG QUIET)
    if(NOT nlohmann_json_FOUND)
        FetchContent_Declare(json
            GIT_REPOSITORY https://github.com/nlohmann/json.git
            GIT_TAG v3.11.3
            GIT_SHALLOW TRUE
        )
        set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
        FetchContent_MakeAvailable(json)
    endif()
    target_link_libraries(${PROJECT_NAME} PRIVATE nlohmann_json::nlohmann_json)
    target_link_libraries(${PROJECT_NAME} PRIVATE SDL3::SDL3 SDL3_image::SDL3_image)

else()
    # Desktop: system packages, as provided by apt, Homebrew or vcpkg.
    find_package(SDL3 CONFIG REQUIRED)
    find_package(SDL3_image CONFIG REQUIRED)
    # FLAC's exported config names Threads::Threads in its link interface, so
    # the target has to exist before find_package(FLAC) pulls that config in.
    find_package(Threads REQUIRED)
    find_package(FLAC REQUIRED)
    if(USE_MPG123)
        find_package(mpg123 REQUIRED)
        target_compile_definitions(${PROJECT_NAME} PRIVATE HAVE_MPG123)
    endif()
    find_package(PNG REQUIRED)
    find_package(ZLIB REQUIRED)
    find_package(CURL REQUIRED)
    find_package(nlohmann_json CONFIG REQUIRED)
    target_link_libraries(${PROJECT_NAME} PRIVATE SDL3::SDL3)
endif()

if (USE_ZSTD)
    target_compile_definitions(${PROJECT_NAME} PRIVATE USE_ZSTD)

    if(ANDROID)
        # Built from source via FetchContent above.
        if(TARGET libzstd_static)
            target_include_directories(${PROJECT_NAME} PRIVATE "${zstd_SOURCE_DIR}/lib")
            target_link_libraries(${PROJECT_NAME} PRIVATE libzstd_static)
        elseif(TARGET zstd)
            target_include_directories(${PROJECT_NAME} PRIVATE "${zstd_SOURCE_DIR}/lib")
            target_link_libraries(${PROJECT_NAME} PRIVATE zstd)
        else()
            message(STATUS "ZSTD enabled but zstd target was not created - CHD compressed disk images will not be supported")
        endif()
    else()
        find_helper(ZSTD libzstd zstd.h zstd)
        if(NOT ZSTD_FOUND)
            message(STATUS "ZSTD library not found - CHD compressed disk images will not be supported")
        else()
            target_include_directories(${PROJECT_NAME} PRIVATE ${ZSTD_INCLUDE_DIRS})
            target_link_libraries(${PROJECT_NAME} PRIVATE ${ZSTD_LIBRARIES})
        endif()
    endif()
endif ()

# On Android these three are built via FetchContent above and linked through
# their CMake targets; running find_helper there would inject a raw -l flag
# that the NDK cannot resolve.
if (USE_LIBSERIALPORT)
    target_compile_definitions(${PROJECT_NAME} PRIVATE USE_LIBSERIALPORT)
    if(NOT ANDROID)
        find_helper(LIBSERIALPORT libserialport libserialport.h serialport)
        if(TARGET serialport)
            target_link_libraries(${PROJECT_NAME} PRIVATE serialport)
        elseif(LIBSERIALPORT_FOUND AND LIBSERIALPORT_LIBRARIES)
            target_link_libraries(${PROJECT_NAME} PRIVATE ${LIBSERIALPORT_LIBRARIES})
        else()
            message(STATUS "LibSerialPort enabled but library was not found")
        endif()
    endif()
endif ()

if (USE_PORTMIDI)
    target_compile_definitions(${PROJECT_NAME} PRIVATE USE_PORTMIDI)
    if(NOT ANDROID)
        find_helper(PORTMIDI portmidi portmidi.h portmidi)
        if(TARGET portmidi)
            target_link_libraries(${PROJECT_NAME} PRIVATE portmidi)
        elseif(PORTMIDI_FOUND AND PORTMIDI_LIBRARIES)
            target_link_libraries(${PROJECT_NAME} PRIVATE ${PORTMIDI_LIBRARIES})
        else()
            message(STATUS "PortMidi enabled but library was not found")
        endif()
    endif()
endif ()

if (USE_LIBENET)
    target_compile_definitions(${PROJECT_NAME} PRIVATE USE_LIBENET)
    if(NOT ANDROID)
        find_helper(LIBENET libenet enet/enet.h enet)
        if(NOT LIBENET_FOUND)
            message(STATUS "LibENET library not found - network emulation will not be supported")
        else()
            target_include_directories(${PROJECT_NAME} PRIVATE ${LIBENET_INCLUDE_DIRS})
            target_link_libraries(${PROJECT_NAME} PRIVATE ${LIBENET_LIBRARIES})
        endif()
    endif()
endif ()

if (USE_PCEM)
    target_compile_definitions(${PROJECT_NAME} PRIVATE USE_PCEM)
endif ()

if (USE_PPC)
    target_compile_definitions(${PROJECT_NAME} PRIVATE WITH_PPC)
endif()

# The QEMU glue carries the SCSI/PCI device types that the NCR controllers are
# built from, so it has to be on whenever either emulator that needs it is.
if (USE_PCEM OR USE_PPC)
    target_compile_definitions(${PROJECT_NAME} PRIVATE WITH_QEMU_CPU)
endif()

# SDL3 include dirs: FetchContent builds may not provide SDL3::SDL3.
set(_SDL_INCLUDE_DIRS "")
if(TARGET SDL3::SDL3)
    get_target_property(_SDL_INCLUDE_DIRS SDL3::SDL3 INTERFACE_INCLUDE_DIRECTORIES)
elseif(TARGET SDL3-static)
    get_target_property(_SDL_INCLUDE_DIRS SDL3-static INTERFACE_INCLUDE_DIRECTORIES)
elseif(TARGET SDL3)
    get_target_property(_SDL_INCLUDE_DIRS SDL3 INTERFACE_INCLUDE_DIRECTORIES)
endif()
if(_SDL_INCLUDE_DIRS)
    target_include_directories(${PROJECT_NAME} PRIVATE ${_SDL_INCLUDE_DIRS})
endif()

# SDL3_image include dirs: the Android FetchContent build needs the include path
# for <SDL3_image/SDL_image.h>; packaged builds carry it on the imported target.
if(ANDROID AND DEFINED sdl3_image_SOURCE_DIR)
    target_include_directories(${PROJECT_NAME} PRIVATE "${sdl3_image_SOURCE_DIR}/include")
endif()

set(libmt32emu_SHARED FALSE)
add_subdirectory(external/mt32emu)
if(NOT IOS)
    # FloppyBridge is a dlopen'd plugin; iOS forbids loading unsigned code.
    add_subdirectory(external/floppybridge)
endif()
add_subdirectory(external/capsimage)

# On Android SDL3_image is already linked via the FetchContent target above.
if(ANDROID)
    set(_SDL_IMAGE_LIB "")
elseif(TARGET SDL3_image::SDL3_image)
    set(_SDL_IMAGE_LIB SDL3_image::SDL3_image)
elseif(SDL3_IMAGE_LIBRARIES)
    set(_SDL_IMAGE_LIB ${SDL3_IMAGE_LIBRARIES})
else()
    set(_SDL_IMAGE_LIB SDL3_image)
endif()

set(AMIBERRY_LIBS
        mt32emu
        ZLIB::ZLIB
        nlohmann_json::nlohmann_json
        ${CMAKE_DL_LIBS}
        ${_SDL_IMAGE_LIB}
)

# CURL is used for self-update (not available on iOS)
if(TARGET CURL::libcurl)
    list(APPEND AMIBERRY_LIBS CURL::libcurl)
    target_compile_definitions(${PROJECT_NAME} PRIVATE AMIBERRY_HAS_CURL)
elseif(CURL_FOUND)
    list(APPEND AMIBERRY_LIBS ${CURL_LIBRARIES})
    target_compile_definitions(${PROJECT_NAME} PRIVATE AMIBERRY_HAS_CURL)
endif()

if(TARGET FLAC::FLAC)
    list(APPEND AMIBERRY_LIBS FLAC::FLAC)
elseif(TARGET FLAC)
    list(APPEND AMIBERRY_LIBS FLAC)
elseif(FLAC_FOUND)
    list(APPEND AMIBERRY_LIBS ${FLAC_LIBRARIES})
endif()

if(TARGET PNG::PNG)
    list(APPEND AMIBERRY_LIBS PNG::PNG)
elseif(TARGET png_static)
    list(APPEND AMIBERRY_LIBS png_static)
elseif(TARGET png)
    list(APPEND AMIBERRY_LIBS png)
elseif(PNG_FOUND)
    list(APPEND AMIBERRY_LIBS ${PNG_LIBRARIES})
endif()

if(TARGET MPG123::libmpg123)
    list(APPEND AMIBERRY_LIBS MPG123::libmpg123)
elseif(TARGET libmpg123)
    list(APPEND AMIBERRY_LIBS libmpg123)
elseif(mpg123_FOUND)
    list(APPEND AMIBERRY_LIBS ${mpg123_LIBRARIES})
elseif(MPG123_FOUND)
    list(APPEND AMIBERRY_LIBS ${MPG123_LIBRARIES})
endif()

if(TARGET libzstd_static)
    list(APPEND AMIBERRY_LIBS libzstd_static)
elseif(TARGET zstd)
    list(APPEND AMIBERRY_LIBS zstd)
elseif(ZSTD_FOUND)
    list(APPEND AMIBERRY_LIBS ${ZSTD_LIBRARIES})
endif()

if(ANDROID)
    list(APPEND AMIBERRY_LIBS log android)
elseif(NOT WIN32)
    list(APPEND AMIBERRY_LIBS pthread)
else()
    # llvm-mingw (clang) on Windows does not auto-link winpthread.
    list(APPEND AMIBERRY_LIBS winpthread)
endif()

# Never link SDL by raw library name: every platform links it via its CMake
# target, and a stray -lSDL3 picks up the wrong one (or nothing) at link time.
list(REMOVE_ITEM AMIBERRY_LIBS SDL3)
if(ANDROID)
    list(REMOVE_ITEM AMIBERRY_LIBS pthread)
endif()

target_link_libraries(${PROJECT_NAME} PRIVATE ${AMIBERRY_LIBS})

# capsimage and floppybridge are plugins (not linked into amiberry) but are
# copied by post-build commands. Explicit dependencies ensure they are built.
if(IOS)
    add_dependencies(${PROJECT_NAME} capsimage)
else()
    add_dependencies(${PROJECT_NAME} floppybridge capsimage)
endif()

# Platform system libraries must come AFTER all other dependencies so that
# static libs (enet, etc.) can resolve their system library references.
if(AMIBERRY_PLATFORM_LIBS)
    target_link_libraries(${PROJECT_NAME} PRIVATE ${AMIBERRY_PLATFORM_LIBS})
endif()
