import 'dart:io';

import 'package:flutter/services.dart';

import 'file_category.dart';
import 'media_library.dart';

/// What WHDLoad support looks like right now.
class WhdloadStatus {
  const WhdloadStatus({
    required this.bootArchiveInstalled,
    required this.kickstartCount,
    this.source,
  });

  /// Whether `<home>/WHDBoot/boot-data.zip` is in place.
  final bool bootArchiveInstalled;

  /// Kickstarts copied into the booter's own kickstart folder.
  final int kickstartCount;

  /// Where the installed archive came from, for showing back to the user.
  final String? source;

  /// A .lha will not boot without both halves: the WHDLoad system files and a
  /// Kickstart for the machine the game wants.
  bool get ready => bootArchiveInstalled && kickstartCount > 0;
}

/// Installs the files the core's WHDLoad booter needs.
///
/// The booter is not ours - it is Amiberry's amiberry_whdbooter.cpp - so the
/// layout is its, not a choice:
///
///   `<home>/WHDBoot/boot-data.zip`   the WHDLoad system files, mounted as DH3
///   `<home>/WHDBoot/save-data/Kickstarts`   ROMs, symlinked in by the booter
///
/// `<home>` is where the core looks: SDL_GetAndroidExternalStoragePath on
/// Android, ~/Documents/Amiberry on iOS. It is asked of the host rather than
/// guessed, because putting the archive anywhere else leaves the booter
/// reporting nothing at all - the game simply never starts.
///
/// The archive itself is not shipped. WHDLoad is Bert Jahn's, distributed from
/// whdload.de, and the boot archive people use is assembled from it; this
/// finds the copy already on the device.
class WhdloadSupport {
  const WhdloadSupport._();

  static const MethodChannel _channel = MethodChannel('uae4arm2026/emulator');

  /// Names that mean "this is the WHDLoad boot archive". boot-data.zip is what
  /// the core looks for by name; the others are what the file is usually
  /// called before someone renames it.
  static const List<String> _bootArchiveNames = <String>[
    'boot-data.zip',
    'whdboot.zip',
    'whdload.zip',
    'whdload-boot.zip',
    'amiberry-whdboot.zip',
  ];

  /// Kickstart file names the booter expects, from skick346.lha. The booter
  /// symlinks these by name, so a ROM has to be called the right thing as well
  /// as be the right ROM.
  static const Map<String, String> kickstartNames = <String, String>{
    'kick34005.A500': '1.3',
    'kick40063.A600': '3.1 A600',
    'kick39106.A1200': '3.0 A1200',
    'kick40068.A1200': '3.1 A1200',
    'kick40068.A4000': '3.1 A4000',
    'kick31034.A1000': '1.0',
    'kick33180.A500': '1.2',
    'kick37175.A500': '2.04',
  };

