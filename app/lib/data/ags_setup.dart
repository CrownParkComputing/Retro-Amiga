import 'dart:io';
import 'dart:isolate';

import 'amiga_model.dart';
import 'app_log.dart';
import 'file_category.dart';
import 'config_store.dart';
import 'emulator_settings.dart';
import 'hard_drive_set.dart';
import 'media_library.dart';
import 'media_root.dart';

/// Finds an AGS set and builds a config for it.
class AgsSetup {
  const AgsSetup._();

  /// A folder is an AGS set if it holds several hard drives. Two is a pair of
  /// disks; four or more together is somebody's installation.
  static const int _minimumDrives = 4;

  /// Reads [folder] and describes what is there, or null if it is not a set.
  static HardDriveSet? inspect(String folder) {
    final HardDriveSet? set = HardDriveSet.inspect(folder);
    if (set == null || set.driveCount < _minimumDrives) return null;
    return set;
  }

  /// Looks for an AGS set in the usual places.
  ///
  /// The scan index is used rather than a fresh walk: it already knows where
  /// every hard drive on the device is, and an AGS set is simply a folder that
  /// holds a lot of them. Removable storage is checked too, since a set is
  /// large enough that people keep it on a card.
  static Future<List<HardDriveSet>> find(MediaIndex index) async {
    // Folders the scan already found hard drives in. Cheap: no filesystem
    // access, just the index.
    final Map<String, int> counts = <String, int>{};
    for (final MediaFile file in index.files) {
      if (file.category != FileCategory.hardDrives) continue;
      counts[file.directory] = (counts[file.directory] ?? 0) + 1;
    }
    final List<String> fromIndex = counts.entries
        .where((MapEntry<String, int> e) => e.value >= _minimumDrives)
        .map((MapEntry<String, int> e) => e.key)
        .toList();

    final List<String> roots = <String>[
      await MediaRoot.path(),
      '/sdcard',
      '/storage',
    ];

    // The walk runs in its own isolate. It is synchronous filesystem work over
    // whatever is plugged in - an external drive can be enormous - and on the
    // UI isolate that is a frozen app rather than a slow one.
    final List<Map<String, Object>> found = await Isolate.run(
      () => _search(roots, fromIndex),
    );

    return found
        .map(
          (Map<String, Object> m) => HardDriveSet(
            folder: m['folder']! as String,
            bootDrive: m['boot']! as String,
            drives: (m['drives']! as List<Object?>).cast<String>(),
            sharedFolder: m['shared']! as String,
          ),
        )
        .toList();
  }

  /// Runs in an isolate; returns plain maps, which is all that can cross.
  static List<Map<String, Object>> _search(
    List<String> roots,
    List<String> fromIndex,
  ) {
    final Set<String> folders = <String>{...fromIndex};

    for (final String root in roots) {
      final Directory dir = Directory(root);
      if (!dir.existsSync()) continue;
      try {
        for (final FileSystemEntity entry in dir.listSync(followLinks: false)) {
          if (entry is! Directory) continue;
          final String name = entry.path.split('/').last.toLowerCase();
          if (name.contains('ags')) {
            folders.add(entry.path);
          } else if (root == '/storage' &&
              name != 'emulated' &&
              name != 'self') {
            // A card or a USB drive. An AGS set on one is usually at the root
            // or one folder in - "AGS_UAE", or "Amiga/AGS_UAE" - so both are
            // looked at, and any folder holding enough hard drives counts even
            // when its name says nothing.
            _addIfAgs(entry, folders, depth: 2);
          }
        }
      } on FileSystemException {
        continue;
      }
    }

    final List<HardDriveSet> found = <HardDriveSet>[];
    for (final String folder in folders) {
      final HardDriveSet? install = inspect(folder);
      if (install != null) found.add(install);
    }
    found.sort(
      (HardDriveSet a, HardDriveSet b) => b.driveCount.compareTo(a.driveCount),
    );

    return found
        .map(
          (HardDriveSet i) => <String, Object>{
            'folder': i.folder,
            'boot': i.bootDrive,
            'drives': i.drives,
            'shared': i.sharedFolder,
          },
        )
        .toList();
  }

  /// Adds [dir] and, up to [depth] levels down, any folder that is an AGS set
  /// or is named for one.
  static void _addIfAgs(
    Directory dir,
    Set<String> folders, {
    required int depth,
    int budget = 400,
  }) {
    if (depth <= 0 || budget <= 0) return;
    try {
      if (inspect(dir.path) != null) folders.add(dir.path);
      // A budget as well as a depth: an external drive can hold thousands of
      // folders, and looking in every one of them to find a set of HDFs is not
      // worth the wait even off the UI isolate.
      int left = budget;
      for (final FileSystemEntity child in dir.listSync(followLinks: false)) {
        if (child is! Directory) continue;
        if (--left <= 0) return;
        final String name = child.path.split('/').last.toLowerCase();
        if (name.startsWith('.') || name == 'android') continue;
        if (name.contains('ags') || inspect(child.path) != null) {
          folders.add(child.path);
        }
        _addIfAgs(child, folders, depth: depth - 1, budget: left);
      }
    } on FileSystemException {
      // Unreadable mount, which is normal for some cards.
    }
  }

  /// The machine an AGS set wants.
  ///
  /// Taken from the working config this replaces: an A1200 with the JIT, a
  /// Zorro III graphics card and enough Z3 memory for it. AGS runs its menu on
  /// the RTG screen, so without the card it starts and shows nothing useful.
  static EmulatorSettings settingsFor(HardDriveSet install, String romFile) {
    return EmulatorSettings.fromModel(AmigaModel.a1200).copyWith(
      cpuModel: 68020,
      cpuCompatible: true,
      cpuSpeed: 'max',
      fpuModel: 68882,
      jitCacheSize: 16384,
      chipRam: 4,
      fastRam: 0,
      z3Ram: 512,
      useRtg: true,
      romFile: romFile,
      hardDrives: install.allMounts,
    );
  }

  /// Writes the config and returns the file.
  static Future<File> createConfig(HardDriveSet install, String romFile) async {
    final File file = await ConfigStore.save(
      settingsFor(install, romFile),
      install.name.toLowerCase().contains('ags')
          ? install.name
          : 'AGS (${install.name})',
    );
    AppLog.info(
      'ags',
      '${install.driveCount} drives'
          '${install.sharedFolder.isEmpty ? '' : ' and a shared folder'}'
          ' from ${install.folder}',
    );
    return file;
  }
}
