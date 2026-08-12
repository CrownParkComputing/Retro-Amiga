import 'dart:io';

import 'package:archive/archive.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'file_category.dart';
import 'host_paths.dart';
import 'media_library.dart';

/// Where imported media lives, and what goes where inside it.
///
/// One folder with a known layout, rather than "wherever the file happened to
/// be". It is what makes the library stable - a scan of one tree instead of
/// the whole device - and it is what the emulator's own path settings expect.
///
/// The root is not forced into the app's private directory. On Android it can
/// be anywhere the user can write, so a collection that already exists stays
/// where it is and survives the app being uninstalled. iOS has no such choice:
/// the sandbox is the only place the app can read, so the root is fixed to
/// Documents, which is at least reachable from the Files app.
class MediaRoot {
  const MediaRoot._();

  static const String _prefsKey = 'media_root_path';

  /// Subfolder per kind, named as the core names its own.
  static const Map<FileCategory, String> folders = <FileCategory, String>{
    FileCategory.roms: 'Kickstarts',
    FileCategory.floppies: 'Floppies',
    FileCategory.hardDrives: 'HardDrives',
    FileCategory.cdImages: 'CDROMs',
    FileCategory.whdloadGames: 'LHA',
    FileCategory.music: 'Music',
    FileCategory.archives: 'Archives',
  };

  static String? _cached;

  /// The chosen root, or the best default if none has been chosen.
  static Future<String> path() async {
    final String? cached = _cached;
    if (cached != null) return cached;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(_prefsKey);
    if (stored != null && stored.isNotEmpty) {
      _cached = stored;
      return stored;
    }

    final String fallback = await defaultPath();
    _cached = fallback;
    return fallback;
  }

  static Future<void> setPath(String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
    _cached = value;
  }

  /// iOS can only use its own Documents directory; Android gets shared
  /// storage, so an existing collection is not copied for no reason.
  static Future<String> defaultPath() async {
    if (Platform.isAndroid) return '/sdcard/Amiga';
    return await HostPaths.documents();
  }

  static bool get canChoose => Platform.isAndroid;

  /// The folder in [index] that already holds the most media, if any.
  ///
  /// Suggested as the root so an existing collection - /sdcard/UAE4Arm on a
  /// device that has been running the old launcher - is adopted rather than
  /// copied. Importing into a root the files are already under moves nothing.
  static String? suggestFrom(MediaIndex index) {
    final Map<String, int> counts = <String, int>{};
    for (final MediaFile file in index.files) {
      if (file.category == FileCategory.archives) continue;
      final String directory = file.directory;
      if (directory.isEmpty) continue;
      // The parent, because media sits in per-kind subfolders: it is
      // /sdcard/UAE4Arm we want, not /sdcard/UAE4Arm/floppies.
      final int slash = directory.lastIndexOf('/');
      final String parent = slash <= 0 ? directory : directory.substring(0, slash);
      counts[parent] = (counts[parent] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;

    String best = counts.keys.first;
    for (final MapEntry<String, int> entry in counts.entries) {
      if (entry.value > (counts[best] ?? 0)) best = entry.key;
    }
    // A single stray file is not a collection.
    return (counts[best] ?? 0) >= 3 ? best : null;
  }

  static Future<Directory> folderFor(FileCategory category) async {
    final Directory dir =
        Directory('${await path()}/${folders[category] ?? 'Other'}');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}

/// What an import did.
class ImportResult {
  const ImportResult({
    required this.moved,
    required this.alreadyInPlace,
    required this.failed,
    this.extracted = 0,
  });

  final int moved;
  final int alreadyInPlace;
  final int failed;

  /// Disk images taken out of zips and written as real files.
  final int extracted;

  int get total => moved + alreadyInPlace + failed;
}

/// Files scanned media into the media root.
///
/// Moves rather than copies. Within one volume a move is a rename, so a 2GB
/// collection is filed instantly instead of being duplicated on a device that
/// may not have room for a second copy. Across volumes - SD card to internal -
/// it falls back to copy-then-delete, which is what rename would fail at.
class MediaImporter {
  const MediaImporter._();

  static Future<ImportResult> import(MediaIndex index) async {
    final String root = await MediaRoot.path();
    int moved = 0;
    int inPlace = 0;
    int failed = 0;

    for (final MediaFile file in index.files) {
      // Archives are not media. They are only worth keeping when they hold
      // WHDLoad's boot files, which install() handles separately.
      if (file.category == FileCategory.archives) continue;

      if (file.path.startsWith('$root/')) {
        inPlace++;
        continue;
      }

      final Directory target = await MediaRoot.folderFor(file.category);
      final String destination = '${target.path}/${file.name}';
      if (File(destination).existsSync()) {
        inPlace++;
        continue;
      }

      final File source = File(file.path);
      try {
        source.renameSync(destination);
        moved++;
      } on FileSystemException {
        // Different volume: rename cannot cross one.
        try {
          source.copySync(destination);
          source.deleteSync();
          moved++;
        } on FileSystemException {
          failed++;
        }
      }
    }

    final int extracted = await _extractArchives(index, root);

    return ImportResult(
      moved: moved,
      alreadyInPlace: inPlace,
      failed: failed,
      extracted: extracted,
    );
  }

  /// Unpacks disk images out of zips, so the library holds Amiga files rather
  /// than containers.
  ///
  /// Most Amiga collections are distributed zipped - a whole floppy library
  /// arrives as one .zip per disk - and the launcher used to either hide them
  /// or offer the zip itself. Neither is what anyone wants: the emulator can
  /// open some of them, but nothing else can tell you what is inside.
  ///
  /// Only archives already inside the media folder are opened. That is the
  /// difference between unpacking a user's Amiga disks and grinding through
  /// the 1800 Spectrum and C64 zips that also live on a handheld: if a zip
  /// sits in the Amiga folder, it is an Amiga zip.
  ///
  /// The zip is kept, moved aside into Archives/, rather than deleted. It is
  /// the user's file and the extraction may have missed something.
  static Future<int> _extractArchives(MediaIndex index, String root) async {
    int extracted = 0;

    for (final MediaFile file in index.files) {
      if (file.category != FileCategory.archives) continue;
      if (!file.path.startsWith('$root/')) continue;
      if (!file.name.toLowerCase().endsWith('.zip')) continue;

      final File source = File(file.path);
      if (!source.existsSync()) continue;

      List<ArchiveFile> entries;
      try {
        entries = ZipDecoder().decodeBytes(source.readAsBytesSync()).files;
      } on Object {
        // Not a zip, encrypted, or truncated: leave it alone.
        continue;
      }

      bool tookSomething = false;
      for (final ArchiveFile entry in entries) {
        if (!entry.isFile) continue;
        final String name = entry.name.split('/').last;
        final FileCategory? category = FileCategory.fromPath(name);
        // Only media, and never an archive inside an archive.
        if (category == null || category == FileCategory.archives) continue;

        final Directory target = await MediaRoot.folderFor(category);
        final File destination = File('${target.path}/$name');
        if (destination.existsSync()) {
          tookSomething = true;
          continue;
        }
        try {
          destination.writeAsBytesSync(entry.content as List<int>);
          extracted++;
          tookSomething = true;
        } on Object {
          // One bad entry should not lose the rest of the archive.
        }
      }

      if (tookSomething) {
        // Out of the way, but not destroyed.
        try {
          final Directory kept = await MediaRoot.folderFor(FileCategory.archives);
          source.renameSync('${kept.path}/${file.name}');
        } on FileSystemException {
          // Leaving it where it is only means it is scanned again.
        }
      }
    }

    return extracted;
  }
}
