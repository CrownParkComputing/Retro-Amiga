# Retro-Amiga platform parity

The Flutter launcher owns the shared UI and data model. Each host implements
the same `uae4arm2026/emulator` method channel; the emulator-facing C API is
in `src/osdep/uae4arm_host.{h,cpp}`.

| Capability | Android | iOS | macOS | Windows | Linux |
|---|---|---|---|---|---|
| Platform and storage paths | implemented | implemented | implemented | implemented | implemented |
| Build stamp | implemented | implemented | implemented | implemented | implemented |
| All-files access | system permission | always available | always available | always available | always available |
| Controller mapping screen | native activity | no-op | no-op | no-op | no-op |
| Emulator launch | SDL activity/process | in-process shared-core bridge | shared-core bridge | shared-core bridge | shared-core bridge |
| Music player | native JNI bridge | shared-core bridge | shared-core bridge | shared-core bridge | shared-core bridge |

## What is shared already

`app/lib/emulator.dart`, the media/config stores, WHDLoad preparation, and all
launch argument construction are platform-neutral. The core bridge exposes one
stable C surface for running, restarting, quitting, input, save states, music,
and pads. All four native host families now bind the run path; Android uses a
separate SDL process, while iOS and desktop load the shared core in the app.

## Remaining parity work

Desktop hosts now load `uae4arm_host_run` from the packaged shared core and pass
the same argument list as Android and iOS. Linux and Windows copy the core from
the path in their CMake cache (`UAE4ARM_CORE_LIBRARY`); macOS expects the core
inside the app's Frameworks directory. Desktop music now uses the same
shared-core ProTracker exports. Physical desktop controllers remain SDL-native;
host-drawn virtual pad callbacks are only needed on touch platforms.

Flutter tests could not be run in the current environment because the `flutter`
executable is not installed; run `flutter test --no-pub` from `app/` on a Flutter
development machine before release.
