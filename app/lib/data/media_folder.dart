import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';
import 'file_category.dart';
import 'hard_drive_set.dart';
import 'host_paths.dart';
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

/// Chooses a directory in the user's shared Amiga library.
///
/// Android's picker supplies the friendly UI, while all-files access lets
/// Dart and the native POSIX core use the selected path in place. No media is
/// copied into the application's Android/data directory.
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
      return path.isEmpty ? '/storage/$volume' : '/storage/$volume/$path';
    } on FormatException {
      return uri;
    }
  }

  /// Opens the system folder picker. Returns the granted folder, or null if
  /// the user backed out.
  static Future<String?> pick({String? initialSubfolder}) async {
    if (!isSupported) return null;
    try {
      // Every step of this says what it did.
      //
      // It is three decisions deep -- all-files access, then the picker, then
      // the grant -- and until now none of them left a trace. "I chose a
      // folder and nothing was granted" could have been any of the three, and
      // there was no way to tell them apart afterwards.
      if (!await HostPaths.hasSharedStorageAccess()) {
        AppLog.info('folder', 'no all-files access yet; asking');
        // Bounded, and the answer is re-checked rather than believed.
        //
        // requestSharedStorageAccess sends the user to a Settings screen and
        // is completed from onResume when they come back. If the activity is
        // recreated while they are away -- a rotation, a memory-hungry
        // Settings app -- the pending result dies with it and this await
        // never returns. The picker is never opened, the button appears to do
        // nothing, and there is no error anywhere: exactly the "I chose a
        // folder and nothing happened" report.
        //
        // So: wait, but not forever, and then ask the system directly what
        // the answer actually is. Returning from Settings having granted it
        // works whether or not the callback survived.
        await HostPaths.requestSharedStorageAccess().timeout(
          const Duration(seconds: 90),
          onTimeout: () => false,
        );
        if (!await HostPaths.hasSharedStorageAccess()) {
          AppLog.warn(
            'folder',
            'all-files access refused; the picker was never opened',
          );
          return null;
        }
        AppLog.info('folder', 'all-files access granted');
      }
      AppLog.info('folder', 'opening the folder picker');
      final String? uri = await _channel.invokeMethod<String>(
        'pickMediaFolder',
        <String, Object?>{'initialSubfolder': initialSubfolder},
      );
      if (uri == null) {
        AppLog.warn('folder', 'picker closed without a folder');
        return null;
      }
      AppLog.info('folder', 'granted ${pathFromTreeUri(uri)}');
      return uri;
    } on PlatformException catch (e) {
      AppLog.warn('folder', 'picker refused: ${e.code} ${e.message ?? ''}');
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
  /// [onCount] is called while the walk runs, with how many files it has
  /// seen. The enumeration is a single call that returns everything at once,
  /// so without polling the caller has nothing to show for the longest part
  /// of a scan -- a counter stuck on zero for a minute, which is what a hang
  /// looks like.
  static Future<List<FolderEntry>> list({
    int fileLimit = 20000,
    void Function(int found)? onCount,
  }) async {
    if (!isSupported) return const <FolderEntry>[];
    Timer? poll;
    try {
      if (onCount != null) {
        poll = Timer.periodic(const Duration(milliseconds: 250), (_) async {
          try {
            final int? n = await _channel.invokeMethod<int>(
              'mediaFolderScanCount',
            );
            if (n != null) onCount(n);
          } on PlatformException {
            // An older host without the counter: the walk still finishes,
            // it just cannot say how far along it is.
          } on MissingPluginException {
            // Ditto.
          }
        });
      }
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
    } finally {
      poll?.cancel();
    }
  }
}

/// Adopts a granted shared folder without moving or copying its contents.
class MediaFolderImporter {
  const MediaFolderImporter._();

  /// Makes the chosen folder the media root. Indexing happens separately.
  static Future<ImportResult> importAll({
    void Function(int done, int total)? onProgress,
  }) async {
    if (Platform.isAndroid) {
      if (!await HostPaths.hasSharedStorageAccess()) {
        throw StateError('shared Amiga library access has not been granted');
      }
      final String? source = await MediaFolder.displayPath();
      if (source != null && source.isNotEmpty) {
        await MediaRoot.setPath(source);
        AppLog.info('folder', 'using shared library in place at $source');
      }
      return const ImportResult(moved: 0, alreadyInPlace: 0, failed: 0);
    }

    return const ImportResult(moved: 0, alreadyInPlace: 0, failed: 0);
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
    if (Platform.isAndroid) {
      if (!await HostPaths.hasSharedStorageAccess()) {
        throw StateError('shared Amiga library access has not been granted');
      }
      final String? source = await MediaFolder.displayPath();
      if (source == null || source.isEmpty) return null;
      final HardDriveSet? set = await Isolate.run(
        () => HardDriveSet.inspect(source, allowDirectoryMount: true),
      );
      if (set == null) return null;
      AppLog.info('folder', 'using hard-drive collection in place at $source');
      return HardDriveFolderImport(
        set: set,
        result: const ImportResult(moved: 0, alreadyInPlace: 0, failed: 0),
      );
    }

    return null;
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
    final List<String> folders = entry.directory
        .replaceAll(r'\', '/')
        .split('/')
        .map((String part) => part.toLowerCase())
        .toList();
    if (extension == 'img' && folders.contains('harddrives')) {
      return FileCategory.hardDrives;
    }
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
