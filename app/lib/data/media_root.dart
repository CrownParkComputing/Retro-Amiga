import 'dart:io';

import 'package:archive/archive.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
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
    final bool oldAndroidSandbox =
        Platform.isAndroid &&
        stored != null &&
        stored.replaceAll(r'\', '/').contains('/Android/data/com.uae4arm2026/');
    if (stored != null &&
        stored.isNotEmpty &&
        !oldAndroidSandbox &&
        await _isUsable(stored)) {
      _cached = stored;
      return stored;
    }
    if (stored != null && stored.isNotEmpty) {
      // Stored by a build that still held all-files access, pointing at
      // somewhere like /sdcard/Amiga that this one cannot open. Left in place
      // it means an empty library and every import failing silently, so fall
      // back rather than honour a root that no longer works.
      AppLog.info('media', 'root $stored is unreadable now; using the default');
    }

    final String fallback = await defaultPath();
    _cached = fallback;
    return fallback;
  }

  /// Whether a root can actually be listed and written.
  ///
  /// Checked rather than assumed: the answer changed underneath existing
  /// installs when all-files access was dropped, and a root that cannot be
  /// read fails in the least helpful way possible - a library that is simply
  /// empty, with no error anywhere.
  static Future<bool> _isUsable(String path) async {
    try {
      final Directory dir = Directory(path);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      dir.listSync(followLinks: false).take(1).toList();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static Future<void> setPath(String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
    _cached = value;
  }

  /// iOS can only use its own Documents directory; Android gets shared
  /// storage, so an existing collection is not copied for no reason.
  ///
  /// A desktop gets a folder of its own, named for the app. Home and Documents
  /// are shared with everything else on the machine - the first run on this
  /// Linux box adopted another emulator's data directory as its library - and
  /// a launcher that files disks into somebody else's folders is worse than
  /// one that asks.
  static Future<String> defaultPath() async {
    // One shared library for every Retro application. The Android host
    // resolves primary storage (shown as "Odin2" on that handheld), and the
    // native core uses this exact path too. Media stays here in place; it is
    // never duplicated into Android/data.
    if (Platform.isAndroid) return await HostPaths.sharedAmigaDirectory();
    if (Platform.isIOS) return await HostPaths.documents();
    final Directory dir = Directory(
      '${Platform.environment['HOME'] ?? await HostPaths.documents()}'
      '/Amiga-Retro',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// Desktop only.
  ///
  /// iOS can only ever read its own Documents folder. Android could once be
  /// pointed anywhere, but that depended on all-files access; without it the
  /// only writable place is the app's own folder, so offering a choice would
  /// only let the user pick somewhere that silently fails. On Android the
  /// question is answered by the folder they pick to import FROM - the
  /// destination is an implementation detail, not a setting.
  static bool get canChoose => !Platform.isIOS && !Platform.isAndroid;

  /// Whether a collection found by the scan should be adopted as the root.
  ///
  /// Never, now.
  ///
  /// It existed for the Android device that already had /sdcard/UAE4Arm full
  /// of disks, back when all-files access made that folder usable as a root.
  /// Without that permission such a folder can be neither listed nor written,
  /// so adopting one would swap a working root for a broken one. On a desktop
  /// the busiest folder full of media is somebody else's emulator, which is
  /// exactly what happened the first time this ran on Linux.
  static bool get adoptsExistingCollection => false;

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
      final String parent = slash <= 0
          ? directory
          : directory.substring(0, slash);
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
    final Directory dir = Directory(
      '${await path()}/${folders[category] ?? 'Other'}',
    );
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

  /// [only], when given, files just those categories and leaves the rest
  /// where they lie. Launch passes the ROM categories alone: a Kickstart
  /// has to be in place before the core starts, while floppies and music
  /// are a collection the user may still be copying in.
  static Future<ImportResult> import(
    MediaIndex index, {
    Set<FileCategory>? only,
  }) async {
    final String root = await MediaRoot.path();
    int moved = 0;
    int inPlace = 0;
    int failed = 0;

    for (final MediaFile file in index.files) {
      // Archives are not media. They are only worth keeping when they hold
      // WHDLoad's boot files, which install() handles separately.
      if (file.category == FileCategory.archives) continue;
      if (only != null && !only.contains(file.category)) continue;

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

    AppLog.info(
      'import',
      'into $root: $moved moved, $inPlace already there'
          '${failed > 0 ? ', $failed failed' : ''}',
    );
    final int extracted = await _extractArchives(index, root, only);
    if (extracted > 0) {
      AppLog.info('import', '$extracted disk images unpacked from zips');
    }

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
  /// A zip that gave up everything it recognisably held is deleted - the
  /// app's folder is a drop zone, not a museum of spent archives, and the
  /// reference zips live on the machine that built them. One that still
  /// holds something unrecognised is kept, moved aside into Archives/.
  static Future<int> _extractArchives(
    MediaIndex index,
    String root,
    Set<FileCategory>? only,
  ) async {
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
      bool owes = false;
      for (final ArchiveFile entry in entries) {
        if (!entry.isFile) continue;
        final String name = entry.name.split('/').last;
        final FileCategory? category = FileCategory.fromPath(name);
        // Only media, and never an archive inside an archive.
        if (category == null || category == FileCategory.archives) {
          owes = true;
          continue;
        }
        // Not wanted on this pass: the zip keeps it, and so keeps itself.
        if (only != null && !only.contains(category)) {
          owes = true;
          continue;
        }

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
          owes = true; // One bad entry should not lose the rest.
        }
      }

      if (tookSomething) {
        try {
          if (owes) {
            // Something unrecognised is still inside: out of the way,
            // but not destroyed.
            final Directory kept = await MediaRoot.folderFor(
              FileCategory.archives,
            );
            source.renameSync('${kept.path}/${file.name}');
          } else {
            source.deleteSync();
          }
        } on FileSystemException {
          // Leaving it where it is only means it is scanned again.
        }
      }
    }

    return extracted;
  }
}
