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
            FileCategory.isHardDriveImage(
              entry.path,
              // inspect() is only used for a folder the user placed under
              // HardDrives, so a raw Zeb .img is unambiguously a hard disk.
              allowRawImage: true,
            )) {
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

  /// Names that mean "this drive is not the system": saves, data, spare room.
  ///
  /// Checked before falling back to size, because a games drive can easily be
  /// the biggest thing in the folder.
  static const List<String> _notBootNames = <String>[
    'save',
    'saves',
    'data',
    'work',
    'games',
    'music',
    'media',
    'shared',
    'spare',
  ];

  /// [sizes] maps an image path to its size in bytes, where the caller knows
  /// it. Used only to break a tie; absent, the old alphabetical order stands.
  static HardDriveSet fromPaths(
    String folder,
    List<String> paths, {
    List<String> sharedFolders = const <String>[],
    Map<String, int> sizes = const <String, int>{},
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

    if (boot.isEmpty) {
      // Nothing named itself the system drive, so choose rather than settle
      // for whatever sorts first.
      //
      // Alphabetical order is actively wrong here and quietly so. An
      // AmigaVision folder holds AmigaVision.hdf beside
      // AmigaVision-Saves.hdf, and '-' sorts before '.', so the FIRST image
      // is the 84MB saves drive -- which mounts perfectly, boots nothing, and
      // leaves the machine on the insert-disk screen with no clue that the
      // 10GB drive next to it was the one wanted.
      //
      // Skip the ones that name themselves as not-the-system, then take the
      // largest of what remains: a system drive is not the small one.
      final List<String> candidates = images
          .where(
            (String image) => !_notBootNames.any(
              _basename(image).toLowerCase().contains,
            ),
          )
          .toList();
      final List<String> pool = candidates.isEmpty ? images : candidates;
      pool.sort((String a, String b) {
        final int bySize = (sizes[b] ?? 0).compareTo(sizes[a] ?? 0);
        if (bySize != 0) return bySize;
        return _basename(a).toLowerCase().compareTo(_basename(b).toLowerCase());
      });
      boot = pool.first;
    }

    final List<String> shared = sharedFolders.toSet().toList()..sort();
    return HardDriveSet(
      folder: folder,
      bootDrive: boot,
      drives: images.where((String image) => image != boot).toList(),
      sharedFolder: shared.isEmpty ? '' : shared.first,
    );
  }

  /// Complete setups found below the library's `HardDrives` directory.
  ///
  /// A setup is one named child folder. Loose images directly in HardDrives
  /// stay separate choices; combining every top-level HDF into one pretend
  /// machine was the old scanner's most damaging false positive.
  static List<HardDriveSet> discoverIn(MediaIndex index, String hardDriveRoot) {
    final String root = hardDriveRoot
        .replaceAll(r'\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final Map<String, List<String>> grouped = <String, List<String>>{};
    final Map<String, int> sizes = <String, int>{};
    for (final MediaFile file in index.of(FileCategory.hardDrives)) {
      final String path = file.path.replaceAll(r'\', '/');
      if (!path.toLowerCase().startsWith('${root.toLowerCase()}/')) continue;
      final String relative = path.substring(root.length + 1);
      final int slash = relative.indexOf('/');
      if (slash <= 0) continue; // a loose image, not a packaged setup
      final String folder = '$root/${relative.substring(0, slash)}';
      grouped.putIfAbsent(folder, () => <String>[]).add(file.path);
      sizes[file.path] = file.size;
    }

    // Folders under HardDrives that hold no image at all are DIRECTORY
    // mounts: an Amiga volume as plain files, which is what a real hard disk
    // copied off the machine looks like, and what an installed Workbench with
    // its tools on it looks like. The core has always been able to mount one
    // -- config_generator writes filesystem2= for exactly this -- but nothing
    // ever offered one, because this function is built from the index's list
    // of hard-drive IMAGES and a folder of ordinary files contributes none.
    // So the setup existed, could be described, and was unreachable.
    //
    // That is the "add the option to select an HD directory, like in WinUAE"
    // request, and half of "I can't get WB 3.1 to boot and find a way to load
    // DOpus": both are a directory of files, not an HDF.
    //
    // No walk is needed to find them. The index has already been scanned, so
    // a child folder that contributed nothing to `grouped` contains no image
    // by definition -- which is the whole test.
    final List<HardDriveSet> directorySets = <HardDriveSet>[];
    try {
      for (final FileSystemEntity entry
          in Directory(root).listSync(followLinks: false)) {
        final String folder = entry.path.replaceAll(r'\', '/');
        final String name = _basename(folder);
        if (name.startsWith('.')) continue;
        if (grouped.containsKey(folder)) continue;
        // A SYMLINKED folder counts too, and has to be asked about rather
        // than type-tested.
        //
        // listSync(followLinks: false) reports a link to a directory as a
        // Link, not a Directory, so an `is! Directory` test silently drops
        // it -- and a symlink is exactly how someone points the library at a
        // 25GB distribution they already keep elsewhere instead of storing it
        // twice. Asking the path whether a directory exists there covers both
        // without following links anywhere else.
        final Directory directory = Directory(folder);
        if (!directory.existsSync()) continue;
        // An empty folder is somewhere the user has not put anything yet, not
        // a drive. Mounting it would give them an empty DH0 and no clue why.
        bool hasContents;
        try {
          hasContents = directory.listSync(followLinks: false).any(
            (FileSystemEntity child) => !_basename(child.path).startsWith('.'),
          );
        } on FileSystemException {
          continue;
        }
        if (!hasContents) continue;
        directorySets.add(
          HardDriveSet(
            folder: folder,
            bootDrive: folder,
            drives: const <String>[],
            directoryMount: true,
          ),
        );
      }
    } on FileSystemException {
      // No HardDrives folder yet, or no permission to list it. The image-based
      // sets below are unaffected.
    }

    final List<HardDriveSet> sets = <HardDriveSet>[
      ...directorySets,
      for (final MapEntry<String, List<String>> group in grouped.entries)
        fromPaths(
          group.key,
          group.value,
          sizes: sizes,
          sharedFolders: <String>[
            for (final String name in const <String>[
              'Shared',
              'shared',
              'Share',
              'share',
            ])
              if (Directory('${group.key}/$name').existsSync())
                '${group.key}/$name',
          ],
        ),
    ];
    sets.sort((HardDriveSet a, HardDriveSet b) {
      if (a.looksLikeAgs != b.looksLikeAgs) return a.looksLikeAgs ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sets;
  }

  /// Zeb's dated full-disk WHDLoad image. It is a 68020 Workbench setup, not
  /// an AGS/RTG collection, and its README explicitly requires Kickstarts in
  /// Devs:Kickstarts.
  bool get looksLikeZebWhdload {
    final String identity = <String>[
      folder,
      bootDrive,
      ...drives,
    ].join('/').toLowerCase();
    // The dated naming is what these actually ship as -- "A1200 WHDLoad
    // (15-Feb-2026)" -- and almost none of them say "zeb" anywhere. Requiring
    // that name meant the pack was never recognised as one.
    if (RegExp(r'whdload\s*\(').hasMatch(identity)) return true;
    return identity.contains('zeb') && identity.contains('whd');
  }

  static String _basename(String path) {
    final int slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