  static Future<String?> home() async {
    try {
      return await _channel.invokeMethod<String>('emulatorHomeDirectory');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<Directory?> _whdBootDirectory() async {
    final String? base = await home();
    if (base == null || base.isEmpty) return null;
    final Directory dir = Directory('$base/WHDBoot');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<WhdloadStatus> status() async {
    final Directory? dir = await _whdBootDirectory();
    if (dir == null) {
      return const WhdloadStatus(
        bootArchiveInstalled: false,
        kickstartCount: 0,
      );
    }

    final File archive = File('${dir.path}/boot-data.zip');
    final Directory kickstarts = Directory('${dir.path}/save-data/Kickstarts');
    int count = 0;
    if (kickstarts.existsSync()) {
      count = kickstarts
          .listSync()
          .whereType<File>()
          .where((File f) => f.lengthSync() > 0)
          .length;
    }
    return WhdloadStatus(
      bootArchiveInstalled: archive.existsSync() && archive.lengthSync() > 0,
      kickstartCount: count,
    );
  }

  /// The boot archive somewhere on this device, if the scan saw one.
  static MediaFile? findBootArchive(MediaIndex index) {
    for (final MediaFile file in index.files) {
      if (file.category != FileCategory.archives) continue;
      final String name = file.name.toLowerCase();
      if (_bootArchiveNames.contains(name)) return file;
    }
    // Second pass, looser: someone's "WHDLoad_Boot_v19.zip".
    for (final MediaFile file in index.files) {
      if (file.category != FileCategory.archives) continue;
      final String name = file.name.toLowerCase();
      if (name.contains('whdboot') ||
          (name.contains('whdload') && name.contains('boot')) ||
          name.contains('boot-data')) {
        return file;
      }
    }
    return null;
  }

  /// Copies [sourcePath] into place as the boot archive.
  ///
  /// Copied rather than referenced: the core opens this by a fixed path, and a
  /// file on shared storage can be moved or deleted by anything.
  static Future<bool> installBootArchive(String sourcePath) async {
    final Directory? dir = await _whdBootDirectory();
    if (dir == null) return false;
    final File source = File(sourcePath);
    if (!source.existsSync()) return false;
    try {
      source.copySync('${dir.path}/boot-data.zip');
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Copies Kickstarts into the booter's kickstart folder, under the names it
  /// expects.
  ///
  /// Matching is by size and by what the file is called. A Kickstart's name in
  /// the wild ("kick13.rom", "Kickstart v3.1 rev 40.68 (A1200).rom") does not
  /// match what the booter wants, so this is a rename as much as a copy.
  /// Returns how many were installed.
  static Future<int> installKickstarts(MediaIndex index) async {
    final Directory? dir = await _whdBootDirectory();
    if (dir == null) return 0;

    final Directory target = Directory('${dir.path}/save-data/Kickstarts');
    if (!target.existsSync()) target.createSync(recursive: true);

    int installed = 0;
    for (final MediaFile rom in index.files) {
      if (rom.category != FileCategory.roms) continue;
      final File source = File(rom.path);
      if (!source.existsSync()) continue;
      // Only real Kickstarts: `bin` and `rom` are every other emulator's
      // extension too, and a wrong ROM here breaks WHDLoad rather than being
      // ignored.
      if (!MediaLibrary.looksLikeKickstart(source)) continue;

      final String? booterName = _booterNameFor(rom.name, source.lengthSync());
      if (booterName == null) continue;

      final File destination = File('${target.path}/$booterName');
      if (destination.existsSync()) continue;
      try {
        source.copySync(destination.path);
        installed++;
      } on FileSystemException {
        // Skip this one; the others are still worth having.
      }
    }
    return installed;
  }

  /// The name the booter wants for a ROM, from what it is called and how big
  /// it is, or null if it cannot be placed.
  ///
  /// Size settles the generation - 256K is Kickstart 1.x, 512K is 2.x/3.x -
  /// and the name settles which machine within it.
  static String? _booterNameFor(String fileName, int size) {
    final String name = fileName.toLowerCase();

    bool mentions(List<String> needles) => needles.any(name.contains);

    if (size <= 256 * 1024 + 16) {
      if (mentions(<String>['1.2', '12', '33.180'])) return 'kick33180.A500';
      if (mentions(<String>['1.0', '31.034'])) return 'kick31034.A1000';
      // 1.3 is the common 256K ROM and the sensible default.
      return 'kick34005.A500';
    }

    if (size <= 512 * 1024 + 16) {
      if (mentions(<String>['a600', '600'])) return 'kick40063.A600';
      if (mentions(<String>['a4000', '4000'])) return 'kick40068.A4000';
      if (mentions(<String>['3.0', '39.106'])) return 'kick39106.A1200';
      if (mentions(<String>['2.0', '2.04', '37.175'])) return 'kick37175.A500';
      // 3.1 for the A1200 is what most WHDLoad installs want.
      return 'kick40068.A1200';
    }

    // Extended ROMs and 1MB CD32 images are not what the booter symlinks.
    return null;
  }
}
