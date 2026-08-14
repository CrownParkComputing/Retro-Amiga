import 'dart:io';

import 'host_paths.dart';
import 'pad_layout.dart';

/// Where the on-screen pad's layout lives.
///
/// A file rather than preferences, because two processes read it: the launcher
/// designs the pad, and the emulator - which runs in its own process so SDL
/// can own a surface - draws it. SharedPreferences is per-process and caches
/// aggressively, so a layout saved in one would not be seen by the other until
/// something happened to evict it, which is the kind of bug that looks like
/// "sometimes my buttons move back".
class PadLayoutStore {
  const PadLayoutStore._();

  /// Matches the path the emulator's Activity reads: getFilesDir() on Android
  /// is the same directory path_provider calls the app support directory.
  static Future<File> file() async =>
      File('${await HostPaths.appSupport()}/pad_layout.json');

  static Future<PadLayout> load({
    PadStyle fallbackStyle = PadStyle.joystick,
  }) async {
    try {
      final File source = await file();
      if (!source.existsSync()) {
        return PadLayout.defaults.copyWith(style: fallbackStyle);
      }
      return PadLayout.decode(
        source.readAsStringSync(),
        fallbackStyle: fallbackStyle,
      );
    } on Object {
      // An unreadable layout must not be the reason a game has no controls.
      return PadLayout.defaults.copyWith(style: fallbackStyle);
    }
  }

  static Future<void> save(PadLayout layout) async {
    final File target = await file();
    // Written whole and then moved into place: the emulator process may be
    // reading this at the same moment, and half a file parses as no file.
    final File temp = File('${target.path}.tmp');
    temp.writeAsStringSync(layout.encode(), flush: true);
    temp.renameSync(target.path);
  }
}
