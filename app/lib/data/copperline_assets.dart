import 'dart:io';

import 'package:flutter/services.dart' show ByteData, rootBundle;

import 'app_log.dart';
import 'host_paths.dart';

/// Copperline's bundled runtime files, staged where the core can read them.
///
/// The core locates its freely-distributable ROMs "next to the binary or
/// under share/copperline/", a search written for a desktop install. On
/// Android and iOS there is no such place: the binary is the app itself and
/// everything it can read has to be inside its own directories. So the files
/// ship as app assets and are copied out on first use, and the generated
/// TOML points at the copies by absolute path -- the same contract
/// repairConfigFile leans on when iOS hands the app a new container, which
/// is why nothing here can be a path remembered from last launch.
///
/// What is staged and why:
///   * `fmv/copperline-fmv.rom` -- the open FMV cartridge image a CD32
///     config's `fmv = true` resolves to; without it the module is unfittable.
///   * `a2091/copperline-a2091.rom` -- the open SCSI autoboot ROM, needed
///     the moment a `[scsi]` controller is fitted.
///   * `whdboot/WHDLoad_usr.lha`, `whdboot/skick346.lha` -- the WHDLoad
///     archives Copperline's booter unpacks itself. The app also ships them
///     unpacked for Amiberry's booter; this is the other end of the same
///     files, kept as archives because that is what this core reads.
///
/// AROS is deliberately NOT here: the app's own ArosRom already stages the
/// same pair into the user's ROMs folder, and the TOML points at that copy.
class CopperlineAssets {
  const CopperlineAssets._();

  /// Asset path -> staged filename, under [root].
  static const Map<String, String> _files = <String, String>{
    'assets/copperline/fmv/copperline-fmv.rom': 'fmv/copperline-fmv.rom',
    'assets/copperline/a2091/copperline-a2091.rom':
        'a2091/copperline-a2091.rom',
    'assets/whdboot/WHDLoad_usr.lha': 'whdboot/WHDLoad_usr.lha',
    'assets/whdboot/skick346.lha': 'whdboot/skick346.lha',
  };

  /// Where the staged copies live, under the app's own support directory so
  /// an iOS container move is repaired like every other stored path.
  static Future<String> root() async =>
      '${await HostPaths.appSupport()}/copperline';

  /// The staged path for one file, whether or not staging has run yet --
  /// the TOML names the destination, and [ensureInstalled] makes it true.
  static Future<String> pathFor(String asset) async =>
      '${await root()}/${_files[asset]}';

  /// Writes any missing staged file. Never overwrites: a file already there
  /// may be one the user replaced deliberately.
  static Future<void> ensureInstalled() async {
    final String base = await root();
    for (final MapEntry<String, String> entry in _files.entries) {
      try {
        final File target = File('$base/${entry.value}');
        if (target.existsSync() && target.lengthSync() > 0) continue;
        target.parent.createSync(recursive: true);
        final ByteData data = await rootBundle.load(entry.key);
        target.writeAsBytesSync(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        AppLog.info('copperline', 'staged ${entry.value}');
      } on Object catch (error) {
        // A file that will not stage leaves its TOML key pointing at a path
        // that does not exist; the core's own error names it. Log and carry
        // on so one missing asset does not sink an unrelated boot.
        AppLog.warn('copperline', 'could not stage ${entry.key}: $error');
      }
    }
  }
}
