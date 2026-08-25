import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'host_paths.dart';

/// Recovers data written by the Compose launcher this app replaced.
///
/// Both launchers use the same Android package, so an upgrade keeps the old
/// external app directory. The old launcher saved setups in
/// `<external files>/conf`; Flutter saves them in `<files>/conf`. Merely
/// changing that root made every existing setup disappear from the shelf even
/// though the files were still on the device.
class LegacyMigration {
  const LegacyMigration._();

  static const String _doneKey = 'legacy_compose_migration_v1';

  /// Copies every old saved setup once. Existing new setups always win; when
  /// a different old setup has the same filename it is restored under a
  /// clearly named suffix instead of being overwritten or discarded.
  ///
  /// The path overrides are for tests; production asks the host for the two
  /// roots.
  static Future<int> run({
    String? appSupportDirectory,
    String? emulatorHomeDirectory,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_doneKey) ?? false) return 0;

    int copied = 0;
    try {
      final String support =
          appSupportDirectory ?? await HostPaths.appSupport();
      final String home =
          emulatorHomeDirectory ?? await HostPaths.emulatorHome();
      final Directory source = Directory('$home/conf');
      final Directory destination = Directory('$support/conf');

      if (source.existsSync() && source.path != destination.path) {
        destination.createSync(recursive: true);
        for (final FileSystemEntity entity in source.listSync()) {
          if (entity is! File) continue;
          final String name = entity.uri.pathSegments.last;
          if (name.startsWith('.') || !name.toLowerCase().endsWith('.uae')) {
            continue;
          }

          File target = File('${destination.path}/$name');
          if (target.existsSync()) {
            if (_sameFile(entity, target)) continue;
            target = _availableRestoredName(destination, name);
          }
          entity.copySync(target.path);
          copied++;
        }
      }

      // A person with saved setups has already completed setup. Do not force
      // them through first-run onboarding just because the new launcher's
      // preference namespace did not exist yet.
      if (copied > 0 && !(prefs.getBool('setup_complete') ?? false)) {
        await prefs.setBool('setup_complete', true);
      }
      AppLog.info('migration', 'restored $copied legacy setup(s)');
    } on FileSystemException catch (error) {
      // Retry next launch. Marking a failed migration complete would turn a
      // transient storage problem into permanent data loss in the UI.
      AppLog.warn('migration', 'legacy setup restore deferred: $error');
      return copied;
    }

    await prefs.setBool(_doneKey, true);
    return copied;
  }

  static bool _sameFile(File first, File second) {
    if (first.lengthSync() != second.lengthSync()) return false;
    return first.readAsBytesSync().toString() ==
        second.readAsBytesSync().toString();
  }

  static File _availableRestoredName(Directory destination, String name) {
    final String stem = name.substring(0, name.length - 4);
    int suffix = 1;
    while (true) {
      final String label = suffix == 1
          ? '$stem (restored).uae'
          : '$stem (restored $suffix).uae';
      final File candidate = File('${destination.path}/$label');
      if (!candidate.existsSync()) return candidate;
      suffix++;
    }
  }
}
