import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ffi/amiga_core.dart';

import 'data/config_store.dart';
import 'data/whdload_support.dart';

import 'data/app_log.dart';
import 'data/host_paths.dart';
import 'data/music_player.dart';
import 'data/session.dart';

/// The one road from the Flutter UI into the emulator core.
///
/// Every platform binds the same channel: on Android it starts the SDL
/// activity in its own process, on iOS it presents the emulator view
/// controller, on desktop it runs the core as a child process. The Dart side
/// only ever hands over an argument list, exactly as the command line takes.
class Emulator {
  static const MethodChannel _channel = MethodChannel('uae4arm2026/emulator');

  /// The core running INSIDE this process, when the build has one.
  ///
  /// This is what stops a game wiping the launcher: with frames coming back
  /// as pixels the machine is a widget in the workbench's panel, not a second
  /// Activity. Null on a core too old to hand frames back, or on a platform
  /// that runs the core as a child process -- and then [launch] falls back to
  /// the Activity exactly as before.
  static AmigaCore? get inProcessCore {
    final core = AmigaCore.open();
    if (core == null || !core.hasFramebufferOutput) return null;
    return core;
  }

  /// True while the in-process core is running, so the workbench knows to
  /// show the machine in its panel.
  static final ValueNotifier<bool> playing = ValueNotifier<bool>(false);

  /// True when the app backgrounded a running game, so it is known whether
  /// coming back should start it again. A game the user paused themselves is
  /// left paused: resuming it for them would drop them straight back into
  /// play with no warning.
  static bool _suspendedByBackground = false;

  /// Pauses a running game because the app is leaving the foreground.
  ///
  /// The in-process core keeps emulating whatever the app is doing - it is a
  /// thread in this process, not a second Activity that the system stops - so
  /// without this a minimised launcher carries on playing the game's audio out
  /// of a pocket, and burning battery on frames nobody can see.
  static void suspend() {
    if (!playing.value) return;
    final AmigaCore? core = inProcessCore;
    if (core == null || !core.isRunning) return;
    core.setPaused(true);
    _suspendedByBackground = true;
  }

  /// Restarts a game that [suspend] paused, and only one it paused.
  static void resumeIfSuspended() {
    if (!_suspendedByBackground) return;
    _suspendedByBackground = false;
    if (!playing.value) return;
    final AmigaCore? core = inProcessCore;
    if (core == null || !core.isRunning) return;
    core.setPaused(false);
  }

  /// Forgets that the app paused the game, for a user who pauses or resumes it
  /// themselves while the app is away - their choice outranks ours.
  static void forgetBackgroundPause() => _suspendedByBackground = false;

  /// Starts emulation. [args] is passed through verbatim to the core.
  static Future<void> launch(List<String> args) async {
    // The core's own stored paths rot when iOS moves the container; see
    // ConfigStore.repairEmulatorSettings. Done for every launch, because a
    // game is the only thing that reads them.
    await ConfigStore.repairEmulatorSettings();

    AppLog.info('launch', args.join(' '));
    // The launcher's music has no business playing over a game. The core is
    // in-process now, so stop() also closes the music stream before the core
    // opens its own; two SDL playback streams caused underruns on Android.
    await MusicPlayer.stop(byUser: false);
    Session.markStarted();

    final AmigaCore? core = inProcessCore;
    if (core != null) {
      // In-process: the launcher stays on screen and the picture appears in
      // its panel. No Activity, no window, no wipe. A session that is still
      // running -- parked behind the workbench, or simply abandoned for a
      // different game -- is quit and waited for inside start().
      AppLog.info('launch', 'in-process core');
      playing.value = false;
      await core.start(args);
      // Where pausing puts its snapshot: states/<config name>.uss, the same
      // rule every host uses, so the Resume shelf reads one index. A launch
      // with no config - a bare model boot - has no session to come back to.
      final int at = args.indexOf('--config');
      if (at >= 0 && at + 1 < args.length) {
        final String configPath = args[at + 1];
        String name = configPath.split('/').last;
        final int dot = name.lastIndexOf('.');
        if (dot > 0) name = name.substring(0, dot);
        final String support = await HostPaths.appSupport();
        core.setSession('$support/states/$name.uss', configPath, name);
      }
      playing.value = true;
      return;
    }

    try {
      await _channel.invokeMethod<bool>('launch', <String, Object?>{
        'args': args,
      });
    } on PlatformException catch (e) {
      AppLog.error('launch', '${e.code}: ${e.message}');
      rethrow;
    }
  }

  /// Ends an in-process session and puts the workbench back in charge.
  static void stopInProcess() {
    final AmigaCore? core = inProcessCore;
    if (core == null || !core.isRunning) return;
    // Leaving keeps your place, the way the C64 front end's pause does: the
    // snapshot is written before the machine goes down, and Resume offers it.
    core.saveSession();
    core.quit();
    playing.value = false;
  }

