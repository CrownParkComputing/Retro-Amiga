import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'data/whdload_support.dart';

import 'data/app_log.dart';
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

  /// Starts emulation. [args] is passed through verbatim to the core.
  static Future<void> launch(List<String> args) async {
    AppLog.info('launch', args.join(' '));
    // The launcher's music has no business playing over a game, and on
    // Android it would be a second process holding the audio device.
    await MusicPlayer.stop(byUser: false);
    Session.markStarted();
    try {
      await _channel.invokeMethod<bool>('launch', <String, Object?>{
        'args': args,
      });
    } on PlatformException catch (e) {
      AppLog.error('launch', '${e.code}: ${e.message}');
      rethrow;
    }
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
        final String path = trimmed.substring('whdload_filename='.length).trim();
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
  static Future<void> launchConfig(String configPath,
      {String whdloadArchive = ''}) async {
    final String archive =
        await _archiveIn(configPath) ?? whdloadArchive;
    // A WHDLoad game needs Amiberry's booter, and the booter needs its boot
    // archive mounted as DH3. Without it the machine boots to Workbench and
    // stops on "No disk present in device DH3" - a dead end that says nothing
    // about WHDLoad and, on iOS, could not even be left. Better to say so
    // before starting a machine that cannot run the game.
    if (archive.isNotEmpty) {
      WhdloadStatus status = await WhdloadSupport.status();
      if (!status.ready) {
        // The boot files ship with the app, so the first WHDLoad game a person
        // plays installs them rather than failing and telling them to go to
        // Settings. Only what is genuinely missing after that is worth
        // stopping for - a Kickstart, which is theirs to supply.
        await WhdloadSupport.installFromBundle();
        status = await WhdloadSupport.status();
      }
      if (!status.ready) {
        throw Exception(
          'This game needs ${status.missing.map((WhdloadRequirement r) => r.name).join(" and ")}. '
          'Settings > WHDLoad shows what is missing.',
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
