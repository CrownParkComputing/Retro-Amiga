# UAE4ARM 2026

[![Android Release Build](https://github.com/CrownParkComputing/uae4arm_2026/actions/workflows/android-release.yml/badge.svg)](https://github.com/CrownParkComputing/uae4arm_2026/actions/workflows/android-release.yml)

**UAE4ARM 2026** is an Android-only Amiga emulator, rebuilt with Jetpack Compose and Material3 around the Copperline (WinUAE-derived) emulation core.

---

## Overview

UAE4ARM 2026 is a complete Android-first rewrite of the classic UAE4ARM Amiga emulator. This 2026 edition keeps the emulator core in-tree for Android native builds and modernises the app layer with:

- **Jetpack Compose + Material3** UI — fully declarative, responsive layout
- **Copperline emulator backend** — battle-tested UAE-based core with ARM64 JIT
- **Drive icon tile UI** — floppy, hard disk, and CD drive slots presented as visual icon cards
- **Dynamic hard drive slots** — up to 10 HD entries, add/remove at runtime
- **Single-row memory layout** — Chip, Fast, and Z3 memory on one compact row
- **UAE4ARM branding** — restored classic UAE4ARM look with 2026 artwork

---

## Codebase Structure

```
uae4arm_2026/
├── android/                        # Android Kotlin/Compose app + Gradle project
│   ├── app/
│   │   └── src/main/
│   │       ├── java/com/uae4arm2026/
│   │       │   ├── data/
│   │       │   │   ├── ConfigGenerator.kt      # Writes .uae config files
│   │       │   │   ├── ConfigParser.kt         # Parses .uae config files
│   │       │   │   └── model/
│   │       │   │       └── EmulatorSettings.kt # All emulator config state
│   │       │   └── ui/
│   │       │       ├── screens/
│   │       │       │   ├── Uae4ArmHomeScreen.kt     # Main home screen
│   │       │       │   └── settings/
│   │       │       │       ├── StorageTab.kt        # Disk/drive file pickers
│   │       │       │       ├── SystemTab.kt         # CPU/memory settings
│   │       │       │       └── InputTab.kt          # Controller/keyboard
│   │       │       └── viewmodel/
│   │       │           └── SettingsViewModel.kt     # Settings state & logic
│   │       └── res/
│   │           ├── drawable/                   # UAE4ARM artwork + icons
│   │           └── mipmap-*/                   # Launcher icon variants
│   ├── build.gradle                # App module Gradle config
│   ├── gradle/                     # Version catalogs (libs.versions.toml)
│   └── gradlew / gradlew.bat       # Gradle wrapper
├── src/                            # Native emulator core built by Android externalNativeBuild
│   ├── osdep/                      # Platform abstraction
│   ├── jit/                        # ARM64 + x86-64 JIT compiler
│   ├── custom.cpp                  # Amiga custom chips (Agnus/Denise/Paula)
│   ├── newcpu.cpp                  # M68K CPU interpreter
│   └── memory.cpp                  # Memory banking
├── CMakeLists.txt                  # Native Android build entry point + version source of truth
├── cmake/                          # Android-focused CMake helpers used by the native build
├── external/                       # Vendored native dependencies
├── amiberry-src/                   # Upstream Amiberry snapshot used for sync tracking
└── .github/workflows/
    └── android-release.yml         # CI: build + sign + release APK/AAB
```

---

## Key Files

| File | Purpose |
|------|---------|
| `android/app/src/main/java/.../ui/screens/Uae4ArmHomeScreen.kt` | Main UI — drive icon cards, launch button, recent configs |
| `android/app/src/main/java/.../data/model/EmulatorSettings.kt` | All emulator settings including `hardDrives: List<String>` |
| `android/app/src/main/java/.../data/ConfigParser.kt` | Parses `.uae` config files into `EmulatorSettings` |
| `android/app/src/main/java/.../data/ConfigGenerator.kt` | Generates `.uae` config file content from `EmulatorSettings` |
| `android/app/src/main/java/.../ui/viewmodel/SettingsViewModel.kt` | Manages settings state, generates SDL launch args |
| `CMakeLists.txt` | `project(VERSION 4.1.1)` — single version source for app + core |

---

## Version

Version is defined once in `CMakeLists.txt`:

```cmake
project(uae4arm
    VERSION 4.1.1
    ...
)
```

`android/app/build.gradle` reads this automatically and computes `versionCode` and `versionName`.

---

## Building

### Prerequisites

- Android Studio or Android SDK/NDK command-line tooling
- JDK 21 (`JAVA_HOME` = Android Studio JBR)
- Android SDK with NDK r28.0.13004108, CMake 3.22.1, build-tools 37, platform 37

### Debug build (local device)

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
cd android
.\gradlew installDebug
```

### Release build

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
cd android
.\gradlew assembleRelease
```

Release signing requires `android/keystore.properties` (git-ignored):

```properties
storeFile=../keystore/uae4arm26-upload.jks
storePassword=<password>
keyAlias=uae4arm26-upload
keyPassword=<password>
```

---

## CI / GitHub Actions

The workflow `.github/workflows/android-release.yml` triggers on:

- Every push to `main` (when Android or core source changes)
- Any `v*` tag push
- Manual `workflow_dispatch`

It builds both an APK and AAB, signs with the keystore decoded from the `RELEASE_KEYSTORE_BASE64` secret, uploads artifacts, and creates a GitHub Release. Required repository secrets:

| Secret | Value |
|--------|-------|
| `RELEASE_KEYSTORE_BASE64` | Base64-encoded `.jks` keystore |
| `RELEASE_STORE_PASSWORD` | Keystore password |
| `RELEASE_KEY_ALIAS` | Key alias (`uae4arm26-upload`) |
| `RELEASE_KEY_PASSWORD` | Key password |

The workflow `.github/workflows/public-source-mirror.yml` publishes the latest source snapshot from this repository to the public mirror repository `CrownParkComputing/uae4arm2026p`, always overwriting the public repository's `main` branch with the newest mirrored source. It excludes `.github/workflows/` from the mirrored snapshot so the public mirror can be updated with a standard contents-write token. It requires one additional secret:

| Secret | Value |
|--------|-------|
| `PUBLIC_MIRROR_TOKEN` | Personal access token with contents write access to `CrownParkComputing/uae4arm2026p` |

---

## Upstream Sync

This repository does not consume Amiberry as a git submodule. Instead, it tracks Amiberry as an explicit git remote named `upstream`, and keeps a traceable snapshot under `amiberry-src/`.

- Upstream repo: `https://github.com/BlitterStudio/amiberry.git`
- Upstream branch: `master`
- Comparison script: `scripts/git/compare-amiberry-upstream.ps1`
- Sync procedure and ledger: `docs/upstream-sync.md`

Use the comparison script before and after any upstream import so each sync is anchored to a specific Amiberry commit.

---

## License

Licensed under the [GNU General Public License v3.0](LICENSE).

UAE4ARM 2026 builds on open source work from [Copperline](https://github.com/CrownParkComputing/uae4arm_2026) (derived from Amiberry) and [WinUAE](https://www.winuae.net/). The original UAE4ARM project is by Chips (Georgiou Konstantinos).
