# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Retro-Amiga (formerly working name uae4arm2026, folder renamed 2026-08-20):
a multiplatform Amiga emulator — a Flutter launcher (`app/`) over a stripped,
vendored Amiberry core (`src/`).
Targets Android, iOS, and Linux desktop. The core has **no GUI of its own**:
ImGui, the core-drawn on-screen pad and the core virtual keyboard are all
deleted; every control surface is the host's.

The per-directory `AGENTS.md` files describe the codebase **before** that
strip (ImGui panels, vkbd/, core overlays). Treat them as historical maps of
the vendored core's internals, not as current guidance.

Public repo (CrownParkComputing): **no AI attribution anywhere** — no
Co-Authored-By trailers, no "Generated with" lines, in commits or code.

## Commands

```sh
# Host-side checks — ALWAYS before any device build. Reproduces the
# phone-host lifecycle (dlopen core, run, quit from a thread, run again).
tools/check-core.sh                 # builds Linux core + runs all scenarios
SKIP_BUILD=1 tools/check-core.sh    # reuse existing build-linux/

# Flutter app
cd app && flutter analyze lib/ && flutter test
cd app && flutter test test/pad_layout_test.dart   # single test file
# flutter lives at ~/development/flutter/bin (not on default PATH)

# Linux core as a shared library (what check-core.sh drives)
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DUAE4ARM_CORE_LIBRARY=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build build-linux -j$(nproc)

# iOS (Docker cross-build via iosbox; produces an UNSIGNED IPA)
SKIP_SDL=1 tools/build-ios-core.sh   # core dylib -> native/ios/out/
tools/build-ios-app.sh               # Flutter app + core packaged as
                                     # Frameworks/libuae4arm.framework/

# Android
cd app && flutter build apk --release

# Linux desktop app
cd app && flutter build linux --release
```

iOS installs go through MobAI (HTTP API on `127.0.0.1:8686`), which re-signs
at install: `POST /devices/{id}/install-app` with `{"path": ..., "resign": true}`.
The signing session is an Apple ID login inside the MobAI app; "no valid
cached credentials" means it lapsed. `debug/launch` with a `logPath` captures
the device log — the breadcrumbs below are read from there.

## Architecture

Three layers, one narrow waist:

1. **Vendored core** (`src/`, ~1.1M lines of Amiberry/WinUAE): emulation,
   WHDLoad booter (`src/osdep/amiberry_whdbooter.cpp`), renderers. Built as a
   shared library for every host (see `cmake/SourceFiles.cmake`, gated on
   `ANDROID OR IOS OR UAE4ARM_CORE_LIBRARY`).

2. **Host API** (`src/osdep/uae4arm_host.{h,cpp}`): the only door between the
   core and any UI. Plain-C, `dlsym`-able. Inbound: run/quit/launch, raw
   Amiga keycodes (`uae4arm_host_send_key`), relative mouse, virtual pads
   (`uae4arm_host_pad_*` — registered as input devices indistinguishable from
   physical ones), floppy swap, pause, save states, ProTracker music player.
   New capability = new export here, never a platform-specific side channel.

3. **Flutter app** (`app/lib/`): launcher, guided config wizard, media
   library, settings. Platform hosts differ in shape:
   - **Android**: emulator runs in a separate `:sdl` process; a second
     FlutterEngine overlay (`app/lib/overlay_main.dart`) draws in-game
     controls over SDL's SurfaceView. SharedPreferences is per-process —
     cross-process state (pad layout) goes through files
     (`app/lib/data/pad_layout_store.dart`).
   - **iOS**: launcher and core share one process; the core runs **on the
     main thread** (SDL's UIKit backend requires it) and blocks Flutter while
     a game runs. In-game controls are therefore UIKit
     (`app/ios/Runner/EmulatorControls.swift`, `PadOverlayView.swift`,
     `AmigaKeyboardView.swift`, `TouchMouseView.swift`) in a pass-through
     window above SDL's. They read the same `pad_layout.json` the designer
     writes and feed the same host API.
   - **Linux**: single process, method channel implemented in
     `app/linux/runner/my_application.cc`.

### The single-run-statics landmine

The core was written to run once per process; the phone hosts run it many
times. Six shipped bugs came from statics surviving a run — SDL teardown
(iOS never calls `SDL_Quit`), a cached GL framebuffer id, the
`parse_cmdline` once-guard, the zvolume archive list, an SDL keymap probe in
`init_kb`, and a natmem reservation leaked by `munmap(addr, 0)`. **Any "the
second game breaks" symptom: suspect a static first.** The `write_log`
breadcrumbs (`startup:`, `filesys:`, `gfx:` prefixes) exist to name the
failing call from a device log — keep them. `tools/core-twice.c` /
`core-again.c` reproduce the lifecycle on Linux (software rendering: the
NVIDIA driver crashes on a second GL context in ways devices don't; JIT off:
no shipped host re-enters JIT in one process, and its translation cache
doesn't survive natmem moving).

### Media and provisioning

Everything arrives as zips dropped in the app's folder (on iOS, the app's
Documents via the Files app — the sandbox cannot see system Downloads).
`StartupImport` (`app/lib/data/startup_import.dart`) runs at launch and from
the wizard: scans, files by content (never filename), places Kickstarts
where the WHDLoad booter looks (`WHDBoot/save-data/Kickstarts`, names from
`WhdloadSupport.kickstartNames`), and deletes a zip once everything it
recognisably held is banked. WHDLoad's freely-distributable half (loader,
JST, AmiQuit, boot-data.zip, whdload_db.xml, skick `.RTB` tables) ships as
app assets (`app/assets/whdboot/`) and self-installs; Kickstart ROMs are the
user's and are never committed. Reference zips live in
`~/Documents/retro-zips` (see `docs/ZIPS.md`), never in the repo —
`retro-zips` is in the scanner's skip list on purpose.

### iOS packaging trap

The core must ship as `Frameworks/libuae4arm.framework/libuae4arm` (the
Swift loader's path, and a bare dylib in Frameworks/ triggers App Store
rejection 90426). `tools/build-ios-app.sh` builds that bundle; if the loader
path and the packaging ever disagree again, the symptom is "the emulator
core could not be loaded" from an app that builds fine. iOS containers also
move on every install: `ConfigStore.repairEmulatorSettings()` rewrites
stored absolute paths at launch — never persist an absolute container path
and expect it to survive.

### Android identity

`applicationId` is `com.uae4arm2026` and must stay (store package + signing
key); the display name is the manifest `android:label` (`Retro-Amiga`). iOS
uses its own bundle id (`com.crownparkcomputing.amigaretro`) — that split is
deliberate.

## Upstream

`src/` tracks BlitterStudio/amiberry (branch `upstream-rebase`, kept equal to
`main`). See `docs/upstream-sync.md`. Local changes concentrate in
`src/osdep/uae4arm_host.*`, the strip, and the multi-run fixes — keep diffs
against upstream small and deliberate.
