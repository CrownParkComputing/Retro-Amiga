import 'dart:io';

import 'package:flutter/services.dart' show ByteData, rootBundle;

import 'app_log.dart';
import 'file_category.dart';
import 'media_root.dart';

/// The fallback Kickstart, so the app boots on a clean install.
///
/// AROS is an independent, open reimplementation of AmigaOS. Its m68k ROM is
/// what the core reaches for when no real Kickstart is present -- Amiberry
/// says so itself, in as many words:
///
///     Could not load system ROM, trying AROS ROM replacement.
///
/// Shipping it changes the first run from "nothing boots, go and find a
/// Kickstart" to a working Amiga desktop, which matters for two reasons: it is
/// the difference between an app that demonstrates itself and one an App Store
/// reviewer reads as broken, and it gives anyone without a Kickstart something
/// to actually use.
///
/// **It is not a Kickstart substitute for games.** AROS is a reimplementation,
/// not a clone, and most WHDLoad titles and a good share of ADFs need a real
/// Kickstart. The listing and the setup screens have to keep saying so; the
/// honest claim is "boots immediately, add a Kickstart for compatibility".
///
/// Licence: AROS is distributed under the AROS Public License, which permits
/// redistribution. The APL requires that source remain available, so the
/// About panel carries the attribution and the pointer to aros.sourceforge.io
/// -- the same obligation Debian raised against FS-UAE for shipping these
/// exact files (bug #804234). Do not drop the attribution to save a screen.
class ArosRom {
  const ArosRom._();

  /// Both halves are needed. The ext ROM holds what does not fit in the main
  /// 512K image, and the core names them together when either is missing:
  /// "Could not find the 'aros-ext.bin' and 'aros-rom.bin' files".
  static const List<String> fileNames = <String>[
    'aros-rom.bin',
    'aros-ext.bin',
  ];

  /// Writes the pair into the Kickstarts folder if they are not already there.
  ///
  /// Placed alongside whatever real Kickstarts the user supplies rather than
  /// somewhere private, because that folder is exactly where the core looks
  /// and where the Paths screen tells people to put their own. A user who
  /// later adds kick31.rom gets both, and the core prefers the real one.
  ///
  /// Never overwrites. If a file of the same name is already present it is
  /// left alone: it may be a newer AROS the user fetched deliberately.
  static Future<bool> installIfMissing() async {
    try {
      final Directory target = await MediaRoot.folderFor(FileCategory.roms);
      if (!target.existsSync()) target.createSync(recursive: true);

      var wrote = 0;
      for (final String name in fileNames) {
        final File file = File('${target.path}/$name');
        if (file.existsSync() && file.lengthSync() > 0) continue;
        final ByteData data = await rootBundle.load('assets/roms/$name');
        file.writeAsBytesSync(
          data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          ),
          flush: true,
        );
        wrote++;
      }
      if (wrote > 0) {
        AppLog.info('aros', 'installed $wrote AROS ROM file(s) into '
            '${target.path}');
      }
      return true;
    } on Object catch (error) {
      // A missing fallback ROM is not fatal: the app still runs, and the
      // setup screens already explain how to supply a real Kickstart.
      AppLog.warn('aros', 'could not install AROS ROM: $error');
      return false;
    }
  }

  /// True when a Kickstart other than the bundled AROS pair is present, i.e.
  /// the user has supplied their own and full compatibility is available.
  static Future<bool> hasRealKickstart() async {
    try {
      final Directory dir = await MediaRoot.folderFor(FileCategory.roms);
      if (!dir.existsSync()) return false;
      for (final FileSystemEntity entry in dir.listSync()) {
        if (entry is! File) continue;
        final String name = entry.uri.pathSegments.last.toLowerCase();
        if (fileNames.contains(name)) continue;
        if (FileCategory.fromPath(name) == FileCategory.roms) return true;
      }
    } on Object {
      // Unreadable folder: report no real Kickstart rather than claim one.
    }
    return false;
  }
}