  /// Ends the session without writing a snapshot.
  ///
  /// The difference from [stopInProcess] is the whole point of having both:
  /// pause is "I am coming back to this exact moment", close is "I am done".
  /// Writing a snapshot for someone who pressed close fills the Resume shelf
  /// with sessions nobody asked to keep, and each one is a full memory dump.
  static void closeInProcess() {
    final AmigaCore? core = inProcessCore;
    if (core == null || !core.isRunning) return;
    core.quit();
    playing.value = false;
  }

  /// Which host implementation answered, for showing platform-specific UI.
  static Future<String> platformName() async {
    return await _channel.invokeMethod<String>('platformName') ?? 'unknown';
  }

  /// Boots straight into a machine with no media, the quickest way to prove
  /// the whole chain works. `-G` keeps the core from expecting a GUI of its
  /// own — this fork has none.
  /// Opens the screen that asks which physical button is which.
  ///
  /// Native, not Flutter: it has to see raw controller key events to learn a
  /// pad, and reading those is the Activity's job.
  static Future<void> openControllerMapping() async {
    try {
      await _channel.invokeMethod<void>('openControllerMapping');
    } on MissingPluginException {
      // Desktop has no such screen; nothing to open is not an error.
    } on PlatformException {
      // Same.
    }
  }

  static Future<void> launchModel(String model) {
    return launch(<String>['--rescan-roms', '--model', model, '-G']);
  }

  /// Boots a machine with a floppy in DF0.
  /// The archive a config names, or [fallback] when it names none. Exposed
  /// for the test that pins this: the launch must prefer the file, because
  /// the file is what the repair just corrected.
  @visibleForTesting
  static Future<String> archiveFor(String configPath, String fallback) async =>
      await _archiveIn(configPath) ?? fallback;

  /// The WHDLoad archive a config names, or null if it names none.
  static Future<String?> _archiveIn(String configPath) async {
    try {
      final File file = File(configPath);
      if (!file.existsSync()) return null;
      for (final String line in file.readAsLinesSync()) {
        final String trimmed = line.trim();
        if (!trimmed.startsWith('whdload_filename=')) continue;
        final String path = trimmed
            .substring('whdload_filename='.length)
            .trim();
        return path.isEmpty ? null : path;
      }
    } on FileSystemException {
      // Unreadable: fall back to what the caller believed.
    }
    return null;
  }

  static Future<void> launchFloppy(String model, String path) {
    return launch(<String>[
      '--rescan-roms',
      '--model',
      model,
      '-0',
      path,
      '-G',
    ]);
  }

  /// Runs a saved .uae configuration.
  ///
  /// [whdloadArchive] is passed separately because a config cannot start a
  /// WHDLoad game. The core's booter is triggered by --autoload (or by the
  /// .lha arriving as a bare argument), not by the whdload_filename key: with
  /// only the key set the machine boots to Workbench and the game never runs,
  /// and nothing in the log mentions WHDLoad at all.
  /// [whdloadArchive] is a hint only. The archive is read back out of the
  /// config file, because the file is the one thing that has just been
  /// repaired: iOS hands the app a new container on every install, and a
  /// record read before that repair still holds a path into a container that
  /// no longer exists. Passing that stale path to --autoload gave the booter
  /// nothing to load and the player a black screen, while the config beside
  /// it was perfectly correct.
  static Future<void> launchConfig(
    String configPath, {
    String whdloadArchive = '',
  }) async {
    final String archive = await _archiveIn(configPath) ?? whdloadArchive;
    // A WHDLoad game needs Amiberry's booter, and the booter needs its boot
    // archive mounted as DH3. Without it the machine boots to Workbench and
    // stops on "No disk present in device DH3" - a dead end that says nothing
    // about WHDLoad and, on iOS, could not even be left. Better to say so
    // before starting a machine that cannot run the game.
    if (archive.isNotEmpty) {
      WhdloadStatus status = await WhdloadSupport.status();
      if (!status.ready) {
        // The boot files ship with the app and the ROMs are in the library,
        // so the first WHDLoad game a person plays puts both in place rather
        // than failing. Only what is genuinely missing after that is worth
        // stopping for - a Kickstart nobody owns cannot be conjured.
        status = await WhdloadSupport.installEverything();
      }
      if (!status.ready) {
        throw Exception(
          'This game needs ${status.missing.map((WhdloadRequirement r) => r.name).join(" and ")}. '
          'A Kickstart ROM is the usual one: add yours to the media folder '
          'and scan, and it will be put in place for you.',
        );
      }
    }
    return launch(<String>[
      '--rescan-roms',
      '--config',
      configPath,
      if (archive.isNotEmpty) ...<String>['--autoload', archive],
      '-G',
    ]);
  }
}
