import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';
import 'file_category.dart';
import 'hard_drive_set.dart';
import 'media_root.dart';

/// One file the user's granted folder holds.
class FolderEntry {
  const FolderEntry({
    required this.documentId,
    required this.name,
    required this.directory,
    required this.size,
  });

  /// The provider's handle for this file. Not a path: it only means anything
  /// passed back to the host alongside the granted tree.
  final String documentId;

  final String name;

  /// Folders between the picked root and this file, '' at the top.
  final String directory;

  final int size;
}

class FolderCopy {
  const FolderCopy({required this.entry, required this.destination});

  final FolderEntry entry;
  final String destination;
}

/// A folder the user picked, read through the Storage Access Framework.
///
/// Scoped storage will not let the app walk a folder like /sdcard/Amiga, and
/// the permission that would - MANAGE_EXTERNAL_STORAGE - is one Play gates
/// behind a review aimed at file managers, backup and antivirus apps. An
/// undeclared one blocks the release outright. So the user grants one folder
/// through the system picker instead, and that grant persists across restarts.
///
/// What comes back is a document tree, not a path. The emulator core opens
/// files with plain POSIX calls and cannot take a URI, so this is an import
/// source: [copyTo] writes the bytes into the app's own media folder, and
/// everything downstream - the core's paths, save disks, WHDLoad boot - is
/// unchanged.
class MediaFolder {
  const MediaFolder._();

  static const MethodChannel _channel = MethodChannel('uae4arm2026/emulator');

  /// Only Android needs this. iOS reads its own Documents folder directly, and
  /// a desktop has no scoped storage to work around.
  static bool get isSupported => Platform.isAndroid;

  /// The granted folder, or null if the user has not picked one.
  ///
  /// Asked of the system on every call rather than cached: a grant can be
  /// revoked in Settings, and carrying on with a dead URI looks exactly like
  /// the folder having been emptied.
  static Future<String?> granted() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('mediaFolderUri');
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> hasFolder() async => (await granted()) != null;

  /// The granted folder as something a person can recognise.
  ///
  /// A tree URI reads
  /// content://com.android.externalstorage.documents/tree/primary%3AAmiga,
  /// which tells the user nothing about whether they picked the right folder.
  /// The document id inside it is `primary:Amiga` for internal storage, or
  /// `[volume]:path` for an SD card, so it unpacks into something like
  /// /sdcard/Amiga. Falls back to the raw URI rather than guessing wrongly.
  static Future<String?> displayPath() async {
    final String? uri = await granted();
    return uri == null ? null : pathFromTreeUri(uri);
  }

  /// The readable path inside a tree URI. Pure, so it can be tested without a
  /// device: this is the part with the parsing bugs in it, not the channel.
  ///
  /// Anything unrecognised comes back as the URI it went in as. A wrong path
  /// shown confidently is worse than an ugly one, because the whole point of
  /// showing it is to let the user see they picked the wrong folder.
  @visibleForTesting
  static String pathFromTreeUri(String uri) {
    try {
      final int treeAt = uri.indexOf('/tree/');
      if (treeAt < 0) return uri;
      final String id = Uri.decodeComponent(uri.substring(treeAt + 6));
      final int colon = id.indexOf(':');
      if (colon < 0) return id;
      final String volume = id.substring(0, colon);
      final String path = id.substring(colon + 1);
      if (volume == 'primary') {
        return path.isEmpty ? '/sdcard' : '/sdcard/$path';
      }
      return path.isEmpty ? '/$volume' : '/$volume/$path';
    } on FormatException {
      return uri;
    }
  }

