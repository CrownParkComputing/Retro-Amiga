import 'dart:io';

import 'file_category.dart';
import 'media_library.dart';

/// A directory-backed Amiga installation or collection of hard-drive images.
///
/// This deliberately does not call every folder an AGS installation. A dated
/// WHDLoad collection and a user's own HDF folder need to be importable too;
/// only folders whose name/layout identifies AGS receive the AGS hardware
/// preset. The wizard can still mount any set in the order described here.
class HardDriveSet {
  const HardDriveSet({
    required this.folder,
    required this.bootDrive,
    required this.drives,
    this.sharedFolder = '',
    this.directoryMount = false,
  });

  final String folder;
  final String bootDrive;
  final List<String> drives;
  final String sharedFolder;

  /// True when the selected folder contains an Amiga filesystem rather than
  /// HDF images and should itself be mounted as DH0.
  final bool directoryMount;

  String get name => _basename(folder);

  int get driveCount => directoryMount ? 1 : 1 + drives.length;

  List<String> get allMounts => directoryMount
      ? <String>[folder]
      : <String>[
          bootDrive,
          ...drives,
          if (sharedFolder.isNotEmpty) sharedFolder,
        ];

  /// AGS_UAE and similarly named/layout-compatible packs need the accelerated
  /// RTG A1200 preset. A large ordinary HDF collection does not.
  bool get looksLikeAgs {
    final String lowerFolder = folder.toLowerCase();
    if (lowerFolder.contains('ags_uae') ||
        lowerFolder.contains('ags-uae') ||
        lowerFolder.contains('/ags') ||
        lowerFolder.endsWith('ags')) {
      return true;
    }
    if (directoryMount || driveCount < 4) return false;
    final String boot = _basename(bootDrive).toLowerCase();
    return sharedFolder.isNotEmpty &&
        (boot.contains('workbench') || boot.contains('system'));
  }

  /// Describes a folder containing HDF/HDZ/VHD/HDI files. Images may be a few
  /// levels down because real packs commonly wrap their payload in a dated
  /// release directory. Returns a directory mount when there are no images
  /// and [allowDirectoryMount] is true.
  static HardDriveSet? inspect(
    String folder, {
    int maxDepth = 4,
    bool allowDirectoryMount = false,
  }) {
    final Directory root = Directory(folder);
    if (!root.existsSync()) return null;

    final List<String> images = <String>[];
    final List<String> shared = <String>[];

    void walk(Directory directory, int depth) {
      if (depth > maxDepth) return;
      List<FileSystemEntity> entries;
      try {
        entries = directory.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final FileSystemEntity entry in entries) {
        final String name = _basename(entry.path);
        if (name.startsWith('.')) continue;
        if (entry is File &&
            FileCategory.fromPath(entry.path) == FileCategory.hardDrives) {
          images.add(entry.path);
        } else if (entry is Directory) {
          final String lower = name.toLowerCase();
          if (lower == 'shared' || lower == 'share') {
            shared.add(entry.path);
            // A shared AGS drive can hold tens of thousands of games and
            // saves. It is mounted as a directory; none of its contents can
            // be another HDF mount, so walking it only makes setup look hung.
            continue;
          }
          if (const <String>{
            'games',
            'game-data',
            'save-data',
            'savedata',
            'saves',
          }.contains(lower)) {
            continue;
          }
          walk(entry, depth + 1);
        }
      }
    }

    walk(root, 0);
    if (images.isEmpty) {
      return allowDirectoryMount
          ? HardDriveSet(
              folder: folder,
              bootDrive: folder,
              drives: const <String>[],
              directoryMount: true,
            )
          : null;
    }

    return fromPaths(folder, images, sharedFolders: shared);
  }

  /// Builds a set from files already present in the media index.
  static HardDriveSet? fromMediaFiles(String folder, List<MediaFile> files) {
    final List<String> paths = files
        .where((MediaFile file) => file.category == FileCategory.hardDrives)
        .map((MediaFile file) => file.path)
        .toList();
    if (paths.isEmpty) return null;
    final List<String> shared = <String>[
      for (final String name in const <String>[
        'Shared',
        'shared',
        'Share',
        'share',
      ])
        if (Directory('$folder/$name').existsSync()) '$folder/$name',
    ];
    return fromPaths(folder, paths, sharedFolders: shared);
  }

  static HardDriveSet fromPaths(
    String folder,
    List<String> paths, {
    List<String> sharedFolders = const <String>[],
  }) {
    final List<String> images = paths.toSet().toList()
      ..sort(
        (String a, String b) =>
            _basename(a).toLowerCase().compareTo(_basename(b).toLowerCase()),
      );

    const List<String> bootNames = <String>[
      'workbench',
      'system',
      'boot',
      'ags',
    ];
    String boot = '';
    for (final String candidate in bootNames) {
      boot = images.firstWhere(
        (String image) => _basename(image).toLowerCase().contains(candidate),
        orElse: () => '',
      );
      if (boot.isNotEmpty) break;
    }
    boot = boot.isEmpty ? images.first : boot;

    final List<String> shared = sharedFolders.toSet().toList()..sort();
    return HardDriveSet(
      folder: folder,
      bootDrive: boot,
      drives: images.where((String image) => image != boot).toList(),
      sharedFolder: shared.isEmpty ? '' : shared.first,
    );
  }

  static String _basename(String path) {
    final int slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
