import 'dart:io';

import 'package:flutter/services.dart';

import 'app_log.dart';
import 'file_category.dart';
import 'media_library.dart';
import 'media_root.dart';

/// One thing WHDLoad needs, and whether it is there.
class WhdloadRequirement {
  const WhdloadRequirement({
    required this.name,
    required this.detail,
    required this.path,
    required this.present,
    this.essential = true,
  });

  final String name;

  /// What it is for, so a missing one says what will break.
  final String detail;

  /// Where it is looked for. Shown because when something is missing the next
  /// question is always "where should I put it".
  final String path;

  final bool present;

  /// False for things a game will usually run without.
  final bool essential;
}

/// What WHDLoad support looks like right now.
class WhdloadStatus {
  const WhdloadStatus({
    required this.bootArchiveInstalled,
    required this.kickstartCount,
    this.source,
    this.requirements = const <WhdloadRequirement>[],
  });

  /// Every piece, present or not, for showing back to the user.
  final List<WhdloadRequirement> requirements;

  /// The ones that are missing and matter.
  List<WhdloadRequirement> get missing => requirements
      .where((WhdloadRequirement r) => !r.present && r.essential)
      .toList();

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
    final bool hasArchive = archive.existsSync() && archive.lengthSync() > 0;

    final File database = File('${dir.path}/game-data/whdload_db.xml');

    // The ROMs, not the relocation tables. save-data/Kickstarts ships with a
    // .RTB per Kickstart and no Kickstart at all - those are patch tables,
    // and counting them would report a working setup that cannot boot.
    final Directory kickstarts = Directory('${dir.path}/save-data/Kickstarts');
    int count = 0;
    if (kickstarts.existsSync()) {
      count = kickstarts
          .listSync()
          .whereType<File>()
          .where((File f) =>
              !f.path.toLowerCase().endsWith('.rtb') && f.lengthSync() > 1024)
          .length;
    }

    return WhdloadStatus(
      bootArchiveInstalled: hasArchive,
      kickstartCount: count,
      requirements: <WhdloadRequirement>[
        WhdloadRequirement(
          name: 'Boot files',
          detail: 'WHDLoad itself, mounted as DH3 while a game runs.',
          path: '${dir.path}/boot-data.zip',
          present: hasArchive,
        ),
        WhdloadRequirement(
          name: 'Kickstart ROMs',
          detail: count > 0
              ? '$count in place, named the way the booter expects.'
              : 'Copied from your own ROMs and renamed - a game asks for the '
                  'Kickstart its slave was built against.',
          path: kickstarts.path,
          present: count > 0,
        ),
        WhdloadRequirement(
          name: 'Game database',
          detail: 'Per-game settings. Without it every game gets defaults, '
              'and some need more memory or a different CPU than the '
              'defaults give.',
          path: database.path,
          present: database.existsSync(),
          essential: false,
        ),
      ],
    );
  }

  /// Directories that already hold a WHDLoad boot tree, in order of
  /// preference.
  ///
  /// The scan cannot find these: it skips Android/data, which is exactly where
  /// another Amiberry-derived app keeps its copy, and it only indexes media
  /// extensions anyway. So they are looked at directly.
  static Future<List<Directory>> _knownBootTrees() async {
    final List<Directory> candidates = <Directory>[];

    // The media folder first, since that is where the user's own files live
    // and where an import would have put this one.
    final String root = await MediaRoot.path();
    final List<String> paths = <String>[
      '$root/WHDBoot',
      '$root/whdboot',
      '/sdcard/Amiga/WHDBoot',
      '/sdcard/UAE4Arm/whdboot',
      '/sdcard/WHDBoot',
    ];

    // Deliberately NOT another app's Android/data directory. Since Android 11
    // that is unreadable by anything but its owner, all-files access
    // included, so the copy the previous launcher keeps there cannot be used
    // however visible it looks over adb.

    for (final String path in paths) {
      final Directory tree = Directory(path);
      if (File('${tree.path}/boot-data.zip').existsSync()) {
        candidates.add(tree);
      }
    }
    return candidates;
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

  /// Installs everything the booter needs, from wherever it can be found.
  ///
  /// Returns the resulting status. Three things get installed, and the game
  /// will not boot without all of them:
  ///
  ///  * boot-data.zip - the WHDLoad system files, mounted as DH3
  ///  * game-data/whdload_db.xml - per-game settings, without which the booter
  ///    falls back to defaults that suit few games
  ///  * save-data/Kickstarts - the .RTB relocation tables that ship with
  ///    skick, plus the actual ROMs, which do not ship with anything and are
  ///    copied out of the user's own collection under the names the booter
  ///    symlinks
  static Future<WhdloadStatus> install(MediaIndex index) async {
    final Directory? target = await _whdBootDirectory();
    if (target == null) return status();

    // A whole tree beats a bare zip: it brings the database and the relocation
    // tables with it.
    for (final Directory tree in await _knownBootTrees()) {
      _copyTree(tree, target);
      break;
    }

    // Otherwise, whatever the scan turned up.
    if (!File('${target.path}/boot-data.zip').existsSync()) {
      final MediaFile? archive = findBootArchive(index);
      if (archive != null) {
        await installBootArchive(archive.path);
      }
    }

    final int roms = await installKickstarts(index);
    final WhdloadStatus result = await status();
    if (result.ready) {
      AppLog.info('whdload', 'ready ($roms Kickstarts installed)');
    } else {
      AppLog.warn('whdload',
          'not ready: ${result.missing.map((WhdloadRequirement r) => r.name).join(", ")} missing');
    }
    return result;
  }

  /// Copies a directory, skipping anything already there: an existing file is
  /// either the same file or one the user put there deliberately.
  static void _copyTree(Directory from, Directory to) {
    for (final FileSystemEntity entry in from.listSync(recursive: true)) {
      final String relative = entry.path.substring(from.path.length + 1);
      final String destination = '${to.path}/$relative';
      try {
        if (entry is Directory) {
          Directory(destination).createSync(recursive: true);
        } else if (entry is File) {
          if (File(destination).existsSync()) continue;
          Directory(File(destination).parent.path).createSync(recursive: true);
          entry.copySync(destination);
        }
      } on FileSystemException {
        // One unreadable file should not stop the rest.
      }
    }
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
