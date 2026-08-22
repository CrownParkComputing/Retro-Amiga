// The compliance demo: a machine that runs with nothing supplied by the user.
//
// Mirrors Retro-C64's DemoRomsService, and exists for the same reason. A store
// review asks what the app ships, what it needs, and whether it does anything
// at all out of the box -- and "install a Kickstart first" is a poor answer to
// the last one, especially from a reviewer who has no Amiga to take one from.
//
// Two halves:
//
//   * the ROM. AROS is an independent, open reimplementation of AmigaOS, and
//     the app already carries it (see ArosRom). None of it is Commodore's.
//   * the disk. tool/demo_boot.s is ours: a boot block that drives the
//     chipset directly and calls nothing in the ROM but AllocMem, so it is
//     the same demo on AROS and on a real Kickstart.
//
// The demo lives in its own VISIBLE folder, not buried in private storage: a
// review team has to be able to look at what the app claims to ship, and
// "trust us, it is in there" is not an answer.
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'aros_rom.dart';
import 'media_root.dart';

class ComplianceDemo {
  const ComplianceDemo._();

  /// What the disk is called once written out. Short and upper case: the
  /// name is read by the emulated machine as well as by the app.
  static const String diskName = 'DEMO.ADF';

  static const String _diskAsset = 'assets/demo/demo.adf';

  /// The demo's own folder, beside the user's media rather than inside it.
  static Future<Directory> folder() async {
    final Directory dir = Directory('${await MediaRoot.path()}/Compliance');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Writes the demo disk and the AROS ROM out together, and returns the
  /// disk's path.
  ///
  /// Idempotent, and it clears any earlier disk image out first: the name
  /// has to be free to change without leaving the old one behind for the
  /// library to list twice.
  static Future<String> prepare({Directory? into}) async {
    final Directory dir = into ?? await folder();
    if (!dir.existsSync()) dir.createSync(recursive: true);

    for (final FileSystemEntity f in dir.listSync()) {
      if (f is File &&
          f.path.toLowerCase().endsWith('.adf') &&
          f.uri.pathSegments.last != diskName) {
        f.deleteSync();
      }
    }

    final File disk = File('${dir.path}/$diskName');
    final data = await rootBundle.load(_diskAsset);
    await disk.writeAsBytes(data.buffer.asUint8List(), flush: true);

    // The ROM goes in beside it, so everything the demo runs on is in one
    // folder a reviewer can open.
    await ArosRom.installIfMissing();
    return disk.path;
  }

  /// Everything in the demo folder, for display. Names only: the point is
  /// that a reviewer can read the list and go and open the files.
  static Future<List<String>> files({Directory? from}) async {
    final Directory dir = from ?? await folder();
    if (!dir.existsSync()) return const <String>[];
    final List<String> names = <String>[
      for (final FileSystemEntity e in dir.listSync(recursive: true))
        if (e is File) e.path.substring(dir.path.length + 1),
    ];
    names.sort();
    return names;
  }
}
