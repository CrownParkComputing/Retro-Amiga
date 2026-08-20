# Releasing Amiga-Retro to the App Store

The generic runbook -- one-time account setup, the build loop, the triage
table, and the account-level gates that block a submission silently -- lives in
the sister repo and is deliberately not duplicated here, so the two cannot
drift:

- `ViceMultiplatform/docs/APP_STORE_RELEASE.md`
- designed copy: https://claude.ai/code/artifact/979bd83e-b02d-4e7c-ba5d-ed75b8584f16

This file is only what is specific to *this* app.

## The facts

| | |
|---|---|
| Bundle ID | `com.crownparkcomputing.amigaretro` |
| App Store ID | 6801223370 |
| Team | 88A3T9K9C5 |
| Profile | `com.crownparkcomputing.amigaretro AppStore` |
| Device family | **iPad only** (`TARGETED_DEVICE_FAMILY = 2`) |
| Deployment target | iOS 15.0 |
| Price | £2.99, base territory GBR |
| Flutter project | `app/`, not the repo root |

Because the app is iPad-only, the one screenshot set that matters is
`APP_IPAD_PRO_3GEN_129` at 2064x2752. Widening `TARGETED_DEVICE_FAMILY` to
`1,2` would immediately owe an `APP_IPHONE_67` set as well.

## The loop

```sh
export ASC_BUNDLE_ID=com.crownparkcomputing.amigaretro

tools/appstore/asc.rb builds        # server's highest -- not app/pubspec.yaml
# bump app/pubspec.yaml: version: 1.0.0+N

cd app
flutter build ios --release --no-codesign
xcodebuild archive -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/ios/archive/Runner.xcarchive
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist ~/.config/c64retro/ExportOptions-amiga.plist \
  -exportPath build/ios/ipa
xcrun altool --upload-app -f build/ios/ipa/Amiga-Retro.ipa -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
cd ..

tools/appstore/asc.rb attach <N>
tools/appstore/asc.rb blockers
tools/appstore/asc.rb submit
```

Signing is set on the Runner target's **Release** config by hand before the
archive and reverted afterwards -- `main` keeps `CODE_SIGN_STYLE = Automatic`
so Xcode Cloud still builds. Back the file up first:

```sh
cp app/ios/Runner.xcodeproj/project.pbxproj /tmp/pbxproj.orig
```

## AROS, and why this app is easier to get through review

Amiga-Retro bundles the AROS m68k ROM as a fallback Kickstart, so it boots with
nothing supplied by the user. That is the whole Guideline 4.7 argument: a
reviewer with no ROMs still gets a working machine rather than a black screen,
which is exactly the exposure the C64 app still has.

Commodore's own Kickstarts stay out -- they are Cloanto's and shipping them is
not ours to do. Same rule as the C64 ROMs. The description and review notes
both say so; keep them saying so.

**Both were once wrong about this.** The store copy claimed *"the emulator will
not boot without a Kickstart ROM -- make sure you can supply one before
installing"* for two builds after AROS was bundled and it booted out of the
box. Nothing in the pipeline checks the copy against the binary. Re-read it
whenever the ROM story changes.

## Screenshots

The panels sit behind navigation and `simctl` has no tap API, so they are shot
by temporarily defaulting `WorkbenchSection` in
`app/lib/screens/workbench_screen.dart` to each section in turn and capturing
the first frame. Two app-specific traps:

- `AppPrefs.isNewBuild()` **deliberately re-runs the walkthrough after every
  deploy**, so setting `flutter.setup_complete` does not reach the workbench.
  Patch `_load()` in `app/lib/main.dart` instead.
- Planting the preference in the container plist does not work either -- the
  simulator's `cfprefsd` writes its cached copy back over the file.

An empty shelf photographs badly, so the capture run seeds a few setups through
`ConfigStore.save()` rather than hand-written `.uae`, which keeps the images
showing exactly what the app would have produced.

Every simulator capture carries an alpha channel and Apple rejects it during
processing, not at upload:

```sh
swift tools/flatten-screenshot.swift raw.png store/screenshots/ios-ipad-13-portrait/1-setup.png
tools/appstore/asc.rb shots APP_IPAD_PRO_3GEN_129 store/screenshots/ios-ipad-13-portrait/*.png
```

## Known gap

The simulator core is not built. `app/ios/Frameworks/libuae4arm.framework` is a
device binary, so the emulator itself cannot run in the Simulator -- the
launcher UI does, which is enough for screenshots but not for testing a game.
Building it needs SDL3, SDL3_image and FLAC compiled for
`iphonesimulator` first. The C64 side has the equivalent script at
`ViceMultiplatform/native/vice_core/ios/build-core-simulator.sh` if it is worth
doing.