  /// Opens the system folder picker. Returns the granted folder, or null if
  /// the user backed out.
  static Future<String?> pick() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('pickMediaFolder');
    } on PlatformException catch (e) {
      AppLog.info('folder', 'picker refused: ${e.code}');
      return null;
    }
  }

  static Future<void> forget() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('forgetMediaFolder');
    } on PlatformException {
      // Nothing granted: nothing to forget.
    }
  }

  /// Everything under the granted folder.
  ///
  /// [fileLimit] is a guard, not a preference: a user who points this at the
  /// top of their storage should get a long list, not an out-of-memory crash.
  static Future<List<FolderEntry>> list({int fileLimit = 20000}) async {
    if (!isSupported) return const <FolderEntry>[];
    try {
      final List<Object?>? raw = await _channel.invokeMethod<List<Object?>>(
        'listMediaFolder',
        <String, Object>{'fileLimit': fileLimit},
      );
      if (raw == null) return const <FolderEntry>[];

      final List<FolderEntry> entries = <FolderEntry>[];
      for (final Object? item in raw) {
        if (item is! Map) continue;
        final String? id = item['documentId'] as String?;
        final String? name = item['name'] as String?;
        if (id == null || name == null) continue;
        entries.add(
          FolderEntry(
            documentId: id,
            name: name,
            directory: (item['directory'] as String?) ?? '',
            size: (item['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      AppLog.info('folder', '${entries.length} files in the granted folder');
      return entries;
    } on PlatformException catch (e) {
      AppLog.info('folder', 'listing failed: ${e.code}');
      return const <FolderEntry>[];
    }
  }

  /// Copies one entry into [destination], an ordinary path the core can open.
  static Future<bool> copyTo(FolderEntry entry, String destination) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'copyFromMediaFolder',
            <String, Object>{
              'documentId': entry.documentId,
              'destination': destination,
            },
          ) ??
          false;
    } on PlatformException catch (e) {
      AppLog.info('folder', 'copy of ${entry.name} failed: ${e.code}');
      return false;
    }
  }

  /// Copies a group through one platform call. Android previously created a
  /// fresh native thread for every file, which made a several-thousand-file
  /// HDF directory painfully slow and needlessly churned the runtime.
  static Future<List<bool>> copyBatch(List<FolderCopy> copies) async {
    if (!isSupported || copies.isEmpty) return const <bool>[];
    try {
      final List<Object?>? result = await _channel.invokeMethod<List<Object?>>(
        'copyFromMediaFolderBatch',
        <String, Object>{
          'copies': <Map<String, Object>>[
            for (final FolderCopy copy in copies)
              <String, Object>{
                'documentId': copy.entry.documentId,
                'destination': copy.destination,
              },
          ],
        },
      );
      return result?.map((Object? value) => value == true).toList() ??
          List<bool>.filled(copies.length, false);
    } on PlatformException catch (e) {
      AppLog.info('folder', 'batch copy failed: ${e.code}');
      return List<bool>.filled(copies.length, false);
    }
  }
}

/// Brings a granted folder's contents into the app's media root.
///
/// Copies rather than moves: the folder belongs to the user, not the app, and
/// a launcher that empties somebody's /sdcard/Amiga because they pointed at it
/// once is a launcher that eats collections. The cost is disk - the same file
/// exists twice - which is why anything already imported is skipped rather
/// than copied again on every scan.
class MediaFolderImporter {
  const MediaFolderImporter._();

  /// Copies everything recognisable, reporting progress as it goes.
  ///
  /// [onProgress] is called with (done, total) so a ten-thousand-file
  /// collection can show something other than a frozen screen.
  static Future<ImportResult> importAll({
    void Function(int done, int total)? onProgress,
  }) async {
    final List<FolderEntry> entries = await MediaFolder.list();

    // Only files the app knows what to do with. A granted folder may be the
    // top of somebody's storage, and copying every photo on the phone into an
    // Amiga library helps nobody.
    final List<_CategorisedFolderEntry> wanted = <_CategorisedFolderEntry>[
      for (final FolderEntry entry in entries)
        if (categoryFor(entry, entries) case final FileCategory category)
          _CategorisedFolderEntry(entry, category),
    ];

    int copied = 0;
    int alreadyThere = 0;
    int failed = 0;
    final List<FolderCopy> pending = <FolderCopy>[];

    for (final _CategorisedFolderEntry item in wanted) {
      final FolderEntry entry = item.entry;

      final Directory target = await MediaRoot.folderFor(item.category);
      final String relative = safeRelativeDirectory(entry.directory);
      final Directory destinationFolder = relative.isEmpty
          ? target
          : Directory('${target.path}/$relative');
      if (!destinationFolder.existsSync()) {
        destinationFolder.createSync(recursive: true);
      }
      final String destination = '${destinationFolder.path}/${entry.name}';

      final File existing = File(destination);
      if (existing.existsSync()) {
        // Same name and same length is the same file. Comparing bytes would
        // mean reading both copies of a 700MB hard drive image to learn
        // nothing, on every single scan.
        if (entry.size == 0 || existing.lengthSync() == entry.size) {
          alreadyThere++;
          continue;
        }
      }
      pending.add(FolderCopy(entry: entry, destination: destination));
    }

    const int batchSize = 128;
    for (int start = 0; start < pending.length; start += batchSize) {
      final int end = start + batchSize < pending.length
          ? start + batchSize
          : pending.length;
      final List<bool> results = await MediaFolder.copyBatch(
        pending.sublist(start, end),
      );
      for (final bool result in results) {
        if (result) {
          copied++;
        } else {
          failed++;
        }
      }
      onProgress?.call(alreadyThere + end, wanted.length);
    }
    onProgress?.call(wanted.length, wanted.length);

    AppLog.info(
      'folder',
      'imported $copied, $alreadyThere already present'
          '${failed > 0 ? ', $failed failed' : ''}',
    );
    return ImportResult(
      moved: copied,
      alreadyInPlace: alreadyThere,
      failed: failed,
    );
  }

  /// Imports a folder as an Amiga hard-drive collection.
  ///
  /// Unlike the general media import this deliberately keeps every file. A
  /// directory mounted as DH0 contains startup-sequences, tools and data with
  /// no Amiga-media extension, while an AGS shared directory may contain save
  /// data. Filtering either down to HDFs creates a pack that looks present but
  /// cannot boot or save.
  static Future<HardDriveFolderImport?> importHardDriveTree({
    void Function(int done, int total)? onProgress,
  }) async {
    final List<FolderEntry> entries = await MediaFolder.list();
    if (entries.isEmpty) return null;

    final String source = await MediaFolder.displayPath() ?? 'Imported drives';
    final List<String> sourceParts = source
        .replaceAll(r'\', '/')
        .split('/')
        .where((String part) => part.isNotEmpty)
        .toList();
    final String rawName = sourceParts.isEmpty
        ? 'Imported drives'
        : sourceParts.last;
    final String namespace = _safeComponent(rawName);
    final Directory hardDrives = await MediaRoot.folderFor(
      FileCategory.hardDrives,
    );
    final Directory collection = Directory('${hardDrives.path}/$namespace');
    if (!collection.existsSync()) collection.createSync(recursive: true);

    int copied = 0;
    int alreadyThere = 0;
    int failed = 0;
    final List<FolderCopy> pending = <FolderCopy>[];

    for (final FolderEntry entry in entries) {
      final String relative = safeRelativeDirectory(entry.directory);
      final Directory destinationFolder = relative.isEmpty
          ? collection
          : Directory('${collection.path}/$relative');
      final String destination =
          '${destinationFolder.path}/${_safeComponent(entry.name)}';
      final File existing = File(destination);
      if (existing.existsSync() &&
          (entry.size == 0 || existing.lengthSync() == entry.size)) {
        alreadyThere++;
        continue;
      }
      pending.add(FolderCopy(entry: entry, destination: destination));
    }

    const int batchSize = 128;
    for (int start = 0; start < pending.length; start += batchSize) {
      final int end = start + batchSize < pending.length
          ? start + batchSize
          : pending.length;
      final List<FolderCopy> batch = pending.sublist(start, end);
      final List<bool> results = await MediaFolder.copyBatch(batch);
      for (final bool result in results) {
        if (result) {
          copied++;
        } else {
          failed++;
        }
      }
      onProgress?.call(alreadyThere + end, entries.length);
    }
    onProgress?.call(entries.length, entries.length);

    final HardDriveSet? set = HardDriveSet.inspect(
      collection.path,
      allowDirectoryMount: true,
    );
    if (set == null) return null;
    final ImportResult result = ImportResult(
      moved: copied,
      alreadyInPlace: alreadyThere,
      failed: failed,
    );
    AppLog.info(
      'folder',
      'hard-drive collection ${set.name}: ${set.driveCount} mount(s), '
          '$copied copied, $alreadyThere already present, $failed failed',
    );
    return HardDriveFolderImport(set: set, result: result);
  }

  /// Classifies an entry with enough folder context to keep CD sets intact.
  ///
  /// CUE sheets refer to companion BIN/WAV/FLAC/MP3 tracks. A filename-only
  /// classifier sees BIN as a Kickstart and ignores the audio tracks, leaving
  /// a CD that appears in the shelf but cannot boot. If a directory contains
  /// a CUE, those companion files belong beside it in CDROMs.
  @visibleForTesting
  static FileCategory? categoryFor(
    FolderEntry entry,
    List<FolderEntry> allEntries,
  ) {
    final String extension = _extension(entry.name);
    const Set<String> cueCompanions = <String>{'bin', 'wav', 'flac', 'mp3'};
    if (cueCompanions.contains(extension)) {
      final bool hasCue = allEntries.any(
        (FolderEntry candidate) =>
            candidate.directory == entry.directory &&
            _extension(candidate.name) == 'cue',
      );
      if (hasCue) return FileCategory.cdImages;
    }
    return FileCategory.fromPath(entry.name);
  }

  /// Keeps the collection's folder structure without trusting provider names
  /// as filesystem paths. This prevents equally named disks in separate game
  /// folders overwriting each other and keeps AGS hard-drive sets together.
  @visibleForTesting
  static String safeRelativeDirectory(String directory) {
    return directory
        .replaceAll(r'\', '/')
        .split('/')
        .where(
          (String component) =>
              component.isNotEmpty && component != '.' && component != '..',
        )
        .map((String component) => component.replaceAll(':', '_'))
        .join('/');
  }

  static String _safeComponent(String value) {
    final String safe = value
        .replaceAll(RegExp(r'[/\\:\x00]'), '_')
        .replaceAll('..', '_')
        .trim();
    return safe.isEmpty ? 'Imported drives' : safe;
  }

  static String _extension(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }
}

class HardDriveFolderImport {
  const HardDriveFolderImport({required this.set, required this.result});

  final HardDriveSet set;
  final ImportResult result;
}

class _CategorisedFolderEntry {
  const _CategorisedFolderEntry(this.entry, this.category);

  final FolderEntry entry;
  final FileCategory category;
}
