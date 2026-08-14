import 'package:flutter/material.dart';

// Imported so the emulator overlay's entry point exists in the compiled
// bundle. The kernel contains only what is reachable from main(), and nothing
// else references this library - it is entered by name from the emulator
// Activity. Without the import the engine fails with "Could not resolve main
// entrypoint function", the overlay never paints, and because its surface sits
// over SDL's the emulator runs invisibly behind it.
import 'overlay_main.dart' show emulatorOverlayMain;

import 'dart:async';

import 'data/app_prefs.dart';
import 'data/startup_import.dart';
import 'data/whdload_support.dart';
import 'screens/workbench_screen.dart';
import 'screens/onboarding_screen.dart';

/// Keeps the tear-off above from being treated as an unused import.
// ignore: unused_element
const Object _overlayEntryPoint = emulatorOverlayMain;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The boot files WHDLoad needs are assets, so put them in place before
  // anything asks whether they are there. Otherwise the first thing a new
  // install says about WHDLoad is "not ready" - about files it is carrying.
  // Only writes what is missing, and a failure here is not worth blocking a
  // launcher for: the game that needs them installs them too.
  unawaited(WhdloadSupport.installEverything());
  runApp(const AmigaRetroApp());
}

class AmigaRetroApp extends StatelessWidget {
  const AmigaRetroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amiga-Retro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE1122F),
          brightness: Brightness.dark,
        ),
      ),
      home: const _Root(),
    );
  }
}

/// Decides whether to run setup or go straight to the shelf.
///
/// Setup is not a welcome screen to skip past: until it has found a Kickstart
/// there is nothing the shelf can usefully offer, so first launch goes there.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool? _setupComplete;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    bool complete = false;
    try {
      complete = await AppPrefs.setupComplete();
      // A newly deployed build goes through the walkthrough again, whatever
      // was answered last time. It is the one screen that says what this
      // install can actually see - the scan, where media lives, whether
      // WHDLoad is ready - and after a deploy that is exactly what nobody
      // knows.
      if (complete && await AppPrefs.isNewBuild()) complete = false;
    } on Object {
      // A missing preference store means first run, not a failure.
    }
    // File anything new before the Workbench draws, so a collection copied in
    // through the Files app is simply there. Skipped on first run because the
    // onboarding walkthrough does its own import, with the root chooser and a
    // report the user can actually read; doing it twice would move the same
    // files and then show "nothing found".
    if (complete) await StartupImport.run();
    if (mounted) setState(() => _setupComplete = complete);
  }

  @override
  Widget build(BuildContext context) {
    if (_setupComplete == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_setupComplete!) return const WorkbenchScreen();
    return OnboardingScreen(
      onFinished: () async {
        // Remembered on the way out rather than on the way in: a walkthrough
        // that was never finished should come back.
        await AppPrefs.rememberBuild();
        if (mounted) setState(() => _setupComplete = true);
      },
    );
  }
}
